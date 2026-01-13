# Version Tracking

This document tracks pinned versions and their update sources.

## Automated Updates

| Component | Location | Update Method |
|-----------|----------|---------------|
| Python packages | `detection/requirements.txt` | Dependabot (pip) |
| Ubuntu base image | `Dockerfile` | Dependabot (docker) |
| GitHub Actions | `.github/workflows/` | Dependabot (github-actions) |
| Ollama | `Dockerfile` (ARG OLLAMA_VERSION) | GitHub Action (weekly) |

## Current Versions

### Ollama

| 0.13.5 | `Dockerfile` | [GitHub Releases](https://github.com/ollama/ollama/releases) |

The Ollama version is automatically checked weekly by `.github/workflows/check-ollama-version.yml`.
When a new version is available, a PR is created automatically.

### Vision AI Model

| Model | Size | Location |
|-------|------|----------|
| qwen2.5vl:7b | ~5GB | Baked into image |

The model is baked into the Docker image during build (see [ADR-010](docs/adr/010-model-bundling-strategy.md)).
Model updates require an image rebuild. To use a different model version, rebuild with:
```bash
docker build --build-arg VISION_MODEL=qwen2.5vl:latest -t pdfautomagic:latest .
```

## Version History

| Date | Component | Old Version | New Version | Notes |
|------|-----------|-------------|-------------|-------|
| 2026-01-13 | Ollama | 0.5.4 | 0.13.5 | Update for qwen2.5vl compatibility |
| 2026-01-12 | Ollama | - | 0.5.4 | Initial detection implementation |
