#!/usr/bin/env bash
# fetch-source.sh - download and extract an upstream UVdesk release (FR-018).
#
# Downloads the release source tarball for a given VERSION, extracts it, and
# asserts the upstream Dockerfile is present. Also computes a self-contained
# `is_newest` value so US1 does not depend on check-release.sh (X1 remediation):
#   - honors an explicit IS_NEWEST env override (true/false), else
#   - compares VERSION against the newest eligible upstream release.
#
# Usage:  fetch-source.sh [VERSION]
#   VERSION may also come from $VERSION. Format: X.Y.Z or vX.Y.Z.
#
# Writes $WORK_DIR/build.env (CONTEXT_DIR, VERSION, IS_NEWEST) for later stages
# and prints CONTEXT_DIR to stdout. Builds nothing itself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

require_cmd curl jq tar

WORK_DIR="${WORK_DIR:-.work}"
RAW_VERSION="${1:-${VERSION:-}}"
[ -n "$RAW_VERSION" ] || die "no VERSION supplied (arg or \$VERSION)"

VERSION="$(strip_v "$RAW_VERSION")"
is_valid_semver "$VERSION" || die "not a valid semver version: '$VERSION'"

TAG="v${VERSION}"
SRC_DIR="${WORK_DIR}/src"
TARBALL="${WORK_DIR}/${VERSION}.tar.gz"

log "fetching upstream ${UPSTREAM_REPO}@${TAG}"
rm -rf "$SRC_DIR" "$TARBALL"
mkdir -p "$SRC_DIR"

# Resolve the tarball URL from the release (fail cleanly if missing/malformed).
TARBALL_URL="$(gh_api "repos/${UPSTREAM_REPO}/releases/tags/${TAG}" \
  | jq -r '.tarball_url // empty')" \
  || die "could not query release ${TAG} (upstream source unreachable)"
[ -n "$TARBALL_URL" ] || die "release ${TAG} has no tarball_url (malformed/unavailable release)"

curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
  -o "$TARBALL" "$TARBALL_URL" \
  || die "failed to download source archive for ${TAG}"

# GitHub tarballs wrap contents in a single top-level dir; strip it.
tar -xzf "$TARBALL" -C "$SRC_DIR" --strip-components=1 \
  || die "failed to extract source archive for ${TAG} (malformed archive)"

CONTEXT_DIR="$(cd "$SRC_DIR" && pwd)"

# FR-018: the upstream release must ship its own Dockerfile.
[ -f "${CONTEXT_DIR}/Dockerfile" ] \
  || die "extracted upstream ${TAG} has no root Dockerfile — cannot build unmodified upstream"

# --- Compute is_newest (self-contained fallback) ---
if [ -n "${IS_NEWEST:-}" ]; then
  IS_NEWEST="${IS_NEWEST}"
  log "is_newest overridden via env: ${IS_NEWEST}"
elif newest="$(newest_eligible_version 2>/dev/null)" && [ -n "$newest" ]; then
  if [ "$VERSION" = "$newest" ]; then IS_NEWEST=true; else IS_NEWEST=false; fi
  log "is_newest computed: ${IS_NEWEST} (newest eligible=${newest})"
else
  IS_NEWEST=false
  warn "could not resolve newest eligible release; defaulting is_newest=false (latest will NOT advance)"
fi

# Persist for downstream stages.
mkdir -p "$WORK_DIR"
cat > "${WORK_DIR}/build.env" <<EOF
VERSION=${VERSION}
CONTEXT_DIR=${CONTEXT_DIR}
IS_NEWEST=${IS_NEWEST}
EOF

log "extracted upstream ${TAG} to ${CONTEXT_DIR} (is_newest=${IS_NEWEST})"
printf '%s\n' "$CONTEXT_DIR"
