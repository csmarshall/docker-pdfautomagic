# PDFAutomagic

Dockerized script that automatically OCRs PDF documents and syncs them to cloud storage (Dropbox, Google Drive, S3, etc.) organized by date.

Perfect for processing PDFs from scanners, email attachments, downloads, or any other source.

## Quick Start

```bash
# 1. Clone and setup
git clone https://github.com/csmarshall/docker-pdfautomagic.git
cd docker-pdfautomagic

# 2. Create config directory
cp -r config-example my-config
rclone config --config my-config/rclone.conf
# Follow prompts to configure your cloud storage

# 3. Configure environment
cp .env.example .env
# Edit .env with your paths:
#   SCAN_DIR=/path/to/pdfs
#   CONFIG_DIR=/path/to/my-config
#   RCLONE_REMOTE=Dropbox:Cabinet/Documents

# 4. Create scan directory structure
mkdir -p /path/to/pdfs/unprocessed

# 5. Build and start
docker-compose build
docker-compose up -d

# 6. Monitor
docker-compose logs -f
```

Drop PDFs in `/path/to/pdfs/unprocessed/` and watch them get OCR'd and synced!

## Features

- Monitors a directory for PDF files
- Applies OCR to PDFs using ocrmypdf
- Organizes documents by date (YYYY/MM/DD)
- Syncs processed documents to cloud storage using rclone
- Preserves originals in separate directory
- Extensible post-processing via custom scripts
- Multi-language OCR support (10 languages covering 90%+ of global speakers)
- Parallel processing for faster throughput
- Built-in healthchecks and heartbeat monitoring

## Why Ubuntu instead of Alpine?

While Alpine Linux is popular for Docker images due to its small size (~5MB base), **PDFAutomagic uses Ubuntu 22.04** for important technical reasons:

**OCRmyPDF Compatibility**: OCRmyPDF has complex dependencies (Ghostscript, Tesseract, Pillow, leptonica, unpaper) that work reliably with glibc (Ubuntu) but can have compatibility issues with musl libc (Alpine).

**Language Support**: We include 10 Tesseract language packs covering 90%+ of global speakers. Ubuntu's package repository provides well-maintained, current versions of all these languages.

**It Just Works**: Ubuntu ensures out-of-the-box compatibility with all OCR features, Python libraries, and image processing tools without troubleshooting musl/glibc differences.

**Size Trade-off**: While the final image is ~500MB (vs ~200MB with Alpine), this is acceptable for a single-instance background daemon that isn't scaled horizontally. Reliability > 300MB.

See `docs/adr/001-use-ubuntu-base-image.md` for the full decision record.

## Prerequisites

- Docker and Docker Compose
- Cloud storage account (Dropbox, Google Drive, S3, OneDrive, etc.)
- Directory structure:
  ```
  /your/pdf/directory/
  ├── unprocessed/    # Place incoming PDFs here
  ├── processed/      # OCRd files organized by date (auto-created)
  └── originals/      # Original files backed up by date (auto-created)
  ```

## Setup

### 1. Clone or setup the repository

Ensure you have these files in your directory:
- `Dockerfile`
- `docker-compose.yml`
- `import_scanned_documents.sh`
- `.env.example`

### 2. Set up configuration directory

Create a config directory with rclone configuration and optional post-scan commands:

```bash
# Copy the example config directory
cp -r config-example my-config

# Configure rclone with your cloud storage provider
rclone config --config my-config/rclone.conf
# Follow prompts to create a remote (e.g., "Dropbox", "GoogleDrive", "S3", etc.)
# See https://rclone.org/ for supported providers

# Optional: Add post-scan notification scripts
# Example: pushover_notify.sh is already included
chmod +x my-config/post-scan-commands/*
```

### 3. Create environment configuration

```bash
cp .env.example .env
# Edit .env with your actual paths
```

Example `.env`:
```bash
SCAN_DIR=/home/user/pdfs
CONFIG_DIR=/home/user/my-config
RCLONE_REMOTE=Dropbox:Cabinet/Documents
TIMEZONE=America/Chicago
```

