# Testing Guide for PDFAutomagic

This guide helps you test PDFAutomagic on a new machine to ensure everything works correctly.

## Prerequisites

On the test machine, you'll need:
- Docker and Docker Compose installed
- Access to clone the GitHub repo
- A cloud storage account for rclone (Dropbox, Google Drive, etc.)
- A test PDF file (can be any PDF, even without text)

## Test Setup

### 1. Clone and Build

```bash
# Clone the repository
git clone https://github.com/csmarshall/docker-pdfautomagic.git
cd docker-pdfautomagic

# Build the container (this will take 5-10 minutes first time)
docker-compose build
```

**Expected output:**
- Should download Ubuntu base image
- Install all dependencies (ocrmypdf, tesseract, rclone, etc.)
- No errors during build
- Final image size ~500MB

### 2. Configure rclone

```bash
# Copy example config
cp -r config-example test-config

# Configure rclone with your cloud storage
rclone config --config test-config/rclone.conf
```

**Follow the prompts to:**
1. Create a new remote (name it "Dropbox" or "GoogleDrive" or whatever)
2. Choose your cloud provider
3. Authenticate (will open browser)
4. Test with: `rclone lsd YOUR_REMOTE: --config test-config/rclone.conf`

### 3. Create Test Environment

```bash
# Create test directories
mkdir -p ~/pdfautomagic-test/unprocessed

# Create .env file
cat > .env << 'EOF'
SCAN_DIR=/Users/YOUR_USERNAME/pdfautomagic-test
CONFIG_DIR=/Users/YOUR_USERNAME/docker-pdfautomagic/test-config
RCLONE_REMOTE=YOUR_REMOTE:PDFAutomagicTest
INTERVAL_MINUTES=1
MAX_PARALLEL_JOBS=1
MINUTES_OLD=0
TIMEZONE=America/Chicago
EOF

# Edit .env with your actual paths
nano .env
```

**Important:** Set `MINUTES_OLD=0` for testing so files are processed immediately.

### 4. Get a Test PDF

```bash
# Option 1: Create a simple test PDF
echo "This is a test document" | enscript -B -p - | ps2pdf - ~/pdfautomagic-test/unprocessed/test1.pdf

# Option 2: Download a sample
curl -o ~/pdfautomagic-test/unprocessed/sample.pdf \
  https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf

# Option 3: Copy any PDF you have
cp /path/to/your.pdf ~/pdfautomagic-test/unprocessed/
```

## Run Tests

### Test 1: Container Starts

```bash
# Start the container
docker-compose up

# Expected output:
# - "PDFAutomagic starting..."
# - "Validating configuration..."
# - "Configuration validated successfully"
# - "Starting PDFAutomagic daemon (checking every 1 minute(s))"
# - "[TIMESTAMP] Heartbeat - Starting check cycle"
```

**If you see errors:**
- "Scan directory not found" → Check SCAN_DIR path in .env
- "rclone.conf not found" → Check CONFIG_DIR path in .env
- "RCLONE_REMOTE environment variable not set" → Check .env file

### Test 2: PDF Processing

With the container running, watch the logs:

```bash
# In another terminal, check logs
docker-compose logs -f
```

**Expected sequence:**
1. "Found X to scan in /scans/unprocessed"
2. "Processing with MAX_PARALLEL_JOBS=1"
3. "Processing [filename] to [output]"
4. OCRmyPDF progress output
5. "OCR successful for [filename]"
6. "Moving [filename] to [originals]"
7. "All files processed"
8. "Rclone to [YOUR_REMOTE]"
9. "Running post-processing commands"

**Check results:**
```bash
# Should see directories created
ls -la ~/pdfautomagic-test/

# Should have processed/ and originals/ with today's date
ls -la ~/pdfautomagic-test/processed/
ls -la ~/pdfautomagic-test/originals/

# Original should be in originals/YYYY/MM/DD/
# OCR'd version should be in processed/YYYY/MM/DD/
```

**Verify cloud upload:**
```bash
# List remote files
rclone ls YOUR_REMOTE:PDFAutomagicTest --config test-config/rclone.conf
```

### Test 3: Healthcheck

