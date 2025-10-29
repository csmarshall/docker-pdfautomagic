# ADR-004: Export environment variables to post-scan command hooks

**Status**: Accepted

**Date**: 2025-10-29

## Context

PDFAutomagic supports post-scan command hooks: executable scripts in `/config/post-scan-commands/` that run after successful PDF processing.

Originally, scripts only received a message via stdin:
```
3 files OCRd and uploaded to Dropbox:Cabinet/Documents
```

This is limited. Scripts need structured data for:
- Logging to databases with timestamps
- Triggering webhooks with JSON payloads
- Sending rich notifications
- Updating monitoring systems
- Building audit trails

## Decision

Export comprehensive environment variables to all post-scan command scripts:

**Core variables:**
- `$FILES_PROCESSED` - Number of PDFs processed (integer)
- `$RCLONE_REMOTE` - Cloud storage destination
- `$OUTPUT_DIR` - Where processed PDFs were saved
- `$ORIGINALS_DIR` - Where original PDFs were moved
- `$SCAN_DIR` - Base scan directory

**Timestamp variables:**
- `$PROCESSING_DATE` - Date in YYYY/MM/DD format (for directory structure)
- `$DATE` - ISO date: YYYY-MM-DD
- `$TIME` - ISO time: HH:MM:SS
- `$DATETIME` - Full ISO8601 with timezone: 2025-10-29T14:30:45-0500

## Consequences

### Positive

- **Structured data**: Scripts can access individual fields instead of parsing strings
- **Flexibility**: Easy to build complex integrations (webhooks, databases, monitoring)
- **Timestamps**: Full ISO8601 support for proper logging and time-series data
- **Backward compatible**: stdin message still provided for simple scripts
- **Extensible**: Easy to add new variables in future

### Negative

- **More surface area**: Need to document and maintain these variables
- **Potential breaking changes**: If we rename/remove variables in future

### Neutral

- **Standard pattern**: Environment variables are the Unix way to pass data to child processes
- **Well-documented**: README includes examples showing variable usage

## Examples Enabled

**Logging with timestamps:**
```bash
echo "[${DATETIME}] Processed ${FILES_PROCESSED} files" >> /var/log/pdf.log
```

**JSON webhook:**
```bash
curl -X POST https://api.example.com/notify \
  -d "{\"files\":${FILES_PROCESSED},\"date\":\"${DATE}\",\"time\":\"${TIME}\"}"
```

**Database insert:**
```bash
psql -c "INSERT INTO processing_log (date, files, destination)
         VALUES ('${DATETIME}', ${FILES_PROCESSED}, '${RCLONE_REMOTE}')"
```

## Variable Naming Conventions

- **Uppercase**: Following shell environment variable conventions
- **Descriptive**: `FILES_PROCESSED` not `NUM` or `COUNT`
- **Consistent**: `_DIR` suffix for directories, `_REMOTE` for cloud paths
- **ISO standards**: Date/time formats follow ISO8601

## Future Additions

Possible future variables to add:
- `$FILES_FAILED` - Count of files that failed OCR
- `$PROCESSING_DURATION_SECONDS` - How long the batch took
- `$CONTAINER_HOSTNAME` - For multi-instance setups
- `$PDF_FILENAMES` - List of processed files (newline-separated)

## Notes for Future Maintainers

- **Don't remove variables**: Only add new ones (maintain backward compatibility)
- **Document everything**: Each variable must be in main README and config-example/README
- **Test examples**: Ensure example scripts in docs actually work
- **Consider namespacing**: If adding many more, consider `PDFAUTO_*` prefix to avoid conflicts