**Cloud Storage Examples:**
- Dropbox: `RCLONE_REMOTE=Dropbox:Cabinet/Documents`
- Google Drive: `RCLONE_REMOTE=GoogleDrive:Documents/PDFs`
- AWS S3: `RCLONE_REMOTE=S3:my-bucket/documents`
- OneDrive: `RCLONE_REMOTE=OneDrive:Documents`
- Local directory: `RCLONE_REMOTE=/backup/pdfs` (configure local remote in rclone.conf)

### 4. Build the Docker image

```bash
docker-compose build
```

## Usage

### Start the service (Recommended)

PDFAutomagic runs as a daemon by default, checking for new files every minute:

```bash
docker-compose up -d
```

The container will:
- Run continuously in the background
- Check `/scans/unprocessed/` every minute (configurable via `INTERVAL_MINUTES`)
- Process any PDFs found
- Restart automatically if it crashes
- Use built-in locking to prevent concurrent runs

**Monitor the service:**

View logs in real-time:
```bash
docker-compose logs -f
```

Check health status:
```bash
docker ps  # Look for "healthy" status
docker inspect pdfautomagic | grep -A 5 Health
```

Stop the service:
```bash
docker-compose down
```

**Configure check interval:**

Edit `.env` to change how often PDFAutomagic checks for new files:
```bash
INTERVAL_MINUTES=5  # Check every 5 minutes instead of default 1 minute
```

## How It Works

1. Script monitors `/scans/unprocessed/` for PDF files older than 2 minutes
2. Each file is processed with `ocrmypdf` to add searchable OCR text layer
3. Processed files are saved to `/scans/processed/YYYY/MM/DD/`
4. Original files are moved to `/scans/originals/YYYY/MM/DD/`
5. Processed files are synced to your configured cloud storage via rclone
6. All executable scripts in `/config/post-scan-commands/` are executed
   - Examples: Send notifications, update databases, trigger webhooks, log events, etc.

## Example: Network Scanner to Cloud Workflow

This example shows how to configure PDFAutomagic with a network scanner that uploads to a Samba/CIFS share.

**Scenario**: Canon imageRUNNER or similar network scanner → SMB share → OCR → Cloud storage

### 1. Create dedicated scanner user

**Best practice**: Create a dedicated user whose sole purpose is to own the scan directory and SMB share. This isolates permissions and provides better security.

```bash
# Create dedicated scanner user and group
# Using explicit UID/GID makes it easier to track ownership
sudo groupadd -g 1003 scanner
sudo useradd -u 1001 -g 1003 -m -s /bin/bash scanner

# Create scan directory structure owned by scanner user
sudo mkdir -p /storage/scanner/unprocessed
sudo chown -R scanner:scanner /storage/scanner
sudo chmod -R 775 /storage/scanner
```

**Why a dedicated user?**
- **Security**: Limited permissions, only accesses scan directory
- **Isolation**: Separate from your personal user account
- **Clarity**: Easy to identify scanner-related files (`ls -l` shows "scanner")
- **Auditing**: Can track all scanner activity to one user

### 2. Configure Samba share

Add to `/etc/samba/smb.conf`:
```ini
[scanner]
   comment = Network Scanner Upload
   path = /storage/scanner
   read only = no
   writeable = yes
   browseable = yes
   create mask = 0644
   directory mask = 0755
   valid users = scanner
```

Set Samba password for scanner user:
```bash
sudo smbpasswd -a scanner
sudo systemctl restart smbd
```

### 3. Configure scanner device

On your network scanner (Canon imageRUNNER, Brother, HP, etc.):
- Add SMB destination: `\\your-server\scanner\unprocessed`
- Username: `scanner`
- Password: (password set above)
- File format: PDF or TIFF (both supported)

### 4. Configure PDFAutomagic

Create `.env`:
```bash
SCAN_DIR=/storage/scanner
CONFIG_DIR=/home/youruser/my-config
RCLONE_REMOTE=Dropbox:Cabinet/Documents
PUID=1001  # Match scanner user UID
PGID=1003  # Match scanner group GID
TIMEZONE=America/Chicago
```

