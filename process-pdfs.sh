#!/bin/bash
set -euo pipefail

SCRIPT=$(basename ${0})
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCAN_DIR="${1}"
RAW_SCAN_DIR="${1}/unprocessed"
LOCK_FILE="/tmp/${SCRIPT}.lock"
MINUTES_OLD="${MINUTES_OLD:-2}"
MAX_PARALLEL_JOBS="${MAX_PARALLEL_JOBS:-1}"

ts () {
    echo -n "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ${SCRIPT} - "
    echo $*
}

clean_up () {
    EXIT_CODE=${1}
    if [[ -e "${LOCK_FILE}" ]] ; then
        ts "Removing lock ${LOCK_FILE}"
        rm ${LOCK_FILE}
    fi
    ts "Done"
    exit ${EXIT_CODE}
}

trap clean_up SIGHUP SIGINT SIGTERM

if [[ -e "${LOCK_FILE}" ]]; then
    ts "Already running under pid $(cat ${LOCK_FILE})"
    exit 0
else
    echo $$ > ${LOCK_FILE}
fi


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
    mkdir -vp ${OUTPUT_DIR}
    mkdir -vp ${ORIGINALS_DIR}
else
    ts "Output Directory: ${OUTPUT_DIR} present"
fi

# Function to process a single file
process_file() {
    local INPUT_FILE="${1}"
    local BASENAME=$(basename "${INPUT_FILE}")
    # Strip any extension (.pdf, .tif, .tiff, etc.) - output is always PDF
    local FILENAME="${BASENAME%.*}"
    local OUTPUT_FILE="${OUTPUT_DIR}/ocr${FILENAME}_$(date +"%F-%H%M%S").pdf"

    # Skip if file is empty
    if [[ ! -f "${INPUT_FILE}" ]] || [[ ! -s "${INPUT_FILE}" ]]; then
        ts "Skipping invalid or empty file: ${INPUT_FILE}"
        return 1
    fi

    ts "Processing ${INPUT_FILE} to ${OUTPUT_FILE}"

    # Run OCR with error handling
    if /usr/bin/ocrmypdf -rdc "${INPUT_FILE}" "${OUTPUT_FILE}" 2>&1 | sed "s/^/  /"; then
        ts "OCR successful for $(basename ${INPUT_FILE})"
        ts "Moving ${INPUT_FILE} to ${ORIGINALS_DIR}"
        mv -v "${INPUT_FILE}" "${ORIGINALS_DIR}"
        return 0
    else
        ts "ERROR: OCR failed for ${INPUT_FILE}, leaving in place for retry"
        # Remove partial output file if it exists
        [[ -f "${OUTPUT_FILE}" ]] && rm -f "${OUTPUT_FILE}"
        return 1
    fi
}

# Export function and variables for use in subshells
export -f process_file
export -f ts
export OUTPUT_DIR ORIGINALS_DIR SCRIPT

ts "Processing with MAX_PARALLEL_JOBS=${MAX_PARALLEL_JOBS}"

# Process files in parallel
for INPUT_FILE in ${FILES_TO_SCAN}; do
    # Wait if we've hit the parallel job limit
    while [ $(jobs -r | wc -l) -ge ${MAX_PARALLEL_JOBS} ]; do
        sleep 0.1
    done

    # Start processing in background
    process_file "${INPUT_FILE}" &
done

# Wait for all background jobs to complete
wait

ts "All files processed"

RCLONE_REMOTE="${RCLONE_REMOTE:-Dropbox:Cabinet/Documents}"
ts "Rclone to ${RCLONE_REMOTE}"
/usr/bin/rclone copy --config /config/rclone.conf -v ${SCAN_DIR}/processed ${RCLONE_REMOTE}

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
    export DATE="$(date +"%Y-%m-%d")"
    export TIME="$(date +"%H:%M:%S")"
    export DATETIME="$(date +"%Y-%m-%dT%H:%M:%S%z")"  # ISO8601 with timezone offset

    for cmd in ${POST_SCAN_DIR}/*; do
        if [[ -x "${cmd}" ]]; then
            ts "Executing $(basename ${cmd})"
            echo "${NUM_FILES} files OCRd and uploaded to ${RCLONE_REMOTE}" | ${cmd}
        fi
    done
else
    ts "No post-processing commands directory found at ${POST_SCAN_DIR}"
fi

clean_up
