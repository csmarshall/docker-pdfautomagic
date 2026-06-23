#!/bin/bash
set -euo pipefail

SCRIPT=$(basename ${0})
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCAN_DIR="${1}"
RAW_SCAN_DIR="${1}/unprocessed"
LOCK_FILE="/tmp/${SCRIPT}.lock"
MINUTES_OLD="${MINUTES_OLD:-1}"
MAX_PARALLEL_JOBS="${MAX_PARALLEL_JOBS:-1}"

# OCR configuration
ROTATE_PAGES_THRESHOLD="${ROTATE_PAGES_THRESHOLD:-7.5}"  # Confidence threshold for auto-rotation (0-15+)

# Detection configuration (enabled by default in full image)
ENABLE_DETECTION="${ENABLE_DETECTION:-true}"
ENABLE_CLASSIFICATION="${ENABLE_CLASSIFICATION:-true}"
DETECTION_SCRIPT="${SCRIPT_DIR}/detection/split_pdf.py"
DETECTION_VENV="${SCRIPT_DIR}/detection/.venv"
USING_CPU_FALLBACK="false"  # Set to true if no GPU detected

# Detection reliability (Phase 3): auto-disable after repeated failures + backoff
# DETECTION_FAILURE_THRESHOLD: number of consecutive failed runs before detection
#   is auto-disabled and we fall back to plain OCR (0 disables this safety net).
# DETECTION_BACKOFF_MINUTES: once auto-disabled, minimum gap between re-logging
#   the warning, so a per-minute scan loop doesn't spam logs/notifications.
# State files live in /tmp so they persist across runs for the container's
# lifetime and reset on restart. Delete DETECTION_STATE_FILE to reset manually.
DETECTION_FAILURE_THRESHOLD="${DETECTION_FAILURE_THRESHOLD:-3}"
DETECTION_BACKOFF_MINUTES="${DETECTION_BACKOFF_MINUTES:-15}"
DETECTION_STATE_FILE="${DETECTION_STATE_FILE:-/tmp/pdfautomagic.detection-failures}"
DETECTION_BACKOFF_FILE="${DETECTION_BACKOFF_FILE:-/tmp/pdfautomagic.detection-backoff}"
DETECTION_RUN_MARKER=""  # Per-run temp file recording detection outcomes (set below)

# Ollama configuration (runs as process in same container)
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
OLLAMA_MODELS="${OLLAMA_MODELS:-/usr/share/ollama/models}"  # Where models are baked in
OLLAMA_STARTED_BY_US="false"

# Detection metrics (for post-processing hooks)
TOTAL_PAGES_SCANNED=0
TOTAL_BLANKS_REMOVED=0
TOTAL_DOCS_CREATED=0

ts () {
    echo -n "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ${SCRIPT} - " >&2
    echo $* >&2
}

# Start Ollama process on-demand (runs in same container)
# Returns 0 if Ollama is ready, 1 if failed to start
start_ollama() {
    # Check if ollama binary is available
    if ! command -v ollama &>/dev/null; then
        ts "WARNING: Ollama not installed, detection will not work"
        return 1
    fi

    # Check if already running
    if pgrep -x "ollama" >/dev/null 2>&1; then
        ts "Ollama process already running"
        return 0
    fi

    ts "Starting Ollama process..."

    # Create writable home directory for Ollama runtime state (keys, etc)
    # Ollama uses $HOME/.ollama for config, so we set HOME to /tmp
    mkdir -p /tmp/.ollama

    # Start ollama serve in background
    # OLLAMA_KEEP_ALIVE=0 means model unloads immediately after each request
    # OLLAMA_MODELS points to baked-in models, HOME=/tmp for writable config dir
    export OLLAMA_MODELS HOME=/tmp
    OLLAMA_KEEP_ALIVE=0 ollama serve >/dev/null 2>&1 &
    OLLAMA_STARTED_BY_US="true"

    # Wait for Ollama API to be ready (max 30 seconds)
    ts "Waiting for Ollama API..."
    local WAIT_COUNT=0
    local MAX_WAIT=30
    while [[ ${WAIT_COUNT} -lt ${MAX_WAIT} ]]; do
        if curl -s "${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
            ts "Ollama API ready"
            return 0
        fi
        sleep 1
        WAIT_COUNT=$((WAIT_COUNT + 1))
    done

    ts "ERROR: Ollama API did not become ready within ${MAX_WAIT} seconds"
    return 1
}

