# ADR-011: Force OCR Over Existing Text

**Status**: Accepted

**Date**: 2026-01-13

## Context

Many modern scanners (Canon, HP, Epson, etc.) include built-in OCR that embeds text layers in scanned PDFs. When PDFAutomagic processes these files, we need to decide how to handle existing OCR data.

### Options Considered

1. **`--skip-text` (ocrmypdf default)**
   - Skip pages that already have text, only OCR blank pages
   - Pros: Faster, preserves existing work
   - Cons: Scanner OCR quality varies wildly; older/cheaper scanners produce poor results

2. **`--redo-ocr`**
   - Re-run OCR on pages with existing text, attempt to preserve vector content
   - Pros: Improves quality while preserving vectors
   - Cons: **Not compatible** with `--deskew`, `--clean`, `--rotate-pages`

3. **`--force-ocr`**
   - Rasterize all pages and perform fresh OCR
   - Pros: Consistent quality, compatible with all image processing options
   - Cons: Converts vectors to raster (irrelevant for scanned documents)

## Decision

**Use `--force-ocr`** to always discard existing OCR and perform fresh Tesseract OCR.

### Rationale

1. **Software updates vs hardware** - Tesseract receives regular updates improving accuracy, language support, and handling of edge cases. Scanner firmware updates are rare and often require manual intervention. Over time, Tesseract's OCR quality will increasingly exceed scanner-embedded OCR.

2. **Consistency** - All documents processed by PDFAutomagic will have consistent OCR quality regardless of which scanner produced them or when.

3. **Feature compatibility** - `--force-ocr` is compatible with all image enhancement options:
   - `--deskew` - Straighten skewed scans
   - `--clean` - Remove scanning artifacts/noise
   - `--rotate-pages` - Auto-correct page orientation

4. **Use case is scanned documents** - PDFAutomagic processes scanned mail and documents, which are already raster images. The "downside" of rasterizing vector content is irrelevant since there's no vector content to preserve.

### Final ocrmypdf Command

```bash
ocrmypdf --force-ocr --deskew --clean --rotate-pages input.pdf output.pdf
```

| Flag | Purpose |
|------|---------|
| `--force-ocr` | Discard existing OCR, rasterize, and re-OCR everything |
| `--deskew` | Straighten pages skewed during scanning |
| `--clean` | Remove noise and scanning artifacts |
| `--rotate-pages` | Auto-detect and correct page orientation |

## Consequences

### Positive

- **Consistent quality** - All output PDFs have the same high-quality Tesseract OCR
- **Future-proof** - Benefits from Tesseract improvements automatically
- **Full image processing** - All enhancement options available

### Negative

- **Slightly slower** - Re-OCRs pages that already had text
- **Rasterizes vectors** - Any vector content becomes raster (not applicable to scanned documents)

### Neutral

- **Larger intermediate files** - Rasterization may increase temp file sizes during processing

## References

- [ocrmypdf documentation](https://ocrmypdf.readthedocs.io/en/latest/cookbook.html#ocr-and-correct-document-skew-rotation)
- [Tesseract OCR](https://github.com/tesseract-ocr/tesseract) - The OCR engine used by ocrmypdf
