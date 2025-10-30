# Docker Hub Setup for Automated Builds

This document explains how to set up automated Docker image builds and publishing to Docker Hub via GitHub Actions.

## Prerequisites

1. **Docker Hub Account**: Create account at https://hub.docker.com/
2. **GitHub Repository**: https://github.com/csmarshall/docker-pdfautomagic

## Setup Steps

### 1. Create Docker Hub Repository

1. Log in to https://hub.docker.com/
2. Click "Create Repository"
3. Repository name: `pdfautomagic`
4. Description: "Dockerized script that automatically OCRs PDF documents and syncs them to cloud storage"
5. Visibility: Public
6. Click "Create"

Your image will be available as: `csmarshall/pdfautomagic`

### 2. Create Docker Hub Access Token

1. Go to https://hub.docker.com/settings/security
2. Click "New Access Token"
3. Description: "GitHub Actions - docker-pdfautomagic"
4. Access permissions: "Read, Write, Delete"
5. Click "Generate"
6. **Copy the token immediately** (you won't be able to see it again)

### 3. Add Secrets to GitHub Repository

1. Go to https://github.com/csmarshall/docker-pdfautomagic/settings/secrets/actions
2. Click "New repository secret"
3. Add two secrets:

**Secret 1:**
- Name: `DOCKERHUB_USERNAME`
- Value: `csmarshall` (your Docker Hub username)

**Secret 2:**
- Name: `DOCKERHUB_TOKEN`
- Value: (paste the access token from step 2)

### 4. Test the Workflow

The GitHub Actions workflow (`.github/workflows/docker-build.yml`) will automatically run when:

- **Push to main branch**: Builds and pushes `csmarshall/pdfautomagic:latest`
- **Create a tag** (e.g., `v1.0.0`): Builds and pushes version tags
- **Pull request**: Builds only (doesn't push)
- **Manual trigger**: Via GitHub Actions UI

**To manually trigger a build:**
1. Go to https://github.com/csmarshall/docker-pdfautomagic/actions
2. Select "Build and Push Docker Image" workflow
3. Click "Run workflow"

### 5. Create Your First Release

Once the workflow is set up, create a release:

```bash
# Tag the current commit
git tag -a v1.0.0 -m "Initial release: PDFAutomagic v1.0.0"

# Push the tag
git push origin v1.0.0
```

This will trigger the workflow to build and push:
- `csmarshall/pdfautomagic:latest`
- `csmarshall/pdfautomagic:1.0.0`
- `csmarshall/pdfautomagic:1.0`
- `csmarshall/pdfautomagic:1`

## Workflow Details

The workflow:
- Builds for both `linux/amd64` and `linux/arm64` (ARM support for Raspberry Pi, etc.)
- Uses Docker layer caching for faster builds
- Automatically updates Docker Hub description from README.md
- Only pushes on main branch or tags (not on PRs)

## Using Published Images

Once published, users can use the pre-built image instead of building locally:

**Update docker-compose.yml:**
```yaml
services:
  ocr-processor:
    image: csmarshall/pdfautomagic:latest  # Use pre-built image
    # build: .  # Comment out the build line
    container_name: pdfautomagic
    # ... rest of config
```

**Or pull directly:**
```bash
docker pull csmarshall/pdfautomagic:latest
docker pull csmarshall/pdfautomagic:1.0.0  # Specific version
```

## Monitoring Builds

- View build status: https://github.com/csmarshall/docker-pdfautomagic/actions
- View published images: https://hub.docker.com/r/csmarshall/pdfautomagic

## Troubleshooting

**Build fails with authentication error:**
- Verify `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` secrets are set correctly
- Regenerate Docker Hub access token if needed

**Image not appearing on Docker Hub:**
- Check that the workflow ran successfully in GitHub Actions
- Verify you're pushing to main branch or a tag (not a PR)

**Multi-platform build fails:**
- This is usually a transient issue with GitHub Actions runners
- Re-run the workflow

## Security Notes

- Never commit Docker Hub credentials to git
- Access tokens are stored as GitHub Secrets (encrypted)
- Tokens can be revoked at any time from Docker Hub settings
- Use minimal permissions (Read, Write, Delete for this use case)