# Stop Ollama process (only if we started it)
stop_ollama() {
    if [[ "${OLLAMA_STARTED_BY_US}" != "true" ]]; then
        # We didn't start it, don't stop it
        return 0
    fi

    ts "Stopping Ollama process..."
    pkill -x "ollama" 2>/dev/null || true
    OLLAMA_STARTED_BY_US="false"
}

# --- Detection failure tracking (Phase 3 reliability) -----------------------
# The consecutive-failure count persists across runs (state file) so detection
# can be auto-disabled when the GPU/model is repeatedly failing, then recover.

get_detection_failures() {
    cat "${DETECTION_STATE_FILE}" 2>/dev/null || echo 0
}

set_detection_failures() {
    echo "${1}" > "${DETECTION_STATE_FILE}" 2>/dev/null || true
}

# Record one detection outcome ("success"|"failure") for the current run.
# Appends to a per-run marker file so parallel jobs can each record safely
# (single-byte appends under O_APPEND are atomic).
record_detection_outcome() {
    [[ -n "${DETECTION_RUN_MARKER}" ]] || return 0
    case "${1}" in
        success) echo "S" >> "${DETECTION_RUN_MARKER}" ;;
        failure) echo "F" >> "${DETECTION_RUN_MARKER}" ;;
    esac
}

# True while within the backoff window since the last auto-disable warning.
in_detection_backoff() {
    local last now
    last=$(cat "${DETECTION_BACKOFF_FILE}" 2>/dev/null || echo 0)
    now=$(date +%s)
    [[ $(( now - last )) -lt $(( DETECTION_BACKOFF_MINUTES * 60 )) ]]
}

# Check if detection is available and configured
check_detection_available() {
    if [[ "${ENABLE_DETECTION}" != "true" ]]; then
        return 1
    fi

    # Auto-disable safety net: after several consecutive failed runs, stop
    # attempting detection and fall back to plain OCR. Re-check the GPU each
    # run so we auto-recover the moment it comes back.
    local FAILS
    FAILS=$(get_detection_failures)
    if [[ "${DETECTION_FAILURE_THRESHOLD}" -gt 0 ]] && [[ "${FAILS}" -ge "${DETECTION_FAILURE_THRESHOLD}" ]]; then
        if [[ -x "${DETECTION_VENV}/bin/python" ]] && \
           "${DETECTION_VENV}/bin/python" "${DETECTION_SCRIPT}" --check-gpu >/dev/null 2>&1; then
            ts "Detection recovered (GPU check passed) - clearing failure count (was ${FAILS})"
            set_detection_failures 0
            rm -f "${DETECTION_BACKOFF_FILE}"
        else
            if ! in_detection_backoff; then
                ts "========================================================================"
                ts "WARNING: AI detection AUTO-DISABLED after ${FAILS} consecutive failures"
                ts "         Falling back to standard OCR until the GPU/model recovers."
                ts "         Manual reset: delete ${DETECTION_STATE_FILE}"
                ts "========================================================================"
                date +%s > "${DETECTION_BACKOFF_FILE}" 2>/dev/null || true
            fi
            return 1
        fi
    fi

    if [[ ! -f "${DETECTION_SCRIPT}" ]]; then
        ts "WARNING: Detection enabled but script not found: ${DETECTION_SCRIPT}"
        return 1
    fi

    if [[ ! -d "${DETECTION_VENV}" ]]; then
        ts "WARNING: Detection enabled but venv not found: ${DETECTION_VENV}"
        return 1
    fi

    # Check GPU availability, fall back to CPU with warning
    if ! "${DETECTION_VENV}/bin/python" "${DETECTION_SCRIPT}" --check-gpu >/dev/null 2>&1; then
        ts "========================================================================"
        ts "WARNING: No GPU detected - AI detection will use CPU (VERY SLOW ~10x)"
        ts "========================================================================"
        ts ""
        ts "Options to resolve this:"
        ts "  1. Install GPU drivers (NVIDIA: nvidia-container-toolkit, AMD: ROCm)"
        ts "  2. Use the lite image for basic OCR without AI detection:"
        ts "     docker compose -f docker-compose.lite.yml up -d"
        ts "  3. Set ENABLE_DETECTION=false to disable detection"
        ts ""
        ts "Continuing with CPU processing..."
        ts "========================================================================"
        USING_CPU_FALLBACK="true"
    fi

    return 0
}

