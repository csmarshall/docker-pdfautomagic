# ADR-003: Default MAX_PARALLEL_JOBS=1 (conservative, opt-in for performance)

**Status**: Accepted

**Date**: 2025-10-29

## Context

PDFAutomagic supports parallel PDF processing via the `MAX_PARALLEL_JOBS` environment variable. Processing multiple PDFs simultaneously can significantly speed up throughput (3x faster with `MAX_PARALLEL_JOBS=3`).

However, OCR is CPU-intensive. Each OCRmyPDF process can:
- Use 100% of a CPU core
- Consume 200-500MB of RAM per file
- Generate significant I/O load

The question: Should we default to parallel processing (e.g., 3 jobs) for speed, or sequential processing (1 job) for safety?

## Decision

Default `MAX_PARALLEL_JOBS=1` (sequential processing). Users must opt-in to parallel processing by explicitly setting a higher value.

## Consequences

### Positive

- **Conservative defaults**: Won't overwhelm low-power devices (Raspberry Pi, NAS boxes)
- **Predictable resource usage**: Users know exactly what they're getting
- **Safer for shared systems**: Won't starve other services of CPU/RAM
- **Better first-run experience**: Works reliably on any hardware
- **Clear upgrade path**: Documentation shows how to increase for better performance

### Negative

- **Slower out-of-box**: Users with powerful hardware don't benefit from parallelism by default
- **Manual optimization**: Users must actively choose to enable parallel processing

### Neutral

- **Easy to change**: Single environment variable in `.env`
- **Well-documented**: README clearly explains the trade-offs and recommendations

## Rationale

**Principle**: Defaults should be conservative and safe. Performance optimizations should be opt-in.

Reasoning:
1. **Unknown hardware**: We don't know if users run on Raspberry Pi or a 32-core server
2. **Silent failures**: High CPU/memory usage can cause:
   - System slowdowns
   - OOM kills
   - Degraded performance for other containers
3. **Bad first impression**: If default settings cause problems, users lose trust
4. **Easy upgrade**: Going from 1→3 jobs is trivial; debugging why your system is slow is not

## Recommendations in Documentation

- **Default (1 job)**: Conservative, works everywhere
- **Desktop/Server (3-4 jobs)**: Good balance for modern hardware
- **Powerful server (5-8 jobs)**: Maximum throughput

Users can monitor with `docker stats pdfautomagic` and adjust.

## Alternatives Considered

1. **Auto-detect CPU cores**: Too complex, doesn't account for RAM or shared systems
2. **Default to 3**: Risk overwhelming constrained environments
3. **Remove parallel support**: Unnecessarily limiting for power users

## Notes for Future Maintainers

- If adding auto-detection, consider cgroup limits and available memory, not just CPU count
- Consider adding a warning if `MAX_PARALLEL_JOBS > 1` and available memory is low
- Don't change the default to > 1 without strong justification