```bash
# Check container health
docker ps

# Should show "healthy" in STATUS column after ~30 seconds

# Detailed health info
docker inspect pdfautomagic --format='{{json .State.Health}}' | jq
```

### Test 4: Stop and Restart

```bash
# Stop container
docker-compose down

# Should see:
# - Lock file cleanup
# - Clean exit

# Restart
docker-compose up -d

# Run in background, check it's running
docker ps
docker-compose logs --tail=20
```

## Test Checklist

- [ ] Container builds without errors
- [ ] Container starts and passes validation
- [ ] Heartbeat logs appear every minute
- [ ] PDF is processed and OCR'd
- [ ] Original moved to originals/YYYY/MM/DD/
- [ ] Processed file in processed/YYYY/MM/DD/
- [ ] Files uploaded to cloud storage
- [ ] Container shows "healthy" status
- [ ] Container restarts cleanly
- [ ] Logs are clear and informative

## Advanced Tests

### Test Parallel Processing

Edit `.env`:
```bash
MAX_PARALLEL_JOBS=3
```

Restart container and add 5+ PDFs to unprocessed/:
```bash
docker-compose restart
cp test*.pdf ~/pdfautomagic-test/unprocessed/
```

Watch logs - should see multiple "Processing" lines simultaneously.

### Test Post-Scan Commands

Create a test hook:
```bash
cat > test-config/post-scan-commands/test-hook.sh << 'EOF'
#!/bin/bash
echo "HOOK EXECUTED!"
echo "Files processed: ${FILES_PROCESSED}"
echo "Date: ${DATE} Time: ${TIME}"
echo "Output: ${OUTPUT_DIR}"
EOF

chmod +x test-config/post-scan-commands/test-hook.sh

# Restart and watch for hook output
docker-compose restart
```

### Test Multiple Languages

Create PDFs with different languages and verify OCR works.

## Common Issues

### Issue: "Already running under pid XXX"

**Cause:** Lock file from previous crashed run

**Fix:**
```bash
docker-compose exec ocr-processor rm /tmp/import_scanned_documents.sh.lock
# or
docker-compose restart
```

### Issue: OCR fails with "error"

**Check:**
- Is the PDF valid? `file test.pdf`
- Enough disk space? `df -h`
- Enough memory? `docker stats pdfautomagic`

### Issue: Files not uploading to cloud

**Check:**
```bash
# Test rclone directly
docker-compose exec ocr-processor rclone ls YOUR_REMOTE: --config /config/rclone.conf

# Check rclone config
docker-compose exec ocr-processor cat /config/rclone.conf
```

### Issue: Container unhealthy

**Check:**
```bash
# Detailed health status
docker inspect pdfautomagic | grep -A 10 Health

# Check heartbeat file
docker exec pdfautomagic cat /tmp/pdfautomagic.heartbeat

# Should be recent timestamp
```

## Performance Benchmarks

On a typical system (4-core, 8GB RAM):

- **Container start:** ~2-5 seconds
- **OCR single page PDF:** ~5-10 seconds
- **OCR 10-page PDF:** ~30-60 seconds
- **Upload to cloud:** ~1-5 seconds (depends on connection)
- **Memory usage (idle):** ~50MB
- **Memory usage (processing 1 PDF):** ~200-300MB
- **Memory usage (processing 3 parallel):** ~600-900MB

## Success Criteria

✅ All items in the test checklist pass
✅ No errors in logs
✅ Files appear in cloud storage
✅ Container remains healthy over time (leave running for 1 hour)
✅ Processes at least 5 different PDFs successfully

## Cleanup

After testing:
```bash
# Stop container
docker-compose down

# Remove test data
rm -rf ~/pdfautomagic-test

# Remove test config
rm -rf test-config

# Optional: Remove Docker image to free space
docker rmi $(docker images | grep pdfautomagic | awk '{print $3}')
```

## Reporting Issues

If you find bugs during testing:

1. Check existing issues: https://github.com/csmarshall/docker-pdfautomagic/issues
2. Create new issue with:
   - System info: `docker version`, `docker-compose version`, OS
   - Full logs: `docker-compose logs`
   - Steps to reproduce
   - Expected vs actual behavior