# Detect and split a PDF into multiple documents
# Returns: path to directory containing split PDFs, or empty if detection failed/skipped
detect_and_split_pdf() {
    local INPUT_FILE="${1}"
    local SPLIT_OUTPUT_DIR=$(mktemp -d)

    local CLASSIFY_FLAG=""
    if [[ "${ENABLE_CLASSIFICATION}" == "true" ]]; then
        CLASSIFY_FLAG="--classify"
    fi

    ts "Detecting documents in ${INPUT_FILE}..."

    # Run detection and capture JSON output (stdout only, stderr goes to logs)
    local SPLIT_RESULT
    if SPLIT_RESULT=$("${DETECTION_VENV}/bin/python" "${DETECTION_SCRIPT}" \
        "${INPUT_FILE}" \
        --output-dir "${SPLIT_OUTPUT_DIR}" \
        ${CLASSIFY_FLAG} \
        --allow-cpu \
        --json); then

        # Parse metrics from JSON
        local PAGES_IN=$(echo "${SPLIT_RESULT}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pages_input', 0))" 2>/dev/null || echo "0")
        local BLANKS=$(echo "${SPLIT_RESULT}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pages_blank_removed', 0))" 2>/dev/null || echo "0")
        local DOCS=$(echo "${SPLIT_RESULT}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('documents_output', 0))" 2>/dev/null || echo "0")

        # Update global metrics
        TOTAL_PAGES_SCANNED=$((TOTAL_PAGES_SCANNED + PAGES_IN))
        TOTAL_BLANKS_REMOVED=$((TOTAL_BLANKS_REMOVED + BLANKS))
        TOTAL_DOCS_CREATED=$((TOTAL_DOCS_CREATED + DOCS))

        ts "Detection complete: ${PAGES_IN} pages -> ${DOCS} documents (${BLANKS} blanks removed)"

        record_detection_outcome success
        echo "${SPLIT_OUTPUT_DIR}"
        return 0
    else
        ts "ERROR: Detection failed for ${INPUT_FILE}"
        ts "Detection output: ${SPLIT_RESULT}"
        record_detection_outcome failure
        rm -rf "${SPLIT_OUTPUT_DIR}"
        echo ""
        return 1
    fi
}

cleanup_lock () {
    if [[ -e "${LOCK_FILE}" ]] ; then
        ts "Removing lock ${LOCK_FILE}"
        rm ${LOCK_FILE}
    fi
}

clean_up () {
    EXIT_CODE=${1:-0}
    stop_ollama  # Stop Ollama if we started it on-demand
    cleanup_lock
    [[ -n "${DETECTION_RUN_MARKER}" ]] && rm -f "${DETECTION_RUN_MARKER}"
    ts "Done"
    exit ${EXIT_CODE}
}

# Clean up lock file on exit, interrupt, or termination
trap cleanup_lock EXIT SIGHUP SIGINT SIGTERM

if [[ -e "${LOCK_FILE}" ]]; then
    LOCK_PID=$(cat "${LOCK_FILE}" 2>/dev/null || echo "")
    if [[ -n "${LOCK_PID}" ]] && kill -0 "${LOCK_PID}" 2>/dev/null; then
        ts "Already running under pid ${LOCK_PID}"
        exit 0
    else
        ts "Removing stale lock file (pid ${LOCK_PID} not running)"
        rm -f "${LOCK_FILE}"
    fi
