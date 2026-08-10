#!/usr/bin/env bash
#
# update-deployment.sh — update a running PDFAutomagic deployment to the current
# published image, verify it came up healthy, and roll back automatically if it
# did not.
#
# PDFAutomagic is rebuilt and pushed to Docker Hub on a schedule, so the deployed
# container drifts behind the published image over time. This script makes that
# update a single reviewable step instead of an ad-hoc pull-and-pray.
#
# It is deliberately host-agnostic: no absolute paths, no hardcoded image IDs.
# Point it at the directory holding your compose file.
#
# Usage:
#   ./update-deployment.sh [-d DIR] [-f FILE] [-s SERVICE] [--check] [--rollback]
#                          [--timeout SECONDS] [--no-auto-rollback]
#
#   --check             Report whether an update is available. Changes nothing.
#   --rollback          Restore the image recorded by the last successful run.
#   --timeout SECONDS   How long to wait for health (default 180).
#   --no-auto-rollback  Leave a failed update in place for debugging.
#
# Exit codes:
#   0  success, or --check found the deployment already current
#   1  usage error / precondition failure (nothing was changed)
#   2  --check found an update available
#   3  update failed and was rolled back
#   4  update failed and could NOT be rolled back — needs a human
#
unset TMOUT
set -euo pipefail

COMPOSE_DIR=""
COMPOSE_FILE="docker-compose.yml"
SERVICE="pdfautomagic"
HEALTH_TIMEOUT=180
MODE="update"
AUTO_ROLLBACK=1

SCRIPT_NAME=$(basename "$0")

log() { printf '%s [%s] %s\n' "$(date +'%F %T')" "$1" "$2"; }
die() { log ERROR "$2"; exit "$1"; }

usage() { sed -n '3,28p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d) COMPOSE_DIR="${2:?-d needs a directory}"; shift 2 ;;
        -f) COMPOSE_FILE="${2:?-f needs a filename}"; shift 2 ;;
        -s) SERVICE="${2:?-s needs a service name}"; shift 2 ;;
        --timeout) HEALTH_TIMEOUT="${2:?--timeout needs seconds}"; shift 2 ;;
        --check) MODE="check"; shift ;;
        --rollback) MODE="rollback"; shift ;;
        --no-auto-rollback) AUTO_ROLLBACK=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) log ERROR "Unknown argument: $1"; usage; exit 1 ;;
    esac
done

# Default to the directory this script lives in, so a checkout that sits beside
# its compose file works with no arguments.
if [[ -z "${COMPOSE_DIR}" ]]; then
    COMPOSE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
fi

[[ -d "${COMPOSE_DIR}" ]] || die 1 "Compose directory not found: ${COMPOSE_DIR}"
[[ -e "${COMPOSE_DIR}/${COMPOSE_FILE}" ]] || \
    die 1 "Compose file not found: ${COMPOSE_DIR}/${COMPOSE_FILE}"

# Not every host puts the invoking user in the docker group.
DOCKER="docker"
if ! docker info >/dev/null 2>&1; then
    if sudo -n docker info >/dev/null 2>&1 || sudo docker info >/dev/null 2>&1; then
        DOCKER="sudo docker"
    else
        die 1 "Cannot talk to the Docker daemon, with or without sudo."
    fi
fi

compose() { ${DOCKER} compose -f "${COMPOSE_FILE}" "$@"; }

cd "${COMPOSE_DIR}"

# Compose reads .env from the project directory, which is the path given on the
# command line — NOT the target of a symlinked compose file. A deploy directory
# holding only a symlink to a compose file elsewhere will therefore expand every
# ${VAR} to an empty string, and the failure surfaces as a confusing bind-mount
# error ("invalid spec: :/scans: empty section between colons") rather than as a
# missing-file error. Check for it directly so the diagnosis is obvious.
if ! compose config --quiet 2>/dev/null; then
    log ERROR "Compose file does not validate in ${COMPOSE_DIR}."
    if [[ ! -e "${COMPOSE_DIR}/.env" ]]; then
        log ERROR "There is no .env in ${COMPOSE_DIR}. Compose resolves .env relative to"
        log ERROR "this directory, not to the target of a symlinked compose file."
    fi
    compose config 2>&1 | sed 's/^/    /'
    exit 1
