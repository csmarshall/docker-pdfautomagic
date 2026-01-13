# ADR-010: Vision Model Bundling Strategy

**Status**: Accepted

**Date**: 2026-01-12

## Context

The AI document detection feature requires a ~5GB vision language model (Qwen2.5-VL). We need to decide how to distribute this model to users.

### Options Considered

1. **Manual pull after container start**
   ```bash
   docker compose run --rm pdfautomagic ollama pull qwen2.5vl:7b
   ```
   - Pros: Smaller image, model in reusable volume
   - Cons: **Rejected** - Manual setup step is a UX anti-pattern. Users expect containers to just work.

2. **Auto-pull on first run (in entrypoint)**
   - Pros: No manual step
   - Cons: First run blocks for 10+ minutes with unclear progress. Timeout risks.

3. **Bake model into Docker image as separate layer**
   ```dockerfile
   RUN ollama serve & sleep 5 && ollama pull ${MODEL} && pkill ollama
   ```
   - Pros: Just works. Layer is cached separately (~5GB). Subsequent builds/pulls reuse cached layer.
   - Cons: Large image size (~7GB total)

4. **External model server via OLLAMA_HOST**
   - Pros: Shared models across tools, flexible deployment
   - Cons: Requires separate Ollama setup, not "just works"

## Decision

**Bake the model into the image** (Option 3) as the default, while **preserving OLLAMA_HOST support** (Option 4) for advanced users.

### Rationale

1. **"Just works" principle** - Users should be able to `docker compose up` and have a working system. Manual setup steps are an anti-pattern.

2. **Docker layer caching** - The model download is a separate `RUN` instruction, creating an independent ~5GB layer. This layer:
   - Is cached locally after first pull
   - Is cached on Docker Hub and reused across image versions
   - Only re-downloads if the model version changes

3. **Privacy preserved** - The model runs locally. No data leaves the container by default.

4. **Advanced users supported** - `OLLAMA_HOST` environment variable allows pointing to:
   - A shared Ollama server on the local network
   - A NAS or home server with better GPU
   - A centralized model server for multiple AI tools

### Image Size Tradeoffs

| Tag | Contents | Size | Use Case |
|-----|----------|------|----------|
| `latest` | OCR + Ollama + Model | ~7GB | Default, just works |
| `latest-lite` | OCR only | ~800MB | No AI, minimal footprint |

The ~7GB size is acceptable because:
- Layer caching means subsequent pulls are fast
- The alternative (manual setup) is worse UX
- Users who want smaller images can use `latest-lite`

### Layer Structure

```
┌─────────────────────────────────────────┐
│ Layer 1: Ubuntu base (~80MB)            │
├─────────────────────────────────────────┤
│ Layer 2: OCR tools, Tesseract (~700MB)  │
├─────────────────────────────────────────┤
│ Layer 3: Python + deps (~200MB)         │
├─────────────────────────────────────────┤
│ Layer 4: Ollama binary (~100MB)         │
├─────────────────────────────────────────┤
│ Layer 5: Vision model (~5GB)            │  ← Cached separately
├─────────────────────────────────────────┤
│ Layer 6: App scripts (~50KB)            │
└─────────────────────────────────────────┘
```

If we update the app scripts (Layer 6), Docker reuses all previous layers including the 5GB model.

## Consequences

### Positive

- **Zero-config experience** - `docker compose up` and it works
- **Efficient updates** - Model layer cached, only app changes download
- **Privacy by default** - Local model, no external calls
- **Flexibility for power users** - OLLAMA_HOST for shared model servers

### Negative

- **Large initial pull** - ~7GB for first download (mitigated by layer caching)
- **Docker Hub storage** - Large images cost more to host

### Neutral

- **Model updates** - Requires image rebuild, but this ensures version consistency
- **OLLAMA_HOST option** - Available but not required; doesn't compromise privacy-first default

## References

- [Ollama](https://ollama.com) - Local model runtime
- [Qwen2.5-VL](https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct) - Vision language model by Alibaba
- [Docker layer caching](https://docs.docker.com/build/cache/) - How Docker caches build layers
