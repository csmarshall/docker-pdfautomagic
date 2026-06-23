#!/bin/bash

# Example pushover notification using environment variables.
# Available variables: FILES_PROCESSED, RCLONE_REMOTE, OUTPUT_DIR, ORIGINALS_DIR,
#                      PROCESSING_DATE, SCAN_DIR, DATE, TIME, DATETIME
# Detection reliability (Phase 3): SCAN_STATUS (success|partial|failure),
#                      DETECTION_FAILURES, DETECTION_CONSECUTIVE_FAILURES,
#                      DETECTION_AUTO_DISABLED

MESSAGE="PDFAutomagic: ${FILES_PROCESSED} PDF(s) processed at ${TIME} on ${DATE} and uploaded to ${RCLONE_REMOTE}"

# Escalate priority on failures so they stand out; warn if auto-disabled.
PRIORITY=0
case "${SCAN_STATUS:-success}" in
    failure) PRIORITY=1; MESSAGE="⚠️ Detection FAILED this run (${DETECTION_CONSECUTIVE_FAILURES} in a row). ${MESSAGE}" ;;
    partial) MESSAGE="⚠️ Partial success (${DETECTION_FAILURES} detection failure(s)). ${MESSAGE}" ;;
esac
if [[ "${DETECTION_AUTO_DISABLED:-false}" == "true" ]]; then
    PRIORITY=1
    MESSAGE="${MESSAGE} — AI detection is AUTO-DISABLED; running plain OCR until the GPU recovers."
fi

curl -s \
  --form-string "token=YOUR_PUSHOVER_APP_TOKEN" \
  --form-string "user=YOUR_PUSHOVER_USER_KEY" \
  --form-string "title=PDFAutomagic - ${DATE}" \
  --form-string "message=${MESSAGE}" \
  --form-string "priority=${PRIORITY}" \
  --form-string "timestamp=$(date -d "${DATETIME}" +%s)" \
https://api.pushover.net/1/messages.json