fi
echo $$ > "${LOCK_FILE}"


if [[ ! -d ${1} ]]; then
    ts "Provided scan dir"
    echo "${0} /usr/local/scans"
    clean_up 1
fi

ts "Start"

ts "Inspecting files in ${RAW_SCAN_DIR} for files modified more than ${MINUTES_OLD} minutes ago"

FILES_TO_SCAN=$(find ${RAW_SCAN_DIR} -maxdepth 1 -mmin +${MINUTES_OLD} -type f 2>/dev/null)
NUM_FILES_TO_SCAN=$(echo ${FILES_TO_SCAN} | wc -w)

if [[ "${NUM_FILES_TO_SCAN}" > "0" ]]; then
    ts "Found ${NUM_FILES_TO_SCAN} to scan in ${RAW_SCAN_DIR}"
    PROCESSING_START_TIME=$(date +%s)
else
    ts "No files found in ${RAW_SCAN_DIR}, exiting"
    clean_up 0
fi

for PROCESS_DIR in originals processed
do
    if [[ ! -d "${SCAN_DIR}/${PROCESS_DIR}" ]]; then
        ts "${SCAN_DIR}/${PROCESS_DIR} directory not found, creating"
        mkdir ${SCAN_DIR}/${PROCESS_DIR}
    else
        ts "${SCAN_DIR}/${PROCESS_DIR} found"
    fi
done

DATE=$(date +"%Y/%m/%d")

OUTPUT_DIR="${SCAN_DIR}/processed/${DATE}"
ORIGINALS_DIR="${SCAN_DIR}/originals/${DATE}"

ts "Validating ${OUTPUT_DIR}"
if [ ! -d ${OUTPUT_DIR} ] || [ ! -d ${ORIGINALS_DIR} ] ; then
    ts "Missing ${OUTPUT_DIR}, creating it..."
    mkdir -p ${OUTPUT_DIR}
    mkdir -p ${ORIGINALS_DIR}
else
    ts "Output Directory: ${OUTPUT_DIR} present"
fi

# Function to OCR a single file (internal - use process_file instead)
ocr_file() {
    local INPUT_FILE="${1}"
    local OUTPUT_FILE="${2}"

    # Warn if overwriting existing file
    if [[ -f "${OUTPUT_FILE}" ]]; then
        ts "WARNING: Overwriting existing file: $(basename ${OUTPUT_FILE})"
    fi

    ts "OCR: ${INPUT_FILE} -> ${OUTPUT_FILE}"

    if /usr/bin/ocrmypdf --force-ocr --deskew --clean --rotate-pages --rotate-pages-threshold ${ROTATE_PAGES_THRESHOLD} "${INPUT_FILE}" "${OUTPUT_FILE}" 2>&1 | while IFS= read -r line; do
        [[ -n "$line" ]] && echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ocrmypdf -   $line" || true
    done; then
        ts "OCR successful for $(basename ${INPUT_FILE})"
        return 0
    else
        ts "ERROR: OCR failed for ${INPUT_FILE}"
        [[ -f "${OUTPUT_FILE}" ]] && rm -f "${OUTPUT_FILE}"
        return 1
    fi
}

