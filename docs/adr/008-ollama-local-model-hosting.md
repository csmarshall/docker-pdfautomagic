# ADR-008: Ollama for Local Vision Model Hosting

**Status**: Accepted

**Date**: 2026-01-12

## Context

The Vision AI document detection feature (ADR-007) requires running a vision language model. We need to decide how to host and run this model.

### Security & Privacy Requirement

PDFAutomagic is designed to process **personal mail** - bills, bank statements, medical documents, tax forms, and other sensitive materials. Sending this content to cloud AI APIs would be a significant security and privacy risk. **Local-only processing is a core requirement, not just a preference.**

### Options Considered

1. **Cloud API (OpenAI GPT-4V, Anthropic Claude, Google Gemini)**
   - Pros: No local GPU needed, always up-to-date models
   - Cons: **Rejected** - Per-request cost, requires internet, and critically: sends personal document content to third-party servers

2. **Direct model loading (transformers, llama.cpp)**
   - Pros: Full control, no external dependencies
   - Cons: Complex setup, manual model management, GPU configuration

3. **Ollama**
   - Pros: Simple CLI, handles GPU detection, model management, API server
   - Cons: Additional service to run, limited to Ollama-supported models

4. **LocalAI / LM Studio**
   - Pros: OpenAI-compatible API
   - Cons: Less mature, smaller community

## Decision

Use **Ollama** for local model hosting.

### Model Selection: Qwen2.5-VL:7B

After evaluating available vision models:

| Model | VRAM | Accuracy | Speed | Ollama Support |
|-------|------|----------|-------|----------------|
| Qwen2.5-VL 7B | ~14GB | Excellent | Fast | ✅ Yes |
| LLaVA 1.6 7B | ~14GB | Good | Fast | ✅ Yes |
| Florence-2 | ~4GB | Good | Very Fast | ❌ No |

Qwen2.5-VL was selected because:
- Excellent document understanding capabilities
- Native Ollama support (`ollama pull qwen2.5vl:7b`)
- Good balance of accuracy and speed
- Fits in 16GB VRAM

### GPU Support Matrix

Ollama supports:

| GPU Type | Backend | Supported |
|----------|---------|-----------|
| NVIDIA | CUDA | ✅ Yes |
| AMD | ROCm | ✅ Yes (Linux) |
| Apple Silicon | Metal | ✅ Yes |
| Intel Arc/iGPU | oneAPI | ❌ No |

For Intel GPU users, we provide a helpful error message pointing to the Ollama GitHub issue tracking Intel support.

### Integration Architecture

```
┌─────────────────────┐     HTTP API      ┌─────────────┐
│  PDFAutomagic       │ ───────────────── │   Ollama    │
│  (split_pdf.py)     │   localhost:11434 │   Server    │
└─────────────────────┘                   └─────────────┘
                                                │
                                          ┌─────┴─────┐
                                          │ qwen2.5vl │
                                          │   :7b     │
                                          └───────────┘
```

The Python detection script uses the `ollama` Python package which communicates with the Ollama server via HTTP API.

## Consequences

### Positive

- **Privacy-first** - All document processing stays local; no content ever leaves your machine
- Simple model management (`ollama pull`, `ollama rm`)
- Automatic GPU detection and utilization
- Model persistence across container restarts
- Easy to switch models for experimentation
- Large community and model library

### Negative

- Adds Ollama as a dependency
- Limited to models Ollama supports
- Intel GPU users cannot use GPU acceleration
- Model must be pulled separately (~5GB download)

### Neutral

- Ollama can run as embedded service or sidecar container
- CPU fallback available (with significant performance penalty)
- Model version pinned to avoid unexpected behavior changes