fi

IMAGE_REF=$(compose config --images "${SERVICE}" | sed -n '1p')
[[ -n "${IMAGE_REF}" ]] || die 1 "Could not determine the image for service ${SERVICE}."

STATE_FILE="${COMPOSE_DIR}/.${SCRIPT_NAME%.sh}.previous-image"

current_image_id() {
    ${DOCKER} image inspect "${IMAGE_REF}" --format '{{.Id}}' 2>/dev/null || true
}

# Digest the registry currently serves for a tag — i.e. exactly what a pull would
# fetch. Printed empty (and non-zero) when it cannot be determined, so callers can
# refuse to guess rather than report a bogus "up to date".
#
# `docker manifest inspect --verbose` is deliberately NOT used here: for a
# single-platform image it reports the platform manifest digest, which does not
# equal the tag digest recorded in RepoDigests, so the comparison would report a
# spurious update on every run.
registry_digest() {
    local ref="$1" repo tag token accept

    ref="${ref#docker.io/}"
    ref="${ref#index.docker.io/}"

    # Only Docker Hub is handled. A ref carrying its own registry host (a dot or
    # colon before the first slash) is somebody else's API.
    if [[ "${ref%%/*}" == *.* || "${ref%%/*}" == *:* ]]; then
        return 1
    fi

    if [[ "${ref}" == *:* ]]; then
        tag="${ref##*:}"; repo="${ref%:*}"
    else
        tag="latest"; repo="${ref}"
    fi
    # Official images live under library/.
    [[ "${repo}" == */* ]] || repo="library/${repo}"

    token=$(curl -fsS --max-time 20 \
        "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repo}:pull" \
        2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("token",""))' 2>/dev/null) || return 1
    [[ -n "${token}" ]] || return 1

    accept='application/vnd.oci.image.index.v1+json'
    accept+=',application/vnd.docker.distribution.manifest.list.v2+json'
    accept+=',application/vnd.docker.distribution.manifest.v2+json'
    accept+=',application/vnd.oci.image.manifest.v1+json'

    # HEAD only: the Docker-Content-Digest header is the answer, so there is no
    # need to transfer the manifest body, let alone any layers.
    curl -fsSI --max-time 20 -H "Authorization: Bearer ${token}" -H "Accept: ${accept}" \
        "https://registry-1.docker.io/v2/${repo}/manifests/${tag}" 2>/dev/null \
        | tr -d '\r' \
        | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest:[[:space:]]*//p' \
        | sed -n '1p'
}

# Wait for the container to report healthy. A container with no healthcheck is
# treated as "running is good enough", but a container that exits is a failure
# regardless — otherwise a crash-looping update would look like a slow one.
wait_for_health() {
    local deadline=$((SECONDS + HEALTH_TIMEOUT)) state health
    while (( SECONDS < deadline )); do
        state=$(${DOCKER} inspect "${SERVICE}" --format '{{.State.Status}}' 2>/dev/null || echo missing)
        health=$(${DOCKER} inspect "${SERVICE}" \
            --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null || echo none)
        case "${state}:${health}" in
            running:healthy) echo healthy;   return 0 ;;
            running:none)    echo running;   return 0 ;;
            running:starting) ;;
            running:unhealthy) echo unhealthy; return 1 ;;
            exited:*|dead:*) echo "${state}"; return 1 ;;
            missing:*)       echo missing;   return 1 ;;
        esac
        sleep 5
    done
    echo timeout
    return 1
}

