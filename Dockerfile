# =============================================================================
# PDFAutomagic - Multi-stage Dockerfile
# =============================================================================
# Targets:
#   (default)  - Full featured: OCR + AI detection (model baked in) ~7GB
#   lite       - OCR only, no AI features ~800MB
#
# Build examples:
#   docker build -t pdfautomagic:latest .                    # Full (default)
#   docker build --target lite -t pdfautomagic:lite .        # Lightweight
#
# The default image includes everything needed for AI-powered document
# detection. Ollama runs as a process inside the container and starts/stops
# automatically when detection is needed - no sidecar required.
#
# GPU Requirements (for AI detection):
#   - NVIDIA: Install nvidia-container-toolkit
#   - AMD: Install ROCm and configure Docker
#   - CPU fallback available (slower, set ALLOW_CPU_FALLBACK=true)
#
# Version Updates:
#   - OLLAMA_VERSION: Automated via GitHub Action, or check
#     https://github.com/ollama/ollama/releases
#   - Python deps: See detection/requirements.txt (Dependabot)
# =============================================================================

# -----------------------------------------------------------------------------
# Base stage - shared dependencies for all variants
# -----------------------------------------------------------------------------
FROM ubuntu:24.04 AS base

ENV DEBIAN_FRONTEND=noninteractive

# Update package list
RUN apt-get update

# Install base OCR tools and utilities
# Split into smaller RUN commands for better ARM64/QEMU compatibility
# Use --no-install-recommends to reduce package count for QEMU
RUN apt-get install -y --no-install-recommends \
    ocrmypdf \
    tesseract-ocr \
    ghostscript \
    unpaper \
    pngquant

# Install language packs - Group 1: Top 3 languages (English, Chinese, Spanish)
RUN apt-get install -y --no-install-recommends \
    tesseract-ocr-eng \
    tesseract-ocr-chi-sim \
    tesseract-ocr-spa

# Install language packs - Group 2: Hindi, Arabic, French
RUN apt-get install -y --no-install-recommends \
    tesseract-ocr-hin \
    tesseract-ocr-ara \
    tesseract-ocr-fra

# Install language packs - Group 3: Portuguese, Russian, German, Japanese
RUN apt-get install -y --no-install-recommends \
    tesseract-ocr-por \
    tesseract-ocr-rus \
    tesseract-ocr-deu \
    tesseract-ocr-jpn

# Install remaining utilities
RUN apt-get install -y --no-install-recommends \
    curl \
    unzip \
    ca-certificates \
    procps

# Clean up apt cache to reduce image size
RUN rm -rf /var/lib/apt/lists/*

# Install rclone
RUN curl https://rclone.org/install.sh | bash

# Create working directory
WORKDIR /app

# Create config directory for rclone.conf and post-scan-commands
RUN mkdir -p /config

# -----------------------------------------------------------------------------
# Lite stage - OCR only, no AI features (tagged as 'lite')
# Use this if you don't need AI detection or want a smaller image
# -----------------------------------------------------------------------------
FROM base AS lite

# Copy scripts
COPY process-pdfs.sh /app/
COPY entrypoint.sh /app/

# Make scripts executable
RUN chmod +x /app/process-pdfs.sh /app/entrypoint.sh

# Healthcheck: verify the entrypoint process is running and heartbeat is recent
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD pgrep -f entrypoint.sh > /dev/null && \
      test -f /tmp/pdfautomagic.heartbeat && \
      test $(( $(date +%s) - $(date -r /tmp/pdfautomagic.heartbeat +%s) )) -lt 300 || exit 1

# Set the entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/scans"]

# -----------------------------------------------------------------------------
# Default stage - Full featured with AI detection (tagged as 'latest')
# Includes Python, Ollama, and vision AI for intelligent document detection
# -----------------------------------------------------------------------------
FROM base AS default

# Version pins for reproducible builds
# Automatically updated via GitHub Action (.github/workflows/check-ollama-version.yml)
# Manual check: https://github.com/ollama/ollama/releases
ARG OLLAMA_VERSION=0.30.10

# Install Python and dependencies for document detection
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    poppler-utils \
    pciutils \
    zstd \
    && rm -rf /var/lib/apt/lists/*

# Install Ollama (pinned version for reproducibility)
# Ollama manages GPU detection automatically (NVIDIA, AMD, Apple Silicon)
# Download architecture-specific binary (amd64 or arm64)
# Note: Ollama switched its release archives from .tgz to zstd-compressed
# .tar.zst (requires the zstd package installed above to extract).
RUN ARCH=$(dpkg --print-architecture) && \
    curl -fsSL https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-${ARCH}.tar.zst \
    -o /tmp/ollama.tar.zst \
    && tar --use-compress-program=unzstd -xf /tmp/ollama.tar.zst -C /usr \
    && rm /tmp/ollama.tar.zst \
    && ollama --version

# Pre-download the vision AI model (~5GB) so it's baked into the image
# This creates a ~5GB layer that's cached separately from the rest of the image
# Model is stored in /usr/share/ollama so it's readable by non-root users at runtime
# NOTE: Skip model download on ARM64 - QEMU emulation is too slow/unreliable
#       ARM64 users will auto-download the model on first use
ARG VISION_MODEL=qwen2.5vl:7b
ENV OLLAMA_MODELS=/usr/share/ollama/models
RUN mkdir -p /usr/share/ollama/models && \
    ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        ollama serve & \
        sleep 5 && \
        ollama pull ${VISION_MODEL} && \
        pkill ollama; \
    else \
        echo "Skipping model download on $ARCH - will auto-download on first use"; \
    fi && \
    chmod -R a+rX /usr/share/ollama

# Copy detection module
COPY detection/ /app/detection/

# Create venv and install Python dependencies
RUN python3 -m venv /app/detection/.venv \
    && /app/detection/.venv/bin/pip install --no-cache-dir -r /app/detection/requirements.txt

# Copy scripts
COPY process-pdfs.sh /app/
COPY entrypoint.sh /app/

# Make scripts executable
RUN chmod +x /app/process-pdfs.sh /app/entrypoint.sh /app/detection/split_pdf.py

# Healthcheck: verify the entrypoint process is running and heartbeat is recent
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD pgrep -f entrypoint.sh > /dev/null && \
      test -f /tmp/pdfautomagic.heartbeat && \
      test $(( $(date +%s) - $(date -r /tmp/pdfautomagic.heartbeat +%s) )) -lt 300 || exit 1

# Set the entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/scans"]
