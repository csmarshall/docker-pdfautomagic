#!/bin/bash

# Example pushover notification using environment variables
# Available variables: FILES_PROCESSED, RCLONE_REMOTE, OUTPUT_DIR, ORIGINALS_DIR,
#                      PROCESSING_DATE, SCAN_DIR, DATE, TIME, DATETIME

MESSAGE="PDFAutomagic: ${FILES_PROCESSED} PDF(s) processed at ${TIME} on ${DATE} and uploaded to ${RCLONE_REMOTE}"

curl -s \
  --form-string "token=YOUR_PUSHOVER_APP_TOKEN" \
  --form-string "user=YOUR_PUSHOVER_USER_KEY" \
  --form-string "title=PDFAutomagic - ${DATE}" \
  --form-string "message=${MESSAGE}" \
  --form-string "timestamp=$(date -d "${DATETIME}" +%s)" \
https://api.pushover.net/1/messages.json