Start container:
```bash
docker-compose up -d
```

### 5. Workflow in action

1. **Scan**: Press scan button on network printer
2. **Upload**: Scanner uploads `scan001.pdf` to `/storage/scanner/unprocessed/`
3. **Process**: PDFAutomagic OCRs it → `ocrscan001_2025-10-29-151230.pdf`
4. **Organize**:
   - Processed: `/storage/scanner/processed/2025/10/29/ocrscan001_2025-10-29-151230.pdf`
   - Original: `/storage/scanner/originals/2025/10/29/scan001.pdf`
5. **Sync**: Uploaded to `Dropbox:Cabinet/Documents/2025/10/29/`
6. **Access**: Searchable PDF available in cloud storage from any device

**File ownership**: With `PUID=1001` and `PGID=1003`, all processed files will be owned by the scanner user, maintaining consistent permissions across the SMB share.

## Logging & Monitoring

### View logs

All output goes to Docker logs (stdout/stderr):

```bash
# View recent logs
docker-compose logs

# Follow logs in real-time
docker-compose logs -f

# View last 100 lines
docker-compose logs --tail=100
```

### Log rotation

Docker handles log rotation automatically. Configure in `/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

### Healthchecks

The container includes a built-in healthcheck that verifies:
1. The entrypoint process is running
2. Heartbeat file is being updated (must be < 5 minutes old)

**Check health status:**

```bash
# Quick check
docker ps
# Look for "healthy" in STATUS column

# Detailed health info
docker inspect pdfautomagic --format='{{json .State.Health}}' | jq

# View heartbeat file
docker exec pdfautomagic cat /tmp/pdfautomagic.heartbeat
```

**Heartbeat monitoring:**

The container logs a heartbeat message at the start of each check cycle:
```
[2025-10-29T12:00:00Z] Heartbeat - Starting check cycle
```

For external monitoring systems (Prometheus, Datadog, etc.), you can:
- Parse Docker logs for heartbeat messages
- Check the container health status via Docker API
- Monitor the `/tmp/pdfautomagic.heartbeat` file inside the container

## Troubleshooting

### Container won't start

```bash
docker-compose logs ocr-processor
```

### Test rclone connection

```bash
# List your configured remotes
docker-compose run --rm ocr-processor rclone listremotes --config /config/rclone.conf

# Test connection to your remote
docker-compose run --rm ocr-processor rclone ls Dropbox: --config /config/rclone.conf
```

### Verify OCR is working

```bash
docker-compose run --rm ocr-processor ocrmypdf --version
```

## Configuration

### Add post-scan commands

Create executable scripts in `{CONFIG_DIR}/post-scan-commands/` that run after successful processing.

**Environment variables available:**
- `$FILES_PROCESSED` - Number of PDFs processed
- `$RCLONE_REMOTE` - Cloud storage destination
- `$OUTPUT_DIR` - Where processed PDFs were saved
- `$ORIGINALS_DIR` - Where original PDFs were moved
- `$PROCESSING_DATE` - Date stamp (YYYY/MM/DD format, used for directory structure)
- `$SCAN_DIR` - Base scan directory
- `$DATE` - Processing date (YYYY-MM-DD format)
- `$TIME` - Processing time (HH:MM:SS format)
- `$DATETIME` - Full ISO8601 timestamp with timezone (e.g., 2025-10-29T14:30:45-0500)

**Example: Simple logging**
```bash
cat > my-config/post-scan-commands/log.sh << 'EOF'
#!/bin/bash
echo "[${DATETIME}] Processed ${FILES_PROCESSED} files to ${OUTPUT_DIR}"
logger -t pdfautomagic "${DATE} ${TIME} - Processed ${FILES_PROCESSED} PDFs, uploaded to ${RCLONE_REMOTE}"
EOF
chmod +x my-config/post-scan-commands/log.sh
```

**Example: Webhook notification**
```bash
cat > my-config/post-scan-commands/webhook.sh << 'EOF'
#!/bin/bash
curl -X POST https://your-webhook-url.com/notify \
  -H "Content-Type: application/json" \
  -d "{\"files\": ${FILES_PROCESSED}, \"date\": \"${DATE}\", \"time\": \"${TIME}\", \"datetime\": \"${DATETIME}\"}"
