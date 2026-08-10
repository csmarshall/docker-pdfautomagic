# ADR-009: Multi-Stage Docker Builds with Image Variants

**Status**: Accepted

**Date**: 2026-01-12

## Context

The Vision AI document detection feature (ADR-007) adds significant dependencies:
- Python 3 with pypdf, pdf2image, Pillow, ollama packages
- Ollama runtime for model inference
- Qwen2.5-VL model (~5GB, baked into image - see ADR-010)
- GPU drivers (for NVIDIA/AMD)

Not all users need AI detection. Some just want basic OCR functionality with a smaller footprint.

## Decision

Use **multi-stage Docker builds** with **two image variants**:

1. **Default (`:latest`)** - Full featured with AI detection
2. **Lite (`:latest-lite`)** - OCR only, no AI features

AI detection is the default because it's the primary differentiating feature of PDFAutomagic.

### Image Variants

| Tag | Contents | Size |
|-----|----------|------|
| `latest` | OCR + Python + Ollama + Model | **~7GB** |
| `latest-lite` | OCR only | **~800MB** |

The vision model is baked into the image as a separate Docker layer for efficient caching. See [ADR-010](010-model-bundling-strategy.md) for the rationale behind this "just works" approach.

### Architecture (Full Image)

```
┌─────────────────────────────────────────────────────────────┐
│              pdfautomagic:latest container                  │
│                                                             │
│  ┌─────────────────────┐      ┌─────────────────────────┐  │
│  │   process-pdfs.sh   │      │    ollama process       │  │
│  │                     │ HTTP │    (on-demand)          │  │
│  │  - Detects files    │─────▶│                         │  │
│  │  - Starts Ollama    │11434 │  - qwen2.5vl:7b model   │  │
│  │  - Runs detection   │      │  - GPU acceleration     │  │
│  │  - Stops Ollama     │      │  - Model baked in       │  │
│  └─────────────────────┘      └─────────────────────────┘  │
│           │                                                 │
│           ▼                                                 │
│     ┌──────────┐                                           │
│     │  /scans  │                                           │
│     │ (volume) │                                           │
│     └──────────┘                                           │
└─────────────────────────────────────────────────────────────┘
```

### On-Demand Process Lifecycle

1. **Files detected** → `start_ollama()` starts Ollama process
2. **API ready** → Detection script analyzes pages
3. **Processing complete** → `stop_ollama()` kills process
4. **GPU freed** → No processes holding GPU memory between batches

### Dockerfile Structure

Illustrative — exact version pins live in the [`Dockerfile`](../../Dockerfile)
(base image via Dependabot, `OLLAMA_VERSION` via the weekly check workflow).

```dockerfile
FROM ubuntu:26.04 AS base
# Install ocrmypdf, tesseract, rclone, etc.

# Lite variant - OCR only
FROM base AS lite
COPY process-pdfs.sh entrypoint.sh /app/
# ~800MB

# Default variant - Full featured (last stage = default)
FROM base AS default
ARG OLLAMA_VERSION=0.30.10
RUN apt-get install -y python3 python3-venv poppler-utils zstd
# Ollama ships zstd-compressed .tar.zst archives (see ADR-008 / Dockerfile)
RUN curl ... ollama-linux-amd64.tar.zst | tar --use-compress-program=unzstd -x -C /usr

# Pre-download model (~5GB layer, cached separately)
ARG VISION_MODEL=qwen2.5vl:7b
RUN ollama serve & sleep 5 && ollama pull ${VISION_MODEL} && pkill ollama

COPY detection/ /app/detection/
# ~7GB total (model baked in as separate layer)
```

### Version Tracking

| Component | Update Method |
|-----------|---------------|
| Python packages | Dependabot (pip ecosystem) |
| Ubuntu base image | Dependabot (docker ecosystem) |
| Ollama | GitHub Action - weekly check, auto-PR |
| AI Model | Baked into image at build time (VISION_MODEL build arg) |

## Consequences

### Positive

- **Just works**: No manual setup - model is included in image
- **Full featured by default**: Users get AI detection out of the box
- **Lite option available**: Users who don't need AI get smaller image
- **On-demand GPU**: Ollama process starts/stops with file processing
- **Automated updates**: Dependabot + GitHub Action keep deps current
- **Efficient caching**: Model layer cached separately from code changes

### Negative

- **Larger default image**: Full image is ~7GB vs ~800MB for lite
- **GPU recommended**: Full features work best with NVIDIA/AMD GPU

### Neutral

- Detection enabled by default via `ENABLE_DETECTION=true`
- Falls back gracefully if Ollama fails to start
- CPU fallback available (slower) via `ALLOW_CPU_FALLBACK=true`
- Advanced users can point to shared Ollama server via `OLLAMA_HOST`

## Usage

### Full Image (Default)

```bash
# Start the service (model is included - no setup needed)
docker compose up -d
```

### Lite Image

```bash
docker compose -f docker-compose.lite.yml up -d
```

Or in docker-compose.yml:
```yaml
image: chasmarshall/pdfautomagic:latest-lite
```

### Advanced: Shared Ollama Server

Point to an external Ollama server instead of the bundled model:
```yaml
environment:
  - OLLAMA_HOST=http://your-ollama-server:11434
```
