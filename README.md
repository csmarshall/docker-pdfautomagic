# PDFAutomagic

[![Build and Push Docker Image](https://github.com/csmarshall/docker-pdfautomagic/actions/workflows/docker-build.yml/badge.svg)](https://github.com/csmarshall/docker-pdfautomagic/actions/workflows/docker-build.yml)
[![Scheduled Dependency Updates](https://github.com/csmarshall/docker-pdfautomagic/actions/workflows/scheduled-rebuild.yml/badge.svg)](https://github.com/csmarshall/docker-pdfautomagic/actions/workflows/scheduled-rebuild.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/chasmarshall/pdfautomagic)](https://hub.docker.com/r/chasmarshall/pdfautomagic)
[![Docker Image Version](https://img.shields.io/docker/v/chasmarshall/pdfautomagic?sort=semver)](https://hub.docker.com/r/chasmarshall/pdfautomagic/tags)

Dockerized OCR processor with **AI-powered document detection**. Automatically processes PDFs, detects and splits multi-document scans, and syncs to cloud storage.

**Key Features:**
- **AI Document Detection** - Scan a stack of mail as one PDF, AI detects document boundaries and splits into separate files
- **Blank Page Removal** - Automatically removes blank backs from single-sided documents
- **Smart Naming** - Optionally names files based on content (e.g., `2025-01-15_Comcast_Bill.pdf`)
- **OCR** - Makes PDFs searchable with text layer
- **Cloud Sync** - Uploads to Dropbox, Google Drive, S3, OneDrive, etc. via rclone

## Quick Start

### 1. Setup

```bash
# Create directory structure
mkdir -p ~/pdfautomagic/{unprocessed,config}
cd ~/pdfautomagic

# Configure cloud storage
rclone config --config config/rclone.conf
# Follow prompts for Dropbox, Google Drive, S3, etc.

# Create .env file
cat > .env << 'EOF'
SCAN_DIR=./
CONFIG_DIR=./config
RCLONE_REMOTE=YourRemote:Path/To/Folder
TIMEZONE=America/Chicago
PUID=1000
PGID=1000
EOF
```

### 2. Download docker-compose.yml and start

```bash
# Download compose file
curl -O https://raw.githubusercontent.com/csmarshall/docker-pdfautomagic/main/docker-compose.yml

# Start the service (AI model is included - no extra setup needed)
docker compose up -d
```

### 3. Use it

Drop PDFs in `~/pdfautomagic/unprocessed/` and watch them get processed and synced!

## Image Variants

| Tag | Description | Size |
|-----|-------------|------|
| `latest` | **Full featured** - OCR + AI detection + smart naming (model included) | **~7GB** |
| `latest-lite` | OCR only, no AI features | **~800MB** |

The `latest` image includes the vision AI model baked in - no additional setup required. See [ADR-010](docs/adr/010-model-bundling-strategy.md) for details on this design decision.

### GPU Requirements (for AI detection)

The full image uses a vision AI model for document detection:
- **NVIDIA GPU** (recommended) - Install [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- **AMD GPU** - Install ROCm and configure Docker

**No GPU?** AI detection will automatically fall back to CPU with a prominent warning. CPU processing is ~10x slower.

If you don't have a GPU and don't want slow CPU processing:
- **Use lite image** - `docker compose -f docker-compose.lite.yml up -d` (OCR only, no AI)
- **Or disable detection** - Set `ENABLE_DETECTION=false` in `.env`

### Using the Lite Image

If you don't need AI detection or don't have a GPU:

```bash
docker compose -f docker-compose.lite.yml up -d
```

Or change your docker-compose.yml:
```yaml
image: chasmarshall/pdfautomagic:latest-lite
```

## Features

### AI Document Detection

Scan a stack of mail as a single PDF. PDFAutomagic uses vision AI to:
1. **Remove blank pages** - Backs of single-sided documents
2. **Detect document boundaries** - Different letterheads, formats, etc.
3. **Split into separate files** - Each piece of mail becomes its own PDF

Enable in `.env`:
```bash
ENABLE_DETECTION=true
```

### Smart Document Naming

Optionally extract document info for intelligent file naming:

```bash
ENABLE_CLASSIFICATION=true
```

Results in filenames like:
- `2025-01-15_Comcast_Bill_acct1234.pdf`
- `2025-01-12_IRS_Tax_Notice_1234567.pdf`
- `2025-01-10_Bank_Statement.pdf`

### Core Features

- **Multi-language OCR** - 10 languages covering 90%+ of global speakers
- **Cloud sync** - Dropbox, Google Drive, S3, OneDrive, etc. via rclone
- **Date organization** - Files organized as `YYYY/MM/DD/`
- **Parallel processing** - Process multiple PDFs simultaneously
- **Post-scan hooks** - Run custom scripts after processing
- **Health monitoring** - Built-in healthchecks and heartbeat

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SCAN_DIR` | - | Directory containing `unprocessed/`, `processed/`, `originals/` |
| `CONFIG_DIR` | - | Directory with `rclone.conf` and `post-scan-commands/` |
| `RCLONE_REMOTE` | - | Cloud destination (e.g., `Dropbox:Documents`) |
| `TIMEZONE` | `UTC` | Container timezone |
| `PUID` / `PGID` | `1000` | User/group ID for file ownership |
| `INTERVAL_MINUTES` | `1` | How often to check for new files |
| `MAX_PARALLEL_JOBS` | `1` | Number of PDFs to process simultaneously |
| `MINUTES_OLD` | `1` | Only process files older than this (minutes) |
| **OCR Settings** | | |
| `ROTATE_PAGES_THRESHOLD` | `7.5` | Confidence threshold for auto-rotation (0-15, lower=more aggressive) |
| **AI Detection** | | |
| `ENABLE_DETECTION` | `true` | Enable AI document detection |
| `ENABLE_CLASSIFICATION` | `true` | Enable smart document naming |

### Post-Scan Hooks

Create executable scripts in `{CONFIG_DIR}/post-scan-commands/` that run after processing.

**Available environment variables:**
```bash
# Core variables
$FILES_PROCESSED      # Number of input PDF files
$RCLONE_REMOTE        # Cloud storage destination
$OUTPUT_DIR           # Where processed PDFs were saved
$ORIGINALS_DIR        # Where original PDFs were moved
$SCAN_DIR             # Base scan directory

# Timestamps
$TZ                   # Container timezone (e.g., America/Chicago)
$DATE                 # ISO date (YYYY-MM-DD)
$TIME                 # ISO time (HH:MM:SS)
$DATETIME             # Full ISO8601 with timezone offset
$PROCESSING_DATE      # Date for directory structure (YYYY/MM/DD)

# Detection metrics (when ENABLE_DETECTION=true)
$DETECTION_ENABLED    # "true" or "false"
$PAGES_SCANNED        # Total pages in all input PDFs
$BLANK_PAGES_REMOVED  # Blank pages detected and removed
$DOCUMENTS_CREATED    # Output documents after splitting
$CLASSIFICATION_ENABLED  # "true" or "false"

# Timing metrics
$PROCESSING_DURATION_SECONDS  # Total processing time in seconds
$PROCESSING_DURATION          # Human readable (e.g., "2m 34s")
$SECONDS_PER_PAGE             # Average seconds per page
```

**Example notification:**
```bash
#!/bin/bash
if [[ "${DETECTION_ENABLED}" == "true" ]]; then
  MSG="${FILES_PROCESSED} scans -> ${DOCUMENTS_CREATED} documents"
  MSG="${MSG} (${BLANK_PAGES_REMOVED} blanks removed)"
else
  MSG="${FILES_PROCESSED} files processed"
fi
curl -X POST "https://ntfy.sh/mytopic" -d "${MSG}"
```

## Building from Source

```bash
git clone https://github.com/csmarshall/docker-pdfautomagic.git
cd docker-pdfautomagic

# Copy and configure
cp .env.example .env
cp -r config-example my-config
rclone config --config my-config/rclone.conf

# Build and run (model is included in the build)
docker compose -f docker-compose.build.yml build
docker compose -f docker-compose.build.yml up -d
```

### Building Lite Image

```bash
docker build --target lite -t pdfautomagic:latest-lite .
```

## How It Works

1. **Monitor** - Checks `/scans/unprocessed/` for PDFs older than `MINUTES_OLD` (default: 1 min)
2. **Detect** (if enabled) - AI analyzes pages, removes blanks, detects boundaries
3. **OCR** - Adds searchable text layer with ocrmypdf
4. **Organize** - Moves to `/scans/processed/YYYY/MM/DD/`
5. **Backup** - Originals saved to `/scans/originals/YYYY/MM/DD/`
6. **Sync** - Uploads to cloud storage via rclone
7. **Notify** - Runs post-scan hook scripts

## Privacy & Security

PDFAutomagic processes documents **entirely locally** - no data is sent to external servers.

- **Local AI model** - Document detection uses Ollama running locally in the container. We intentionally avoided cloud AI APIs (OpenAI, Anthropic, Google) because this tool was designed to process personal mail containing sensitive information like bills, medical documents, and financial statements.
- **No telemetry** - No usage data, document content, or metadata is collected or transmitted.
- **Your cloud, your choice** - Cloud sync via rclone is optional and uses your own configured storage.

See [ADR-008](docs/adr/008-ollama-local-model-hosting.md) for the full rationale on local-only AI processing.

## Architecture Decisions

See `docs/adr/` for architecture decision records:
- [ADR-007](docs/adr/007-vision-ai-pdf-detection.md) - Vision AI for document detection
- [ADR-008](docs/adr/008-ollama-local-model-hosting.md) - Ollama for local model hosting (privacy-first)
- [ADR-009](docs/adr/009-multi-stage-docker-detection-variants.md) - Docker image variants
- [ADR-010](docs/adr/010-model-bundling-strategy.md) - Model bundling strategy (just works)

## Troubleshooting

### Check logs
```bash
docker compose logs -f
```

### Verify GPU access
```bash
docker compose run --rm pdfautomagic nvidia-smi  # NVIDIA
```

### Test detection manually
```bash
docker compose run --rm pdfautomagic \
  /app/detection/.venv/bin/python /app/detection/split_pdf.py \
  --check-gpu
```

## Maintenance

### Automatic Updates

Dependencies are automatically tracked:
- **Python packages** - Dependabot
- **Docker base image** - Dependabot
- **Ollama** - Weekly GitHub Action creates PRs for new versions

### Manual Updates

```bash
# Pull latest image (includes updated model)
docker pull chasmarshall/pdfautomagic:latest
docker compose down && docker compose up -d
```

### Advanced: Shared Model Server

For users running multiple AI tools, you can point PDFAutomagic at a shared Ollama server instead of using the bundled model:

```yaml
environment:
  - OLLAMA_HOST=http://your-ollama-server:11434
  - ENABLE_DETECTION=true
```

This allows sharing models across tools while maintaining privacy (your server, your network).

## Dependencies & Acknowledgments

PDFAutomagic builds on these excellent open-source projects:

### AI/ML
- **[Ollama](https://ollama.com)** - Local LLM runtime that makes it easy to run models privately
- **[Qwen2.5-VL](https://github.com/QwenLM/Qwen2.5-VL)** - Vision-language model by Alibaba/Qwen team, used for document boundary detection

### Document Processing
- **[OCRmyPDF](https://ocrmypdf.readthedocs.io/)** - Adds OCR text layer to PDFs
- **[Tesseract OCR](https://github.com/tesseract-ocr/tesseract)** - OCR engine (via OCRmyPDF)
- **[pypdf](https://pypdf.readthedocs.io/)** - PDF manipulation in Python
- **[pdf2image](https://github.com/Belval/pdf2image)** - PDF to image conversion (uses Poppler)

### Infrastructure
- **[rclone](https://rclone.org)** - Cloud storage sync (supports 40+ providers)
- **[Ubuntu](https://ubuntu.com)** - Base container image

## License

MIT License - see [LICENSE](LICENSE) for details.
