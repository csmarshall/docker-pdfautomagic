# ADR-002: Daemon-only mode (remove external scheduling support)

**Status**: Accepted

**Date**: 2025-10-29

## Context

Initially, PDFAutomagic supported two modes:
1. **Daemon mode**: Container runs continuously with internal loop checking every N minutes
2. **One-shot mode**: Container runs once and exits, requires external scheduler (cron, systemd, Ofelia)

External scheduling meant container startup/teardown overhead every 5 minutes, plus added complexity in documentation showing three different scheduling approaches (cron, systemd timer, Ofelia).

## Decision

Remove one-shot mode and external scheduling support. Make daemon mode the only way to run PDFAutomagic.

Changes:
- Removed `DAEMON_MODE` environment variable (always daemon now)
- Removed cron/systemd/Ofelia documentation sections
- Simplified `entrypoint.sh` to always run in loop
- Single recommended path: `docker-compose up -d`

## Consequences

### Positive

- **Simpler user experience**: One clear way to run the service
- **Better performance**: No container startup/teardown overhead every cycle
- **Cleaner documentation**: Removed ~80 lines of scheduling examples
- **More reliable**: Container restarts automatically if it crashes (`restart: unless-stopped`)
- **Better monitoring**: Built-in healthcheck with continuous heartbeat

### Negative

- **Less flexible**: Can't easily integrate with existing cron-based workflows
- **Edge cases**: Users with very specific orchestration needs lose the one-shot option

### Neutral

- **Default check interval**: 1 minute is configurable via `INTERVAL_MINUTES`
- **Resource usage**: Daemon uses minimal resources when idle (just sleep)

## Rationale

The original one-shot mode was designed to avoid "running containers indefinitely" but this thinking is outdated:

1. **Docker is designed for long-running containers**: Daemon containers are the norm
2. **Container overhead**: Starting/stopping a container with 500MB image every 5 minutes is wasteful
3. **Complexity**: Three scheduling options confused users and required OS-specific knowledge
4. **Reliability**: `restart: unless-stopped` is simpler than cron job resilience

PDFAutomagic is a background daemon by nature - it should run continuously.

## Migration

Users on one-shot mode can:
1. Set `INTERVAL_MINUTES` to their desired check frequency
2. Run `docker-compose up -d` instead of cron job
3. Remove cron/systemd scheduler entries

## Notes for Future Maintainers

If someone requests one-shot mode:
- Ask about their use case first
- Most "I want cron" requests are actually "I want control over when it runs"
- Consider adding a "pause/resume" API endpoint instead of one-shot mode
- Don't re-add one-shot without strong justification - it adds significant complexity