# Function to process a single file (with optional detection)
process_file() {
    local INPUT_FILE="${1}"
    local BASENAME=$(basename "${INPUT_FILE}")
    local FILENAME="${BASENAME%.*}"

    # Skip if file is empty
    if [[ ! -f "${INPUT_FILE}" ]] || [[ ! -s "${INPUT_FILE}" ]]; then
        ts "Skipping invalid or empty file: ${INPUT_FILE}"
        return 1
    fi

    ts "Processing ${INPUT_FILE}"

    # Check if detection is enabled and available
    if [[ "${DETECTION_AVAILABLE}" == "true" ]]; then
        # Detect and split the PDF first
        local SPLIT_DIR
        SPLIT_DIR=$(detect_and_split_pdf "${INPUT_FILE}")

        if [[ -n "${SPLIT_DIR}" ]] && [[ -d "${SPLIT_DIR}" ]]; then
            # Process each split document
            local SPLIT_SUCCESS=true
            for SPLIT_FILE in "${SPLIT_DIR}"/*.pdf; do
                if [[ -f "${SPLIT_FILE}" ]]; then
                    local SPLIT_BASENAME=$(basename "${SPLIT_FILE}")
                    local SPLIT_FILENAME="${SPLIT_BASENAME%.*}"
                    local OUTPUT_FILE="${OUTPUT_DIR}/${SPLIT_FILENAME}.pdf"

                    if ! ocr_file "${SPLIT_FILE}" "${OUTPUT_FILE}"; then
                        SPLIT_SUCCESS=false
                    fi
                fi
            done

            # Clean up temp split directory
            rm -rf "${SPLIT_DIR}"

            if [[ "${SPLIT_SUCCESS}" == "true" ]]; then
                ts "Moving original ${INPUT_FILE} to ${ORIGINALS_DIR}"
                mv "${INPUT_FILE}" "${ORIGINALS_DIR}"
                return 0
            else
                ts "ERROR: Some split documents failed OCR for ${INPUT_FILE}"
                return 1
            fi
        else
            ts "WARNING: Detection failed, falling back to standard OCR"
            # Fall through to standard processing
        fi
    fi

    # Standard processing (no detection or detection failed)
    local OUTPUT_FILE="${OUTPUT_DIR}/ocr${FILENAME}_$(date +"%F-%H%M%S").pdf"

    if ocr_file "${INPUT_FILE}" "${OUTPUT_FILE}"; then
        ts "Moving ${INPUT_FILE} to ${ORIGINALS_DIR}"
        mv "${INPUT_FILE}" "${ORIGINALS_DIR}"
        return 0
    else
        ts "ERROR: OCR failed for ${INPUT_FILE}, leaving in place for retry"
        return 1
    fi
}

# Start Ollama on-demand if detection is enabled and files were found
if [[ "${ENABLE_DETECTION}" == "true" ]] && [[ "${NUM_FILES_TO_SCAN}" -gt 0 ]]; then
    if ! start_ollama; then
        ts "WARNING: Could not start Ollama, detection will be disabled"
    fi
fi

# Check if detection is available at startup
DETECTION_AVAILABLE="false"
if check_detection_available; then
    ts "Document detection: ENABLED"
    if [[ "${ENABLE_CLASSIFICATION}" == "true" ]]; then
        ts "Document classification: ENABLED"
    fi
    DETECTION_AVAILABLE="true"
else
    if [[ "${ENABLE_DETECTION}" == "true" ]]; then
        ts "Document detection: DISABLED (not available - check warnings above)"
    else
        ts "Document detection: DISABLED (not enabled)"
    fi
fi

# Per-run marker file recording each detection success/failure (used after the
# run to update the consecutive-failure counter). Parallel jobs append to it.
DETECTION_RUN_MARKER="$(mktemp)"
export DETECTION_RUN_MARKER

# Export function and variables for use in subshells
export -f process_file
export -f ocr_file
export -f ts
export -f detect_and_split_pdf
export -f record_detection_outcome
export -f start_ollama
export -f stop_ollama
export OUTPUT_DIR ORIGINALS_DIR SCRIPT DETECTION_AVAILABLE
export ENABLE_CLASSIFICATION DETECTION_SCRIPT DETECTION_VENV USING_CPU_FALLBACK
export TOTAL_PAGES_SCANNED TOTAL_BLANKS_REMOVED TOTAL_DOCS_CREATED
export OLLAMA_HOST OLLAMA_MODELS OLLAMA_STARTED_BY_US

ts "Processing with MAX_PARALLEL_JOBS=${MAX_PARALLEL_JOBS}"

# Track PIDs of processing jobs (not Ollama)
PROCESS_PIDS=()

# Process files in parallel
for INPUT_FILE in ${FILES_TO_SCAN}; do
    # Wait if we've hit the parallel job limit
    while [ $(jobs -r | wc -l) -ge ${MAX_PARALLEL_JOBS} ]; do
        sleep 0.1
    done

    # Start processing in background and capture PID
    process_file "${INPUT_FILE}" &
    PROCESS_PIDS+=($!)
done

# Wait for all processing jobs to complete (not Ollama)
ts "Waiting for ${#PROCESS_PIDS[@]} processing job(s) to complete..."
set +e  # Temporarily disable exit on error for wait
for PID in "${PROCESS_PIDS[@]}"; do
    wait ${PID}
done
WAIT_EXIT=$?
set -e  # Re-enable exit on error
ts "Wait completed with exit code: ${WAIT_EXIT}"

ts "All files processed"

# --- Phase 3: tally detection outcomes and update the failure counter -------
DETECTION_FAILURES_THIS_RUN=0
DETECTION_SUCCESSES_THIS_RUN=0
if [[ -f "${DETECTION_RUN_MARKER}" ]]; then
    # grep -c always prints a count; || true swallows its exit-1-on-zero-matches
    DETECTION_FAILURES_THIS_RUN=$(grep -c '^F' "${DETECTION_RUN_MARKER}" 2>/dev/null || true)
    DETECTION_SUCCESSES_THIS_RUN=$(grep -c '^S' "${DETECTION_RUN_MARKER}" 2>/dev/null || true)
fi

# Reset on any success (detection works); increment only when detection was
# attempted and every attempt failed (detection appears broken).
DETECTION_CONSECUTIVE_FAILURES=$(get_detection_failures)
if [[ "${DETECTION_SUCCESSES_THIS_RUN}" -gt 0 ]]; then
    if [[ "${DETECTION_CONSECUTIVE_FAILURES}" -ne 0 ]]; then
        ts "Detection succeeded - resetting consecutive failure count (was ${DETECTION_CONSECUTIVE_FAILURES})"
    fi
    set_detection_failures 0
    rm -f "${DETECTION_BACKOFF_FILE}"
    DETECTION_CONSECUTIVE_FAILURES=0
elif [[ "${DETECTION_FAILURES_THIS_RUN}" -gt 0 ]]; then
    DETECTION_CONSECUTIVE_FAILURES=$(( DETECTION_CONSECUTIVE_FAILURES + 1 ))
    set_detection_failures "${DETECTION_CONSECUTIVE_FAILURES}"
    ts "Detection failed this run - consecutive failures: ${DETECTION_CONSECUTIVE_FAILURES}/${DETECTION_FAILURE_THRESHOLD}"
fi

# Overall status exposed to notification hooks
if [[ "${DETECTION_FAILURES_THIS_RUN}" -gt 0 ]] && [[ "${DETECTION_SUCCESSES_THIS_RUN}" -eq 0 ]]; then
    SCAN_STATUS="failure"
elif [[ "${DETECTION_FAILURES_THIS_RUN}" -gt 0 ]] || [[ "${WAIT_EXIT}" -ne 0 ]]; then
    SCAN_STATUS="partial"
else
    SCAN_STATUS="success"
fi

RCLONE_REMOTE="${RCLONE_REMOTE:-Dropbox:Cabinet/Documents}"
ts "Rclone to ${RCLONE_REMOTE}"
/usr/bin/rclone copy --config /config/rclone.conf -v \
    --exclude ".DS_Store" \
    --exclude ".AppleDouble/**" \
    --exclude "._*" \
    ${SCAN_DIR}/processed ${RCLONE_REMOTE}

ts "Running post-processing commands"
POST_SCAN_DIR="/config/post-scan-commands"
if [[ -d "${POST_SCAN_DIR}" ]]; then
    NUM_FILES=$(echo ${FILES_TO_SCAN} | wc -w)

    # Export environment variables for post-scan commands
    export FILES_PROCESSED="${NUM_FILES}"
    export RCLONE_REMOTE="${RCLONE_REMOTE}"
    export OUTPUT_DIR="${OUTPUT_DIR}"
    export ORIGINALS_DIR="${ORIGINALS_DIR}"
    export PROCESSING_DATE="${DATE}"
    export SCAN_DIR="${SCAN_DIR}"

    # Timestamp variables
    export TZ="${TZ:-UTC}"  # Container timezone (e.g., America/Chicago)
    export DATE="$(date +"%Y-%m-%d")"
    export TIME="$(date +"%H:%M:%S")"
    export DATETIME="$(date +"%Y-%m-%dT%H:%M:%S%z")"  # ISO8601 with timezone offset

    # Detection metrics (available when ENABLE_DETECTION=true)
    export DETECTION_ENABLED="${DETECTION_AVAILABLE}"
    export PAGES_SCANNED="${TOTAL_PAGES_SCANNED}"
    export BLANK_PAGES_REMOVED="${TOTAL_BLANKS_REMOVED}"
    export DOCUMENTS_CREATED="${TOTAL_DOCS_CREATED}"
    export CLASSIFICATION_ENABLED="${ENABLE_CLASSIFICATION}"

    # Detection reliability status (Phase 3) - lets hooks notify on success vs
    # failure. SCAN_STATUS is one of: success | partial | failure.
    export SCAN_STATUS="${SCAN_STATUS:-success}"
    export DETECTION_FAILURES="${DETECTION_FAILURES_THIS_RUN:-0}"
    export DETECTION_CONSECUTIVE_FAILURES="${DETECTION_CONSECUTIVE_FAILURES:-0}"
    if [[ "${DETECTION_FAILURE_THRESHOLD}" -gt 0 ]] && \
       [[ "${DETECTION_CONSECUTIVE_FAILURES:-0}" -ge "${DETECTION_FAILURE_THRESHOLD}" ]]; then
        export DETECTION_AUTO_DISABLED="true"
    else
        export DETECTION_AUTO_DISABLED="false"
    fi

    # Timing metrics
    PROCESSING_END_TIME=$(date +%s)
    PROCESSING_DURATION_SECONDS=$((PROCESSING_END_TIME - PROCESSING_START_TIME))
    PROCESSING_MINUTES=$((PROCESSING_DURATION_SECONDS / 60))
    PROCESSING_SECS=$((PROCESSING_DURATION_SECONDS % 60))
    export PROCESSING_DURATION_SECONDS
    export PROCESSING_DURATION="${PROCESSING_MINUTES}m ${PROCESSING_SECS}s"

    # Calculate per-page timing (use PAGES_SCANNED if detection, otherwise estimate 1 page per file)
    if [[ "${TOTAL_PAGES_SCANNED}" -gt 0 ]]; then
        TOTAL_PAGES="${TOTAL_PAGES_SCANNED}"
    else
        TOTAL_PAGES="${NUM_FILES}"
    fi
    if [[ "${TOTAL_PAGES}" -gt 0 ]]; then
        SECONDS_PER_PAGE=$(echo "scale=2; ${PROCESSING_DURATION_SECONDS} / ${TOTAL_PAGES}" | bc 2>/dev/null || echo "0")
    else
        SECONDS_PER_PAGE="0"
    fi
    export SECONDS_PER_PAGE

    ts "Processing complete in ${PROCESSING_DURATION} (${SECONDS_PER_PAGE}s/page)"

    for cmd in ${POST_SCAN_DIR}/*; do
        if [[ -x "${cmd}" ]]; then
            CMD_NAME=$(basename ${cmd})
            ts "Executing ${CMD_NAME}"
            if [[ "${DETECTION_AVAILABLE}" == "true" ]]; then
                echo "${NUM_FILES} scans -> ${TOTAL_DOCS_CREATED} documents (${TOTAL_BLANKS_REMOVED} blanks removed) uploaded to ${RCLONE_REMOTE}" | ${cmd} 2>&1 | while IFS= read -r line; do
                    [[ -n "$line" ]] && echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] post-scan/${CMD_NAME} - $line"
                done || true
            else
                echo "${NUM_FILES} files OCRd and uploaded to ${RCLONE_REMOTE}" | ${cmd} 2>&1 | while IFS= read -r line; do
                    [[ -n "$line" ]] && echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] post-scan/${CMD_NAME} - $line"
                done || true
            fi
        fi
    done
else
    ts "No post-processing commands directory found at ${POST_SCAN_DIR}"
fi

clean_up
