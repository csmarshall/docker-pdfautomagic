FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    ocrmypdf \
    tesseract-ocr \
    tesseract-ocr-eng \
    tesseract-ocr-chi-sim \
    tesseract-ocr-spa \
    tesseract-ocr-hin \
    tesseract-ocr-ara \
    tesseract-ocr-fra \
    tesseract-ocr-por \
    tesseract-ocr-rus \
    tesseract-ocr-deu \
    tesseract-ocr-jpn \
    ghostscript \
    unpaper \
    pngquant \
    curl \
    unzip \
    ca-certificates \
    procps \
    && rm -rf /var/lib/apt/lists/*

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
