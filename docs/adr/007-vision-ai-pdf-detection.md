# ADR-007: Vision AI for Intelligent Document Detection

**Status**: Accepted

**Date**: 2026-01-12

## Context

When scanning a stack of mail documents using a duplex scanner, users end up with a single multi-page PDF containing:
- Multiple separate documents (letters, bills, statements)
- Blank pages (backs of single-sided documents)
- Mixed orientations (portrait letters with landscape spreadsheet attachments)

Manually splitting these PDFs is tedious. We need an automated solution that can:
1. Detect and remove blank pages
2. Identify document boundaries (where one letter ends and another begins)
3. Split into separate PDFs for individual documents

### Approaches Considered

1. **Heuristic-based detection**: Use page count patterns, blank page detection, barcode separators
   - Pros: Fast, no ML required
   - Cons: Fragile, can't handle real-world mail variety

2. **OCR-based detection**: Analyze text content for letterheads, dates, addresses
   - Pros: Deterministic
   - Cons: Unreliable for varied layouts, slow OCR before detection

3. **Vision AI detection**: Use a vision language model to analyze each page image
   - Pros: Handles varied layouts, understands visual patterns (letterheads, logos)
   - Cons: Requires GPU or slow CPU inference, model dependency

## Decision

Use **Vision AI (specifically Qwen2.5-VL via Ollama)** for document boundary detection.

The model analyzes each page and determines:
- Is this page blank? (simple pixel density check, no AI needed)
- Is this the first page of a new document? (AI analyzes letterheads, dates, salutations)

### Why Vision AI for Mail

Mail documents have strong visual patterns that Vision AI handles well:
- Letterheads and company logos at top of first pages
- Recipient address blocks
- Dates prominently displayed
- "Page X of Y" indicators
- Portrait cover pages followed by landscape data pages

### Pipeline Architecture

```
Input PDF (multi-page duplex scan)
    │
    ▼
1. Convert to page images (pdf2image)
    │
    ▼
2. Remove blank pages (>97% white pixels)
    │
    ▼
3. Detect document boundaries (Vision AI per page)
    │
    ▼
4. Group & reassemble into separate PDFs (pypdf)
    │
    ▼
5. OCR each document (existing ocrmypdf)
    │
    ▼
6. Cloud sync (existing rclone)
```

## Consequences

### Positive

- Handles real-world mail variety without custom rules
- Can detect document boundaries even with unusual layouts
- Extensible to document classification and smart naming
- User doesn't need to manually split scans

### Negative

- Requires GPU for reasonable performance (or accept slow CPU inference)
- Adds ~6GB model to container (if bundled)
- AI inference adds processing time (~5-6 seconds per page on GPU)
- Model updates may change behavior

### Neutral

- Detection is opt-in (disabled by default)
- Falls back to standard OCR-only processing if detection unavailable
- Can tune prompts to improve accuracy for specific document types
