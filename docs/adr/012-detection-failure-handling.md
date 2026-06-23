# ADR-012: Detection Failure Handling (Auto-Disable & Backoff)

**Status**: Accepted

**Date**: 2026-06-23

## Context

AI document detection depends on a working GPU and a loadable vision model.
These can fail at runtime in ways unrelated to the PDFs being processed:

- A kernel upgrade leaves the NVIDIA driver/module mismatched and `nvidia-smi`
  fails, so every detection call errors.
- The model fails to load (corrupt download, OOM, Ollama upgrade incompatibility).
- The container loses GPU access (CDI / nvidia-container-toolkit issues).

PDFAutomagic runs as a daemon scanning for new files every `INTERVAL_MINUTES`
(default 1). Before this change, when detection failed it logged an error,
fell back to plain OCR for that file, and tried detection again on the very
next run — re-paying the (often slow) failure cost and re-emitting the same
error/notification every minute, indefinitely. There was no memory of repeated
failure and no way for a notification hook to distinguish a healthy run from a
persistently broken one.

### Options Considered

1. **Do nothing (status quo)** — retry detection every run.
   - Pros: simplest; recovers instantly when the GPU returns.
   - Cons: wastes time on a known-broken path; spams logs/notifications;
     no signal to operators that detection is degraded.

2. **Hard-disable on first failure** — set a flag and never retry.
   - Pros: stops the waste immediately.
   - Cons: a single transient hiccup permanently disables detection until a
     human intervenes; no auto-recovery.

3. **Consecutive-failure counter with auto-disable + auto-recovery** (chosen).
   - Tolerate transient blips, disable only on sustained failure, recover
     automatically when the GPU/model is healthy again.

## Decision

Track **consecutive failed runs** in a state file and **auto-disable** detection
once they reach `DETECTION_FAILURE_THRESHOLD` (default `3`), falling back to
plain OCR. Auto-recover when a GPU re-check passes; rate-limit the warning with
`DETECTION_BACKOFF_MINUTES` (default `15`). Expose detection health to post-scan
hooks so operators can be notified.

### Mechanics

- **State** lives in `/tmp/pdfautomagic.detection-failures` (and a backoff
  timestamp in `/tmp/pdfautomagic.detection-backoff`). `/tmp` is chosen so state
  persists across the per-interval runs for the container's lifetime and resets
  on restart — a restart is a reasonable "try again from scratch" signal.
- **Counting is per-run and parallel-safe.** Each detection attempt appends a
  single byte (`S`/`F`) to a per-run marker file (atomic under `O_APPEND`), so
  it is correct under `MAX_PARALLEL_JOBS > 1`. After the run: any success resets
  the counter to 0; a run where detection was attempted and *every* attempt
  failed increments it.
- **Auto-disable gate** runs in `check_detection_available()`: at/above the
  threshold it re-checks the GPU (`split_pdf.py --check-gpu`); if that passes it
  clears the counter and re-enables, otherwise it logs a prominent warning (at
  most once per backoff window) and skips detection for that run.
- **Manual reset**: delete the state file inside the container.

### Hook variables

Post-scan hooks (see [ADR-004](004-environment-variables-for-hooks.md)) receive:

| Variable | Meaning |
|----------|---------|
| `SCAN_STATUS` | `success` \| `partial` \| `failure` |
| `DETECTION_FAILURES` | Detection failures in this run |
| `DETECTION_CONSECUTIVE_FAILURES` | Running consecutive-failure count |
| `DETECTION_AUTO_DISABLED` | `true` when detection is currently auto-disabled |

## Consequences

### Positive

- **Resilient** — a broken GPU/model degrades gracefully to OCR instead of
  failing every file, and recovers on its own.
- **Quiet** — backoff stops per-minute log/notification spam while degraded.
- **Observable** — hooks can alert on `failure`/auto-disable and stay silent on
  healthy runs.
- **Configurable** — threshold and backoff are env vars; `THRESHOLD=0` opts out.

### Negative

- **Up to N slow failing runs** before auto-disable kicks in (bounded by the
  threshold).
- **State resets on container restart**, so a restart re-attempts detection even
  if the GPU is still broken (acceptable, and arguably desirable).

### Neutral

- Adds a small amount of bookkeeping to the main processing loop.

## References

- [ADR-004](004-environment-variables-for-hooks.md) - Post-scan hook environment variables
- [ADR-007](007-vision-ai-pdf-detection.md) - Vision AI for document detection
- `detection/README.md` - Phase 3 roadmap (Reliability & Notifications)
