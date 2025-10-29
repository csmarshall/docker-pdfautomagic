# ADR-005: Support configurable user/group IDs (PUID/PGID)

**Status**: Accepted

**Date**: 2025-10-29

## Context

PDFAutomagic processes files on the host filesystem via Docker volume mounts. File ownership matters for:

1. **SMB/CIFS shares**: Network scanners upload files as specific users (e.g., "scanner" user)
2. **Permission consistency**: Processed files should maintain same ownership as input files
3. **Multi-user systems**: Different users may run PDFAutomagic with different ownership needs
4. **NFS mounts**: Shared storage often requires specific UID/GID mappings

Without configurable user/group IDs:
- Container runs as root (UID 0) by default
- Created files owned by root → permission conflicts with SMB shares
- Users can't access files created by container
- Security concern: unnecessary root privileges

## Decision

Add `PUID` and `PGID` environment variables to control container user/group IDs:

**docker-compose.yml**:
```yaml
user: "${PUID:-1000}:${PGID:-1000}"
```

**Defaults**: `1000:1000` (typical first user on Linux)

**Configuration**: Users set in `.env` file:
```bash
PUID=1001  # Match scanner user UID
PGID=1003  # Match scanner group GID
```

**Discovery**: Document how to find UID/GID:
- `id username` - shows UID/GID for user
- `ls -n /path` - shows numeric ownership of files
- `stat /path/file` - detailed file ownership info

## Consequences

### Positive

- **Permission compatibility**: Files created by container match host user ownership
- **SMB/CIFS support**: Works seamlessly with network scanner workflows
- **Security**: Container doesn't need to run as root
- **Flexibility**: Each deployment can use different user IDs
- **Industry standard**: Matches pattern used by LinuxServer.io and other Docker projects

### Negative

- **One more config variable**: Users must understand UID/GID concepts
- **Potential confusion**: New Docker users may not know how to find their UID/GID
- **Documentation burden**: Need clear examples and troubleshooting

### Neutral

- **No breaking change**: Defaults to 1000:1000 (typical first user)
- **Well-documented pattern**: Widely used in Docker community
- **README includes example**: Network scanner workflow demonstrates usage

## Implementation Notes

**File naming fix**: Also addressed issue where `.tif` files weren't properly converted to `.pdf` names:
- Before: `scan.tif` → `ocrscan.tif_timestamp.pdf` ❌
- After: `scan.tif` → `ocrscan_timestamp.pdf` ✅

**Documentation**: Added comprehensive "Network Scanner to Cloud Workflow" section to README showing:
1. Creating scanner user with specific UID/GID
2. Configuring Samba share
3. Setting up network scanner device
4. Configuring PDFAutomagic with PUID/PGID
5. Complete workflow example

## Use Cases Enabled

1. **Canon/Brother/HP network scanners** → SMB upload → PDFAutomagic
2. **Shared NFS storage** with specific UID requirements
3. **Multi-user Linux systems** where different users run containers
4. **Docker in NAS devices** (Synology, QNAP) with specific user requirements

## Future Considerations

- Could add entrypoint script to dynamically create user inside container
- Could validate PUID/PGID on startup
- Could add example docker-compose for Synology/QNAP NAS devices

## References

- [LinuxServer.io PUID/PGID documentation](https://docs.linuxserver.io/general/understanding-puid-and-pgid)
- [Docker user namespace documentation](https://docs.docker.com/engine/security/userns-remap/)
