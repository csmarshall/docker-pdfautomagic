# PDF Document Detection

Intelligent document detection using vision AI to identify document boundaries in multi-page scans.

## Overview

When you scan a stack of mail as a single PDF, this tool:
1. **Removes blank pages** (backs of single-sided documents)
2. **Detects document boundaries** using vision AI (letterheads, dates, salutations)
3. **Splits into separate PDFs** for individual documents

## Requirements

- Python 3.8+
- [Ollama](https://ollama.com) with `qwen2.5vl` model
- poppler-utils (for pdf2image)

## Quick Start

```bash
# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Pull the vision model (~5GB)
ollama pull qwen2.5vl:7b

# Install Python dependencies
pip install -r requirements.txt

# Run on a PDF
python split_pdf.py /path/to/scanned_mail.pdf -o ./output
```

## Usage

```bash
# Basic usage
python split_pdf.py input.pdf

# Specify output directory
python split_pdf.py input.pdf -o /path/to/output

# Output as JSON (for scripting)
python split_pdf.py input.pdf --json

# Adjust blank page sensitivity (default 0.97)
python split_pdf.py input.pdf --blank-threshold 0.95
```

## Test Harness

```bash
# Place test PDFs in test/input/
cp your_test.pdf test/input/

# Run tests
cd test && ./run_test.sh

# Or test a specific file
./run_test.sh /path/to/specific.pdf
```

## Output Metrics

| Metric | Description |
|--------|-------------|
| `pages_input` | Total pages in source PDF |
| `pages_blank_removed` | Blank pages detected and dropped |
| `pages_processed` | Non-blank pages analyzed |
| `documents_output` | Number of PDFs created |
| `boundaries_detected` | Page numbers where splits occurred |
| `confidence_scores` | Model confidence for each page (0-1) |
| `low_confidence_pages` | Pages with confidence < 0.7 |
| `processing_time_sec` | Total processing time |
| `model_calls` | Number of vision model API calls |

## Roadmap

### Phase 1: Detection ✅ Complete
- [x] Blank page detection
- [x] Document boundary detection via vision AI
- [x] PDF splitting and reassembly
- [x] Test harness with metrics
- [x] Model baked into Docker image (no manual setup)
- [x] Non-root container support (HOME=/tmp for Ollama)
- [x] Timestamped logging throughout pipeline

### Phase 2: Smart Naming ✅ Complete
- [x] Document type classification (bill, statement, letter, etc.)
- [x] Sender extraction (company/person name)
- [x] Date extraction (document date, not scan date)
- [x] Auto-generate descriptive filenames
  - e.g., `2026-01-10_Comcast_Bill.pdf` instead of `doc001.pdf`
- [x] Enabled by default (`ENABLE_CLASSIFICATION=true`)

### Phase 3: Reliability & Notifications (In Progress)
- [ ] **Success/failure notification hooks**
  - Separate hooks for success vs failure events
  - Export detailed status to hook environment variables
- [ ] **Failure backoff mechanism**
  - Avoid spamming notifications on repeated failures
  - Configurable backoff interval
- [ ] **Auto-disable on repeated failures**
  - If GPU/model fails N times consecutively, disable detection
  - Re-enable on next successful GPU check or manual reset
  - Log prominent warning when auto-disabled

### Phase 4: Future Considerations
- [ ] Auto-detect grayscale vs color and optimize PDF output size
- [ ] Auto-sort into folders by document type
- [ ] Junk mail detection and filtering
- [ ] Priority/urgency detection
- [ ] Account/reference number extraction for searchability
- [ ] Integration with document management systems
