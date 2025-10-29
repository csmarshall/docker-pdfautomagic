# ADR-001: Use Ubuntu 24.04 LTS instead of Alpine Linux for base image

**Status**: Accepted

**Date**: 2025-10-29 (Updated to 24.04 LTS)

## Context

Alpine Linux is the popular choice for Docker base images due to its minimal size (~5MB base image). Many Docker projects default to Alpine to reduce image size, download times, and attack surface.

However, PDFAutomagic has complex requirements:
- OCRmyPDF with multiple dependencies (Ghostscript, Tesseract, Pillow, leptonica, unpaper)
- 10 Tesseract language packs for global language support
- Python libraries with native C extensions
- Image processing tools

Alpine uses musl libc instead of glibc, which can cause compatibility issues with some Python packages and compiled binaries.

## Decision

Use **Ubuntu 24.04 LTS** as the base image instead of Alpine Linux.

**Update**: Originally used 22.04 LTS, updated to 24.04 LTS for extended support and newer package versions.

## Consequences

### Positive

- **OCRmyPDF works out-of-the-box**: All dependencies install cleanly without compatibility issues
- **Complete language support**: All 10 Tesseract language packs are available and well-maintained in Ubuntu repositories
- **Easier debugging**: More familiar environment, better documentation, larger community
- **Python compatibility**: No musl/glibc issues with Pillow, leptonica, or other native libraries
- **Long-term support**: Ubuntu 24.04 LTS is supported until April 2029 (4+ years remaining)
- **Modern packages**: Newer versions of OCRmyPDF, Tesseract, and dependencies compared to 22.04

### Negative

- **Larger image size**: ~500MB final image vs ~200MB with Alpine
- **Slower pulls**: Initial container pull takes longer (~300MB difference)
- **Larger attack surface**: More packages installed by default

### Neutral

- **Not a microservice**: This is a single-instance background daemon, not a horizontally-scaled service, so image size is less critical
- **One-time cost**: Image is built/pulled once, then runs continuously
- **Trade-off accepted**: Reliability and compatibility > 300MB of disk space

## Alternatives Considered

1. **Alpine + manual compilation**: Would require compiling Tesseract and dependencies from source, significantly increasing build complexity and time
2. **Debian Slim**: Similar benefits to Ubuntu but Ubuntu has better Tesseract language pack coverage
3. **Python base image**: Would still need system packages for OCR, doesn't solve the core issue

## Notes for Future Maintainers

If you're considering switching to Alpine:
- Test thoroughly with all 10 language packs
- Verify OCRmyPDF works with `-rdc` flags (rotate, deskew, clean)
- Test unpaper and pngquant functionality
- Check that all Python dependencies (pikepdf, Pillow) compile correctly with musl

The size difference is not worth the compatibility headaches for this use case.
