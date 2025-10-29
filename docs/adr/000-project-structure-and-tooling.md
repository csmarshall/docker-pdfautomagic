# ADR-000: Project structure and tooling decisions

**Status**: Accepted

**Date**: 2025-10-29

## Context

This meta-ADR documents the overall project structure, naming conventions, and tooling choices for PDFAutomagic. This serves as a guide for future maintainers (human or AI).

## Decisions

### Naming

**Product name**: PDFAutomagic
- Chosen because PDFs can come from any source (not just scanners)
- "Automagic" conveys automatic + magic (OCR is magical)
- Rejected: "PDFScanOmatic" (too scanner-specific), "PDFOMatic" (less memorable)

**Repository**: docker-pdfautomagic
- Follows common Docker project naming: `docker-{servicename}`
- Lowercase, hyphenated (Docker Hub convention)

**Container name**: pdfautomagic
- Matches product name in lowercase
- No hyphens (docker-compose container_name convention)

**Main script**: process-pdfs.sh
- Generic, describes what it does
- Renamed from `import_scanned_documents.sh` to match generic branding
- Hyphenated following shell script conventions

### Technology Stack

**Base**: Docker + Docker Compose
- Industry standard for containerization
- Widely supported across platforms
- `docker-compose.yml` for easy deployment

**Language**: Bash
- Simple, no runtime dependencies beyond shell
- Easy to understand and modify
- Sufficient for orchestration tasks

**OCR Engine**: OCRmyPDF + Tesseract
- Industry standard for PDF OCR
- Actively maintained
- Excellent multi-language support

**Cloud Sync**: rclone
- Best-in-class multi-cloud file tool
- 40+ provider support
- Mature, stable, widely used

### File Organization

```
docker-pdfautomagic/
├── docs/
│   └── adr/              # Architecture Decision Records
├── config-example/       # Example configuration
│   ├── post-scan-commands/
│   └── rclone.conf.example
├── .env.example          # Environment template
├── .gitignore           # Prevents committing secrets
├── docker-compose.yml   # Service definition
├── Dockerfile           # Container build
├── entrypoint.sh        # Container entry point (daemon loop)
├── process-pdfs.sh      # Main processing script
├── LICENSE              # MIT
└── README.md            # User documentation
```

### Documentation Standards

**ADR (Architecture Decision Records)**:
- Used for significant architectural decisions
- Numbered sequentially (000-nnn)
- Format: Context → Decision → Consequences
- Located in `docs/adr/`
- Standard format recognized by tooling and developers

**README.md**:
- Quick Start first
- Features prominent
- Rationale for technical choices (Ubuntu vs Alpine)
- Extensive configuration examples
- Troubleshooting section

**Inline comments**:
- Bash scripts have explanatory comments
- Environment variables documented where exported
- Complex logic explained

### Configuration

**Environment-driven**:
- All user configuration via `.env` file
- Sensible defaults in `docker-compose.yml`
- No hardcoded paths in scripts

**Example-based**:
- `config-example/` directory shows working examples
- `.env.example` with detailed comments
- Example post-scan scripts demonstrating patterns

### Git Practices

**.gitignore coverage**:
- Secrets: `.env`, `*.conf`, `rclone.conf`
- User scripts with API keys
- User data directories
- Keep: `config-example/` with sanitized examples

**License**: MIT
- Permissive, widely compatible
- Allows commercial use
- Simple attribution requirement

## Tooling Decisions

### Why not Kubernetes/Helm?

PDFAutomagic is designed as a single-instance background daemon, not a distributed service. Docker Compose is sufficient and more accessible to home users and small deployments.

### Why not Python for orchestration?

Bash is simpler for this use case:
- No dependency management
- No runtime version issues
- Easier for non-programmers to modify
- Sufficient for file watching and process orchestration

Python would add complexity without meaningful benefits.

### Why not a web UI?

PDFAutomagic is intentionally headless:
- Simpler security model (no exposed ports)
- Lower resource usage
- CLI-native (Docker logs, docker-compose)
- Easier to automate and integrate

Future: Could add optional web UI as separate container.

## Principles

1. **Conservative defaults**: Opt-in for performance/advanced features
2. **Clear documentation**: Every decision should be documented
3. **Backward compatibility**: Don't break existing configurations
4. **UNIX philosophy**: Do one thing well, compose via hooks
5. **User empowerment**: Make it easy to extend and customize

## For AI Assistants

If you're an AI helping maintain this project:

1. **Read the ADRs first**: They contain context for why things are the way they are
2. **Don't break backward compatibility**: Users rely on existing `.env` files and scripts
3. **Add ADRs for new decisions**: Any significant architectural change needs an ADR
4. **Update examples**: When adding features, update `config-example/` and README examples
5. **Test conservatively**: Changes should work on low-end hardware (Raspberry Pi)
6. **Maintain naming consistency**: Follow established patterns (environment variable naming, etc.)

## References

- [ADR documentation standard](https://adr.github.io/)
- [Docker Compose best practices](https://docs.docker.com/compose/compose-file/)
- [Semantic Versioning](https://semver.org/)
