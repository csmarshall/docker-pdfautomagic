# Installation Notes for Base System Testing

These are the dependencies installed on the base system for testing.
Use this to replicate in Docker or to back out changes.

## System Packages

```bash
# For pdf2image (converts PDF pages to images)
sudo apt-get install poppler-utils
```

## Ollama

```bash
# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# To uninstall later:
# sudo rm -rf /usr/local/bin/ollama
# sudo rm -rf ~/.ollama
# sudo systemctl stop ollama
# sudo systemctl disable ollama
# sudo rm /etc/systemd/system/ollama.service
```

## Ollama Models

```bash
# Pull vision model (~5GB)
ollama pull qwen2.5vl:7b

# To remove later:
# ollama rm qwen2.5vl:7b
```

## Python Dependencies

```bash
# Create virtual environment
cd detection
python3 -m venv .venv

# Install dependencies
.venv/bin/pip install -r requirements.txt

# To remove later:
# rm -rf .venv
```

## Docker Equivalent

When containerizing, the Dockerfile will need:
```dockerfile
# System deps
RUN apt-get update && apt-get install -y poppler-utils

# Python deps
COPY requirements.txt .
RUN pip install -r requirements.txt

# Ollama - either:
# 1. Run as sidecar container, or
# 2. Install in same container (heavier)
```