case "${MODE}" in
check)
    # Must not touch the deployment — inspect only.
    log INFO "Image reference: ${IMAGE_REF}"
    local_digest=$(${DOCKER} image inspect "${IMAGE_REF}" \
        --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' 2>/dev/null || true)
    log INFO "Local:  ${local_digest:-<not present locally>}"

    remote_digest=$(registry_digest "${IMAGE_REF}") || true
    if [[ -z "${remote_digest}" ]]; then
        # Never fall through to a "current" verdict we cannot actually support —
        # a false "nothing to do" is worse than an explicit unknown.
        die 1 "Could not determine the published digest for ${IMAGE_REF}. Cannot tell whether an update exists."
    fi
    log INFO "Remote: ${remote_digest}"

    if [[ -n "${local_digest}" && "${local_digest}" == *"${remote_digest}"* ]]; then
        log INFO "Deployment is current. Nothing to do."
        exit 0
    fi
    log INFO "An update is available. Run without --check to apply it."
    exit 2
    ;;

rollback)
    [[ -f "${STATE_FILE}" ]] || die 1 "No previous image recorded at ${STATE_FILE}."
    previous=$(cat "${STATE_FILE}")
    [[ -n "${previous}" ]] || die 1 "Recorded previous image is empty: ${STATE_FILE}"

    ${DOCKER} image inspect "${previous}" >/dev/null 2>&1 || \
        die 1 "Previous image ${previous} is no longer on this host (pruned?). Cannot roll back."

    log INFO "Rolling back ${IMAGE_REF} to ${previous}."
    ${DOCKER} tag "${previous}" "${IMAGE_REF}"
    compose up -d --force-recreate
    if result=$(wait_for_health); then
        log INFO "Rollback complete and ${SERVICE} is ${result}."
        exit 0
    fi
    die 4 "Rollback did not come up cleanly (${result}). Manual intervention needed."
    ;;
esac

# ---- update ----------------------------------------------------------------

PREVIOUS_ID=$(current_image_id)
if [[ -n "${PREVIOUS_ID}" ]]; then
    log INFO "Current image: ${PREVIOUS_ID}"
else
    log INFO "No local copy of ${IMAGE_REF} yet — this is a first deployment."
fi

log INFO "Pulling ${IMAGE_REF}"
compose pull

NEW_ID=$(current_image_id)
[[ -n "${NEW_ID}" ]] || die 1 "Pull reported success but ${IMAGE_REF} is not present locally."

if [[ "${NEW_ID}" == "${PREVIOUS_ID}" ]]; then
    log INFO "Already running the current image (${NEW_ID}). Nothing to do."
    exit 0
fi
log INFO "New image: ${NEW_ID}"

# Record the outgoing image before recreating, so a rollback target survives even
# if this script dies partway through.
if [[ -n "${PREVIOUS_ID}" ]]; then
    printf '%s\n' "${PREVIOUS_ID}" > "${STATE_FILE}"
    log INFO "Recorded rollback target in ${STATE_FILE}"
fi

log INFO "Recreating ${SERVICE}"
compose up -d --force-recreate

if result=$(wait_for_health); then
    log INFO "${SERVICE} is ${result} on ${NEW_ID}."
    ${DOCKER} ps --filter "name=${SERVICE}" \
        --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
    log INFO "Update complete. Roll back with: ${SCRIPT_NAME} --rollback"
    exit 0
fi

log ERROR "${SERVICE} did not come up cleanly after the update (${result})."
${DOCKER} logs --tail 40 "${SERVICE}" 2>&1 | sed 's/^/    /' || true

if (( ! AUTO_ROLLBACK )); then
    die 1 "Left in place for debugging (--no-auto-rollback). Roll back with: ${SCRIPT_NAME} --rollback"
fi

if [[ -z "${PREVIOUS_ID}" ]]; then
    die 4 "First deployment failed and there is no previous image to roll back to."
fi

log INFO "Auto-rolling back to ${PREVIOUS_ID}."
${DOCKER} tag "${PREVIOUS_ID}" "${IMAGE_REF}"
compose up -d --force-recreate

if result=$(wait_for_health); then
    log INFO "Rolled back successfully; ${SERVICE} is ${result} on the previous image."
    exit 3
fi
die 4 "Update failed AND rollback failed (${result}). ${SERVICE} needs manual attention."
