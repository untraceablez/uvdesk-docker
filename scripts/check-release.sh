#!/usr/bin/env bash
# check-release.sh - resolve the target upstream version and decide build/skip
# (FR-001/002/009/010/011; Principle III/IV).
#
# Resolution:
#   * If VERSION is supplied (manual override), target that exact version.
#   * Otherwise select the newest eligible (non-draft, non-prerelease) release.
# Decision:
#   * action=skip  when the target is already published on ALL registries and
#     FORCE_REBUILD is not true (idempotency, FR-010).
#   * action=build otherwise.
#   * is_newest = (target == newest eligible release) — gates `latest` (FR-006).
#
# Fails cleanly (non-zero) if upstream cannot be reached/read (FR-009 edge);
# the caller is responsible for notifying.
#
# Writes $WORK_DIR/decision.env and prints "action=<build|skip> version=<v> is_newest=<b>".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

require_cmd curl jq docker

WORK_DIR="${WORK_DIR:-.work}"
REQUESTED_VERSION="${VERSION:-}"
FORCE_REBUILD="${FORCE_REBUILD:-false}"

# Resolve the newest eligible release (also used for is_newest).
if ! NEWEST="$(newest_eligible_version)" || [ -z "$NEWEST" ]; then
  die "could not resolve newest eligible upstream release (upstream unreachable or no stable release)"
fi

if [ -n "$REQUESTED_VERSION" ]; then
  TARGET="$(strip_v "$REQUESTED_VERSION")"
  is_valid_semver "$TARGET" || die "requested VERSION is not valid semver: $REQUESTED_VERSION"
  log "manual target requested: ${TARGET} (newest eligible=${NEWEST})"
else
  TARGET="$NEWEST"
  log "auto-selected newest eligible release: ${TARGET}"
fi

if [ "$TARGET" = "$NEWEST" ]; then IS_NEWEST=true; else IS_NEWEST=false; fi

# Idempotency: skip if already published on all registries, unless forced.
ACTION="build"
if [ "$FORCE_REBUILD" = "true" ]; then
  log "FORCE_REBUILD=true — will build even if already published"
elif published_on_all "$TARGET"; then
  ACTION="skip"
  log "version ${TARGET} already published on all registries — skipping (FR-010)"
else
  log "version ${TARGET} not published on all registries — will build"
fi

mkdir -p "$WORK_DIR"
cat > "${WORK_DIR}/decision.env" <<EOF
ACTION=${ACTION}
VERSION=${TARGET}
IS_NEWEST=${IS_NEWEST}
FORCE_REBUILD=${FORCE_REBUILD}
EOF

printf 'action=%s version=%s is_newest=%s\n' "$ACTION" "$TARGET" "$IS_NEWEST"
