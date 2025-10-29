# Architecture Decision Records (ADR)

This directory contains Architecture Decision Records for PDFAutomagic.

## What is an ADR?

An ADR is a document that captures an important architectural decision made along with its context and consequences.

## Format

Each ADR follows this format:

- **Title**: Short noun phrase
- **Status**: Proposed, Accepted, Deprecated, Superseded
- **Context**: What is the issue we're seeing that is motivating this decision?
- **Decision**: What is the change that we're proposing and/or doing?
- **Consequences**: What becomes easier or more difficult to do because of this change?

## List of ADRs

- [ADR-000](000-project-structure-and-tooling.md) - Project structure, naming, and tooling decisions (READ THIS FIRST)
- [ADR-001](001-use-ubuntu-base-image.md) - Use Ubuntu instead of Alpine for base image
- [ADR-002](002-daemon-mode-only.md) - Daemon-only mode (removed external scheduling)
- [ADR-003](003-parallel-processing-opt-in.md) - Default MAX_PARALLEL_JOBS=1 (opt-in for performance)
- [ADR-004](004-environment-variables-for-hooks.md) - Export environment variables to post-scan commands

## Creating a New ADR

1. Copy the template below
2. Number it sequentially (e.g., `005-your-decision.md`)
3. Fill in all sections
4. Update this README with a link to it

## Template

```markdown
# ADR-XXX: [Short title]

**Status**: Proposed | Accepted | Deprecated | Superseded by ADR-YYY

**Date**: YYYY-MM-DD

## Context

What is the issue we're seeing that is motivating this decision or change?

## Decision

What is the change that we're actually proposing/doing?

## Consequences

What becomes easier or more difficult to do because of this change?

### Positive

- List positive consequences

### Negative

- List negative consequences

### Neutral

- List neutral consequences
```

## References

- [ADR GitHub Organization](https://adr.github.io/)
- [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