EOF
chmod +x my-config/post-scan-commands/webhook.sh
```

Scripts also receive a message via stdin: `{number} files OCRd and uploaded to {RCLONE_REMOTE}`

See `config-example/post-scan-commands/pushover_notify.sh` for a notification example.

### Change cloud storage destination

Edit the `RCLONE_REMOTE` variable in your `.env` file:
```bash
RCLONE_REMOTE=GoogleDrive:MyFolder/Scanned
```

The remote name (before the colon) must match a remote configured in your `rclone.conf`.

### Adjust file age threshold

Edit `MINUTES_OLD` in your `.env` file:
```bash
MINUTES_OLD=5  # Only process files older than 5 minutes
```

This prevents processing files that are still being written/uploaded.

### Performance Tuning (Parallel Processing)

By default, PDFAutomagic processes PDFs sequentially (one at a time). For faster throughput on powerful systems, enable parallel processing via `.env`:

```bash
MAX_PARALLEL_JOBS=3  # Process 3 PDFs simultaneously
```

**Recommendations:**
- **Default (conservative):** `MAX_PARALLEL_JOBS=1` - Sequential, lowest resource usage
- **Desktop/Server (4+ cores):** `MAX_PARALLEL_JOBS=3-4` - Good balance
- **Powerful server (8+ cores):** `MAX_PARALLEL_JOBS=5-8` - Maximum speed

**Note:** OCR is CPU-intensive. Higher values use more RAM and CPU. Start with 1 and increase if your system can handle it. Monitor with `docker stats pdfautomagic`.

### OCR Language Support

**Included by default (90%+ global coverage):**
- 🇬🇧 English (eng) - 1.5B speakers
- 🇨🇳 Chinese Simplified (chi-sim) - 1.1B speakers
- 🇪🇸 Spanish (spa) - 560M speakers
- 🇮🇳 Hindi (hin) - 600M speakers
- 🇸🇦 Arabic (ara) - 420M speakers
- 🇫🇷 French (fra) - 280M speakers
- 🇧🇷 Portuguese (por) - 260M speakers
- 🇷🇺 Russian (rus) - 260M speakers
- 🇩🇪 German (deu) - 135M speakers
- 🇯🇵 Japanese (jpn) - 125M speakers

*Speaker counts based on [Ethnologue](https://www.ethnologue.com/insights/ethnologue200/) and [Wikipedia - List of languages by total speakers](https://en.wikipedia.org/wiki/List_of_languages_by_total_number_of_speakers)*

Tesseract **auto-detects** language, so no configuration needed!

**Add more languages:**

For your own use, edit `Dockerfile` and add language packs:
```dockerfile
RUN apt-get update && apt-get install -y \
    tesseract-ocr-ita \  # Italian
    tesseract-ocr-kor \  # Korean
    tesseract-ocr-pol \  # Polish
    tesseract-ocr-tha \  # Thai
    tesseract-ocr-vie    # Vietnamese
```

**Want to add a language to the default set?**
Submit a pull request! If a language has significant usage and would benefit others, we'll include it in the default build.

Available languages: https://packages.ubuntu.com/ (search "tesseract-ocr-")
Full list: https://tesseract-ocr.github.io/tessdoc/Data-Files-in-different-versions.html

**Specify language for OCR:**

By default, Tesseract auto-detects language. To specify a language, edit `import_scanned_documents.sh` line 81:
```bash
# Single language
/usr/bin/ocrmypdf -l fra -rdc ${INPUT_FILE} ${OUTPUT_FILE}

# Multiple languages
/usr/bin/ocrmypdf -l eng+fra+deu -rdc ${INPUT_FILE} ${OUTPUT_FILE}
```

## License

Use as you see fit.
