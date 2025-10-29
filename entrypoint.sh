#!/bin/bash
set -e

# PDFAutomagic runs as a daemon with internal loop
INTERVAL_MINUTES="${INTERVAL_MINUTES:-1}"
SCAN_DIR="${1}"

# Validation checks
echo "PDFAutomagic starting..."
echo "Validating configuration..."

if [[ ! -d "${SCAN_DIR}" ]]; then
    echo "ERROR: Scan directory not found: ${SCAN_DIR}"
    echo "Make sure SCAN_DIR is mounted as a volume"
    exit 1
fi

if [[ ! -f "/config/rclone.conf" ]]; then
    echo "ERROR: rclone.conf not found at /config/rclone.conf"
    echo "Please create your rclone configuration:"
    echo "  1. Copy config-example to your config directory"
    echo "  2. Run: rclone config --config /path/to/config/rclone.conf"
    echo "  3. Mount config directory as volume in docker-compose.yml"
    exit 1
fi

if [[ -z "${RCLONE_REMOTE}" ]]; then
    echo "ERROR: RCLONE_REMOTE environment variable not set"
    echo "Please set RCLONE_REMOTE in your .env file"
    exit 1
fi

echo "Configuration validated successfully"
echo "Scan directory: ${SCAN_DIR}"
echo "Rclone remote: ${RCLONE_REMOTE}"
echo "Check interval: ${INTERVAL_MINUTES} minute(s)"
echo ""

echo "Starting PDFAutomagic daemon (checking every ${INTERVAL_MINUTES} minute(s))"

# Create heartbeat file for monitoring
HEARTBEAT_FILE="/tmp/pdfautomagic.heartbeat"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > ${HEARTBEAT_FILE}

while true; do
    # Update heartbeat
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > ${HEARTBEAT_FILE}
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Heartbeat - Starting check cycle"

    /app/process-pdfs.sh ${SCAN_DIR}

    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Check cycle complete. Sleeping for ${INTERVAL_MINUTES} minute(s)..."
    sleep $((INTERVAL_MINUTES * 60))
done
