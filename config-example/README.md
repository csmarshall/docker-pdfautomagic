# Configuration Directory

This directory should contain:

## Required:

### `rclone.conf`
Rclone configuration file with cloud storage credentials.

To create:
```bash
rclone config
```

Follow the prompts to create a remote (e.g., "Dropbox", "GoogleDrive", "S3").

See `rclone.conf.example` for reference and https://rclone.org/ for supported providers.

## Optional:

### `post-scan-commands/`
Directory containing executable scripts that run after OCR and cloud sync.

**Environment variables available to scripts:**
- `$FILES_PROCESSED` - Number of PDFs processed
- `$RCLONE_REMOTE` - Cloud storage destination
- `$OUTPUT_DIR` - Where processed PDFs were saved
- `$ORIGINALS_DIR` - Where original PDFs were moved
- `$PROCESSING_DATE` - Date stamp (YYYY/MM/DD format, used for directory structure)
- `$SCAN_DIR` - Base scan directory
- `$DATE` - Processing date (YYYY-MM-DD format)
- `$TIME` - Processing time (HH:MM:SS format)
- `$DATETIME` - Full ISO8601 timestamp with timezone (e.g., 2025-10-29T14:30:45-0500)

Scripts also receive a message via stdin:
```
{number} files OCRd and uploaded to {RCLONE_REMOTE}
```

**Example:** `pushover_notify.sh` sends push notifications using these variables.

To add your own commands:
1. Create an executable script in this directory
2. Make it executable: `chmod +x post-scan-commands/your-script.sh`
3. Scripts are executed in alphabetical order
4. Use environment variables for flexible automation
