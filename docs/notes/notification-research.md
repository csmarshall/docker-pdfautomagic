# Notification System Research

Research notes for adding notification support to PDFAutomagic.

## Current State

The project already has a post-scan hook system:
- Scripts in `/config/post-scan-commands/` run after PDF processing
- Environment variables available: `FILES_PROCESSED`, `RCLONE_REMOTE`, `OUTPUT_DIR`, `ORIGINALS_DIR`, `PROCESSING_DATE`, `SCAN_DIR`, `DATE`, `TIME`, `DATETIME`
- Example Pushover script exists at `config-example/post-scan-commands/pushover_notify.sh`

## Standard Approaches in Docker Ecosystem

### Apprise (Recommended)

**What it is**: Python library/microservice supporting 100+ notification services through unified URL syntax.

**Used by**: Apache Airflow, Dagster, LinuxServer.io containers

**Pushover URL format**: `pover://user_key@app_token`

**Other supported services**: Telegram, Discord, Slack, Gotify, ntfy, Email (SMTP), SMS (Twilio), PagerDuty, and 90+ more

**Integration options**:
1. Install `apprise` Python package in container
2. Use as sidecar container (`lscr.io/linuxserver/apprise-api:latest`)
3. Call CLI: `apprise -t "Title" -b "Body" "pover://user@token"`

**Docker Compose sidecar example**:
```yaml
services:
  apprise-api:
    image: lscr.io/linuxserver/apprise-api:latest
    ports:
      - 8000:8000
    volumes:
      - /path/to/config:/config
    environment:
      - PUID=1000
      - PGID=1000
```

### Shoutrrr (Go-based alternative)

**What it is**: Go library used by Watchtower and other container tools.

**Supports**: ~20 services (Discord, Slack, Telegram, Pushover, Gotify, etc.)

**Pushover URL format**: `pushover://shoutrrr:token@user`

**Lighter weight** than Apprise but fewer providers.

### ntfy (Self-hosted)

**What it is**: Simple HTTP pub/sub notification service.

**Best for**: Users who want full self-hosted control.

**Limitation**: Only one notification channel (ntfy itself), though ntfy can forward to mobile apps.

## Recommended Implementation

### Option A: Built-in Apprise Support (Simplest for users)

Add to Dockerfile:
```dockerfile
RUN apt-get update && apt-get install -y python3-pip \
    && pip3 install apprise \
    && rm -rf /var/lib/apt/lists/*
```

Add to `process-pdfs.sh` after successful processing:
```bash
if [ -n "$APPRISE_URLS" ]; then
    apprise -t "PDFAutomagic" \
        -b "${FILES_PROCESSED} PDF(s) processed and uploaded to ${RCLONE_REMOTE}" \
        $APPRISE_URLS
fi
```

Environment variable:
```bash
# Single provider
APPRISE_URLS="pover://user_key@app_token"

# Multiple providers (space-separated)
APPRISE_URLS="pover://user@token tgram://bot_token/chat_id discord://webhook_id/webhook_token"
```

### Option B: Apprise API Sidecar (No container changes)

Add to docker-compose.yml:
```yaml
services:
  apprise:
    image: lscr.io/linuxserver/apprise-api:latest
    volumes:
      - ./apprise-config:/config
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}

  pdfautomagic:
    # ... existing config ...
    environment:
      - APPRISE_API_URL=http://apprise:8000/notify
```

Then in post-scan hook:
```bash
curl -X POST -d '{"body":"PDFs processed","title":"PDFAutomagic"}' \
    -H "Content-Type: application/json" \
    "$APPRISE_API_URL"
```

### Option C: Keep Current Hook System (Most flexible)

Current system is already good - users can write any notification script.

Improvements:
1. Add more example scripts (ntfy, Discord webhook, Telegram)
2. Document the hook system more prominently
3. Provide a template script with error handling

## Pushover-Specific Notes

User confirmed they use Pushover.

**Current example** (`config-example/post-scan-commands/pushover_notify.sh`):
```bash
#!/bin/bash
MESSAGE="PDFAutomagic: ${FILES_PROCESSED} PDF(s) processed at ${TIME} on ${DATE} and uploaded to ${RCLONE_REMOTE}"

curl -s \
  --form-string "token=YOUR_PUSHOVER_APP_TOKEN" \
  --form-string "user=YOUR_PUSHOVER_USER_KEY" \
  --form-string "title=PDFAutomagic - ${DATE}" \
  --form-string "message=${MESSAGE}" \
  --form-string "timestamp=$(date -d "${DATETIME}" +%s)" \
  https://api.pushover.net/1/messages.json
```

**Improvement**: Use environment variables instead of hardcoded tokens:
```bash
#!/bin/bash
curl -s \
  --form-string "token=${PUSHOVER_APP_TOKEN}" \
  --form-string "user=${PUSHOVER_USER_KEY}" \
  --form-string "title=PDFAutomagic - ${DATE}" \
  --form-string "message=${FILES_PROCESSED} PDF(s) processed" \
  https://api.pushover.net/1/messages.json
```

Then in docker-compose.yml:
```yaml
environment:
  - PUSHOVER_APP_TOKEN=xxx
  - PUSHOVER_USER_KEY=xxx
```

## Decision Matrix

| Approach | Complexity | Flexibility | User Effort | Pushover Support |
|----------|------------|-------------|-------------|------------------|
| Apprise built-in | Medium | Very High | Low | Yes |
| Apprise sidecar | Low | Very High | Medium | Yes |
| Current hooks | None | High | High | Yes (example exists) |
| Improved hooks | Low | High | Medium | Yes |

## Next Steps

1. Decide on approach (recommend: Apprise built-in with fallback to hooks)
2. Update Dockerfile if adding Apprise
3. Update process-pdfs.sh to check for APPRISE_URLS
4. Add documentation
5. Test with Pushover

## References

- Apprise GitHub: https://github.com/caronc/apprise
- Apprise notification URLs: https://github.com/caronc/apprise/wiki
- LinuxServer Apprise API: https://docs.linuxserver.io/images/docker-apprise-api/
- Shoutrrr: https://github.com/containrrr/shoutrrr
- ntfy: https://ntfy.sh/
