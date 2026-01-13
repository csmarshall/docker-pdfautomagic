#!/bin/bash
# Test harness for PDF document detection

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DETECTION_DIR="$(dirname "$SCRIPT_DIR")"
INPUT_DIR="${SCRIPT_DIR}/input"
OUTPUT_DIR="${SCRIPT_DIR}/output"
RESULTS_FILE="${SCRIPT_DIR}/test_results.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 [OPTIONS] [input.pdf]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -c, --clean         Clean output directory before running"
    echo "  -m, --model MODEL   Specify Ollama model (default: qwen2-vl)"
    echo "  -b, --blank THRESH  Blank page threshold 0-1 (default: 0.97)"
    echo "  -a, --all           Process all PDFs in input directory"
    echo ""
    echo "If no input PDF specified, processes all PDFs in ${INPUT_DIR}"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Default values
CLEAN=false
MODEL="qwen2.5vl"
BLANK_THRESHOLD=0.97
PROCESS_ALL=false
INPUT_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -c|--clean)
            CLEAN=true
            shift
            ;;
        -m|--model)
            MODEL="$2"
            shift 2
            ;;
        -b|--blank)
            BLANK_THRESHOLD="$2"
            shift 2
            ;;
        -a|--all)
            PROCESS_ALL=true
            shift
            ;;
        *)
            INPUT_FILE="$1"
            shift
            ;;
    esac
done

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."

    if ! command -v python3 &> /dev/null; then
        log_error "python3 not found"
        exit 1
    fi

    if ! command -v ollama &> /dev/null; then
        log_error "ollama not found. Install from https://ollama.ai"
        exit 1
    fi

    # Check if model is available
    if ! ollama list | grep -q "$MODEL"; then
        log_warn "Model '$MODEL' not found. Pulling..."
        ollama pull "$MODEL"
    fi

    # Check Python dependencies
    if ! python3 -c "import pypdf, pdf2image, PIL, ollama" 2>/dev/null; then
        log_warn "Missing Python dependencies. Installing..."
        pip install -r "${DETECTION_DIR}/requirements.txt"
    fi

    log_info "Dependencies OK"
}

# Clean output directory
clean_output() {
    if [[ "$CLEAN" == "true" ]]; then
        log_info "Cleaning output directory..."
        rm -rf "${OUTPUT_DIR:?}"/*
    fi
}

# Run detection on a single PDF
run_detection() {
    local input="$1"
    local basename=$(basename "$input" .pdf)
    local output_subdir="${OUTPUT_DIR}/${basename}"

    log_info "Processing: $input"
    log_info "Output to: $output_subdir"

    mkdir -p "$output_subdir"

    python3 "${DETECTION_DIR}/split_pdf.py" \
        "$input" \
        --output-dir "$output_subdir" \
        --model "$MODEL" \
        --blank-threshold "$BLANK_THRESHOLD" \
        --json > "${output_subdir}/results.json"

    # Display results
    echo ""
    log_info "Results for $basename:"
    python3 -c "
import json
with open('${output_subdir}/results.json') as f:
    r = json.load(f)
    print(f\"  Pages in:        {r['pages_input']}\")
    print(f\"  Blanks removed:  {r['pages_blank_removed']}\")
    print(f\"  Docs created:    {r['documents_output']}\")
    print(f\"  Time:            {r['processing_time_sec']:.1f}s\")
    if r['low_confidence_pages']:
        print(f\"  Low confidence:  {r['low_confidence_pages']}\")
"
    echo ""
}

# Main
main() {
    echo "=================================="
    echo "PDF Detection Test Harness"
    echo "=================================="
    echo ""

    check_dependencies
    clean_output

    mkdir -p "$OUTPUT_DIR"

    if [[ -n "$INPUT_FILE" ]]; then
        # Process single file
        if [[ ! -f "$INPUT_FILE" ]]; then
            log_error "File not found: $INPUT_FILE"
            exit 1
        fi
        run_detection "$INPUT_FILE"
    else
        # Process all PDFs in input directory
        pdf_count=$(find "$INPUT_DIR" -maxdepth 1 -name "*.pdf" 2>/dev/null | wc -l)

        if [[ "$pdf_count" -eq 0 ]]; then
            log_warn "No PDF files found in $INPUT_DIR"
            log_info "Place test PDFs in: $INPUT_DIR"
            exit 0
        fi

        log_info "Found $pdf_count PDF(s) to process"
        echo ""

        for pdf in "$INPUT_DIR"/*.pdf; do
            run_detection "$pdf"
        done
    fi

    log_info "All tests complete!"
    log_info "Results saved to: $OUTPUT_DIR"
}

main "$@"
