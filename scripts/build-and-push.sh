#!/usr/bin/env bash
# build-and-push.sh - atomic multi-arch build + publish (FR-003/004/005/006/
# 007/013/015/016; Constitution Principles I, II, III).
#
# Behavior:
#   * Runs the upstream-integrity guard before building (Principle I).
#   * Builds ALL platforms in a SINGLE `docker buildx build --platform ... --push`
#     invocation, tagging shared multi-arch tags (X.Y.Z, and latest iff newest)
#     on BOTH registries at once. If any architecture fails, or a push to any
#     registry fails, buildx fails the whole invocation and nothing is
#     published (all-or-nothing, Principle II / FR-013).
#   * After the atomic push, derives arch-pinned tags (X.Y.Z-<arch>, plus
#     friendly x64/arm64) on both registries from the pushed per-platform
#     digests (FR-007). These are created only after a fully successful build.
#   * Stamps traceability labels linking each image to its upstream release
#     (FR-015 / Principle III).
#
# Inputs (env or $WORK_DIR/build.env from fetch-source.sh):
#   VERSION, CONTEXT_DIR, IS_NEWEST
# Config: DOCKERHUB_NAMESPACE, GHCR_OWNER, IMAGE_NAME, PLATFORMS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

require_cmd docker jq

WORK_DIR="${WORK_DIR:-.work}"
# Load persisted build context if present.
if [ -f "${WORK_DIR}/build.env" ]; then
  # shellcheck disable=SC1091
  . "${WORK_DIR}/build.env"
fi

VERSION="$(strip_v "${VERSION:-}")"
CONTEXT_DIR="${CONTEXT_DIR:-}"
IS_NEWEST="${IS_NEWEST:-false}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

[ -n "$VERSION" ] || die "VERSION not set (run fetch-source.sh first or export it)"
is_valid_semver "$VERSION" || die "invalid version: $VERSION"
[ -n "$CONTEXT_DIR" ] || die "CONTEXT_DIR not set"

# At least one registry must be configured.
mapfile -t REPOS < <(registry_repos)
[ "${#REPOS[@]}" -gt 0 ] || die "no registries configured (set DOCKERHUB_NAMESPACE and/or GHCR_OWNER)"

# --- Principle I guard: refuse to build anything but unmodified upstream -----
"${SCRIPT_DIR}/lib/assert-unmodified-upstream.sh" "$CONTEXT_DIR"

# --- Traceability labels (FR-015) ------------------------------------------
UPSTREAM_COMMIT="$(gh_api "repos/${UPSTREAM_REPO}/git/ref/tags/v${VERSION}" 2>/dev/null \
  | jq -r '.object.sha // empty' 2>/dev/null || true)"
CREATED="$(_ts)"
LABELS=(
  --label "org.opencontainers.image.title=uvdesk"
  --label "org.opencontainers.image.version=${VERSION}"
  --label "org.opencontainers.image.source=https://github.com/${UPSTREAM_REPO}"
  --label "org.opencontainers.image.created=${CREATED}"
  --label "com.uvdesk-docker.upstream-tag=v${VERSION}"
)
[ -n "$UPSTREAM_COMMIT" ] && LABELS+=(--label "org.opencontainers.image.revision=${UPSTREAM_COMMIT}")

# --- Compute shared tag refs (multi-arch: version [+ latest]) ---------------
SHARED_REFS=()
while IFS= read -r tag; do
  for repo in "${REPOS[@]}"; do
    SHARED_REFS+=(--tag "${repo}:${tag}")
  done
done < <(shared_tags "$VERSION" "$IS_NEWEST")

log "building ${PLATFORMS} for version=${VERSION} is_newest=${IS_NEWEST}"
log "target registries: ${REPOS[*]}"

# --- Atomic build + push (all-or-nothing) -----------------------------------
# A single invocation across all platforms and all registry refs. buildx fails
# the whole build if any platform build OR any registry push fails, so nothing
# is published on a partial failure (FR-013 / Principle II).
docker buildx build \
  --platform "$PLATFORMS" \
  "${LABELS[@]}" \
  "${SHARED_REFS[@]}" \
  --provenance=false \
  --push \
  "$CONTEXT_DIR"

log "shared multi-arch tags pushed for ${VERSION}"

# --- Derive arch-pinned tags from the pushed manifest (FR-007) --------------
# platform -> "arch friendly"
arch_for()     { case "$1" in linux/amd64) echo amd64;; linux/arm64) echo arm64;; *) echo "${1##*/}";; esac; }
friendly_for() { case "$1" in linux/amd64) echo x64;;   linux/arm64) echo arm64;; *) echo "${1##*/}";; esac; }

IFS=',' read -ra PLAT_LIST <<< "$PLATFORMS"
for repo in "${REPOS[@]}"; do
  raw="$(docker buildx imagetools inspect "${repo}:${VERSION}" --raw)"
  for plat in "${PLAT_LIST[@]}"; do
    os="${plat%%/*}"; cpu="${plat##*/}"
    digest="$(printf '%s' "$raw" \
      | jq -r --arg os "$os" --arg cpu "$cpu" \
        '.manifests[] | select(.platform.os==$os and .platform.architecture==$cpu) | .digest' \
      | head -n1)"
    if [ -z "$digest" ] || [ "$digest" = "null" ]; then
      die "could not find ${plat} digest in ${repo}:${VERSION} manifest"
    fi
    arch="$(arch_for "$plat")"; friendly="$(friendly_for "$plat")"
    log "creating arch-pinned tags ${repo}:${VERSION}-${arch} and ${repo}:${friendly}"
    docker buildx imagetools create \
      --tag "${repo}:${VERSION}-${arch}" \
      --tag "${repo}:${friendly}" \
      "${repo}:${VERSION}@${digest}"
  done
done

log "publish complete for ${VERSION} on all registries (is_newest=${IS_NEWEST})"
