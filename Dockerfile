FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Update package list
RUN apt-get update

# Install base OCR tools and utilities
# Split into smaller RUN commands for better ARM64/QEMU compatibility
RUN apt-get install -y \
    ocrmypdf \
    tesseract-ocr \
    ghostscript \
    unpaper \
    pngquant

# Install language packs - Group 1: Top 3 languages (English, Chinese, Spanish)
RUN apt-get install -y \
    tesseract-ocr-eng \
    tesseract-ocr-chi-sim \
    tesseract-ocr-spa

# Install language packs - Group 2: Hindi, Arabic, French
RUN apt-get install -y \
    tesseract-ocr-hin \
    tesseract-ocr-ara \
    tesseract-ocr-fra

# Install language packs - Group 3: Portuguese, Russian, German, Japanese
RUN apt-get install -y \
    tesseract-ocr-por \
    tesseract-ocr-rus \
    tesseract-ocr-deu \
    tesseract-ocr-jpn

# Install remaining utilities
RUN apt-get install -y \
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

# Copy scripts
COPY process-pdfs.sh /app/
COPY entrypoint.sh /app/

# Make scripts executable
RUN chmod +x /app/process-pdfs.sh /app/entrypoint.sh

# Create config directory for rclone.conf and post-scan-commands
RUN mkdir -p /config

# Healthcheck: verify the entrypoint process is running and heartbeat is recent
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD pgrep -f entrypoint.sh > /dev/null && \
      test -f /tmp/pdfautomagic.heartbeat && \
      test $(( $(date +%s) - $(date -r /tmp/pdfautomagic.heartbeat +%s) )) -lt 300 || exit 1

# Set the entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/scans"]
