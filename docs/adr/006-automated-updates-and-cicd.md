# ADR-006: Automated updates via CI/CD and Watchtower

**Status**: Accepted

**Date**: 2025-10-29

## Context

PDFAutomagic is a long-running daemon that needs regular updates for:
- Security patches in Ubuntu base image
- Updates to OCRmyPDF, Tesseract, and dependencies
- Rclone updates for new cloud provider features
- Bug fixes and feature improvements

Users face several update challenges:
1. **Manual rebuilds are tedious**: Requires `docker-compose build` regularly
2. **Security lag**: Users may not know when security updates are available
3. **Inconsistent versions**: Users building locally get different package versions depending on when they build
4. **No update notifications**: Users don't know when new versions are released

## Decision

Implement two complementary update mechanisms:

### 1. GitHub Actions CI/CD Pipeline

**Automated Docker Hub publishing:**
- Build and push multi-platform images (amd64, arm64) to Docker Hub
- Trigger on:
  - Push to main → `chasmarshall/pdfautomagic:latest`
  - Git tags (e.g., v1.0.0) → versioned tags
  - Manual workflow dispatch
- Update Docker Hub description from README.md automatically

**Benefits:**
- Users can `docker pull` pre-built images instead of building locally
- Consistent builds for all users
- ARM support (Raspberry Pi, Apple Silicon)
- Faster deployment (no local build time)

### 2. Watchtower Integration (Opt-in)

**Automated container updates:**
- Include Watchtower service in docker-compose.yml (commented out by default)
- Automatically pulls new images and restarts containers
- Configurable schedule (default: daily at 4 AM)
- Only watches PDFAutomagic container (doesn't affect other containers)

**Opt-in approach:**
- Watchtower service is commented out in docker-compose.yml
- Users must explicitly uncomment to enable
- Documented in README with clear setup instructions

## Consequences

### Positive

**CI/CD Pipeline:**
- **Faster deployments**: No build time for users
- **Consistent versions**: Everyone gets same package versions
- **Multi-platform support**: Works on x86_64 and ARM devices
- **Professional**: Follows Docker community best practices
- **Versioned releases**: Users can pin to specific versions

**Watchtower:**
- **Automatic security updates**: Container stays current without manual intervention
- **Zero-touch maintenance**: Set-it-and-forget-it for non-technical users
- **Configurable scheduling**: Users control when updates happen
- **Cleanup**: Automatically removes old images to save disk space

### Negative

**CI/CD Pipeline:**
- **GitHub Actions costs**: Free for public repos, but uses compute minutes
- **Docker Hub dependency**: Requires Docker Hub account and maintenance
- **Additional complexity**: More infrastructure to maintain
- **Setup required**: Needs Docker Hub secrets configuration

**Watchtower:**
- **Docker socket access**: Security consideration (needs /var/run/docker.sock)
- **Automatic restarts**: May interrupt processing mid-scan if not scheduled carefully
- **Breaking changes risk**: Auto-updates could introduce bugs (mitigated by opt-in)
- **Less control**: Users may want manual review before updates

### Neutral

- **Both are optional**: Users can still build locally and update manually
- **Well-documented**: README and DOCKER_HUB_SETUP.md explain everything
- **Industry standard**: Both GitHub Actions and Watchtower are widely used patterns

## Implementation Notes

**GitHub Actions Workflow** (`.github/workflows/docker-build.yml`):
- Uses official Docker build actions
- Supports multi-platform builds (buildx)
- Layer caching for faster builds
- Semantic versioning from git tags
- Updates Docker Hub description automatically

**Watchtower Configuration** (docker-compose.yml):
- Commented out by default (opt-in)
- Schedule: `0 0 4 * * *` (daily at 4 AM)
- Cleanup enabled to remove old images
- Watches only PDFAutomagic (not all containers)

**Documentation:**
- `README.md`: Maintenance & Updates section
- `.github/DOCKER_HUB_SETUP.md`: Step-by-step Docker Hub setup
- `docker-compose.yml`: Inline comments for Watchtower

## Alternatives Considered

1. **GitHub Container Registry (ghcr.io) instead of Docker Hub:**
   - Pro: Native GitHub integration, no separate account
   - Con: Less discoverable, Docker Hub is standard for open source
   - Decision: Use Docker Hub for better discoverability

2. **Make Watchtower enabled by default:**
   - Pro: More users get automatic updates
   - Con: Surprising behavior, security concerns
   - Decision: Opt-in is safer, users explicitly choose auto-updates

3. **Weekly/monthly builds instead of continuous:**
   - Pro: Less CI usage
   - Con: Security patches delayed
   - Decision: Build on every push/tag, users control when they pull

## Versioning Strategy

**Semantic Versioning:**
- Major: Breaking changes (e.g., incompatible .env changes)
- Minor: New features (e.g., new configuration options)
- Patch: Bug fixes, security updates

**Git tag triggers image tags:**
```
v1.2.3 → chasmarshall/pdfautomagic:1.2.3
                                   :1.2
                                   :1
                                   :latest
```

Users can:
- Pin to major: `image: chasmarshall/pdfautomagic:1` (gets all 1.x updates)
- Pin to minor: `image: chasmarshall/pdfautomagic:1.2` (gets 1.2.x patches)
- Pin to patch: `image: chasmarshall/pdfautomagic:1.2.3` (exact version)
- Track latest: `image: chasmarshall/pdfautomagic:latest` (default)

## Security Considerations

**CI/CD:**
- Docker Hub credentials stored as GitHub Secrets (encrypted)
- Access token with minimal permissions (Read, Write, Delete only)
- Token can be revoked instantly if compromised
- Workflow only runs on protected branches/tags

**Watchtower:**
- Requires Docker socket access (security consideration documented)
- Only updates single container, not system-wide
- Users opt-in explicitly after reading security note
- Scheduled updates allow predictable maintenance windows

## Future Enhancements

- Add notification support to Watchtower (Slack, Discord, email)
- Implement vulnerability scanning (Snyk, Trivy)
- Add automated testing in CI pipeline
- Create GitHub Release notes automatically
- Badge in README showing latest version

## References

- [Docker Official Build Actions](https://docs.docker.com/build/ci/github-actions/)
- [Watchtower Documentation](https://containrrr.dev/watchtower/)
- [Semantic Versioning 2.0.0](https://semver.org/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
