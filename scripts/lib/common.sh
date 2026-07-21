#!/usr/bin/env bash
# common.sh - shared helpers for the uvdesk-docker automation pipeline.
#
# Source this from other scripts:  . "$(dirname "$0")/lib/common.sh"
# It defines logging, a GitHub API wrapper, semver helpers, tag computation
# (with is_newest gating for `latest`), and registry manifest inspection.
#
# This library only DEFINES functions/vars; callers set `set -euo pipefail`.

# Guard against double-sourcing. (This library is always sourced, never executed.)
if [ -n "${_UVDESK_COMMON_SH_LOADED:-}" ]; then
  return 0
fi
_UVDESK_COMMON_SH_LOADED=1

# --- Configuration (overridable via environment) ---------------------------
UPSTREAM_REPO="${UPSTREAM_REPO:-uvdesk/community-skeleton}"
GITHUB_API="${GITHUB_API:-https://api.github.com}"
IMAGE_NAME="${IMAGE_NAME:-uvdesk}"
DOCKERHUB_NAMESPACE="${DOCKERHUB_NAMESPACE:-}"
GHCR_OWNER="${GHCR_OWNER:-}"

# --- Logging ---------------------------------------------------------------
_ts() { date -u +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo '?'; }
log()  { printf '[%s] %s\n' "$(_ts)" "$*" >&2; }
warn() { printf '[%s] WARN: %s\n' "$(_ts)" "$*" >&2; }
err()  { printf '[%s] ERROR: %s\n' "$(_ts)" "$*" >&2; }
die()  { err "$*"; exit 1; }

require_cmd() {
  local missing=0 c
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      err "required command not found: $c"
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || die "missing prerequisites"
}

# --- GitHub API ------------------------------------------------------------
# gh_api <path>  ->  prints JSON to stdout. Honors GITHUB_TOKEN if set.
gh_api() {
  local path="$1" url auth=()
  url="${GITHUB_API}/${path#/}"
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${auth[@]}" \
    "$url"
}

# --- Semver helpers --------------------------------------------------------
# strip_v vX.Y.Z -> X.Y.Z
strip_v() { printf '%s' "${1#v}"; }

# is_valid_semver X.Y.Z -> exit 0 if valid
is_valid_semver() {
  printf '%s' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
}

# --- Tag computation -------------------------------------------------------
# The image publishes, for a version X.Y.Z:
#   shared (multi-arch):  X.Y.Z         and  latest (ONLY when is_newest)
#   arch-pinned amd64:    X.Y.Z-amd64   and  x64
#   arch-pinned arm64:    X.Y.Z-arm64   and  arm64
#
# Each function prints one tag name per line.

# shared_tags <version> <is_newest:true|false>
shared_tags() {
  local v="$1" is_newest="${2:-false}"
  printf '%s\n' "$v"
  if [ "$is_newest" = "true" ]; then
    printf '%s\n' "latest"
  fi
}

# amd64_tags <version>
amd64_tags() {
  local v="$1"
  printf '%s\n' "${v}-amd64" "x64"
}

# arm64_tags <version>
arm64_tags() {
  local v="$1"
  printf '%s\n' "${v}-arm64" "arm64"
}

# all_tag_names <version> <is_newest> -> every tag name (for tests/inspection)
all_tag_names() {
  local v="$1" is_newest="${2:-false}"
  shared_tags "$v" "$is_newest"
  amd64_tags "$v"
  arm64_tags "$v"
}

# --- Release resolution ----------------------------------------------------
# newest_eligible_version -> prints the newest stable (non-draft,
# non-prerelease) upstream version (X.Y.Z, no leading v). Requires curl+jq.
# Empty output + non-zero exit if none can be resolved.
newest_eligible_version() {
  local json tag
  json="$(gh_api "repos/${UPSTREAM_REPO}/releases?per_page=30")" || return 1
  # GitHub returns releases newest-first; pick the first stable one.
  tag="$(printf '%s' "$json" \
    | jq -r 'map(select(.draft==false and .prerelease==false)) | .[0].tag_name // empty')" || return 1
  [ -n "$tag" ] || return 1
  strip_v "$tag"
}

# is_newest_version <version> -> exit 0 if <version> == newest eligible.
is_newest_version() {
  local v newest
  v="$(strip_v "$1")"
  newest="$(newest_eligible_version)" || return 1
  [ "$v" = "$newest" ]
}

# --- Registry helpers ------------------------------------------------------
# registry_repos -> prints the fully-qualified repo (without tag) for each
# configured target registry, one per line.
registry_repos() {
  [ -n "$DOCKERHUB_NAMESPACE" ] && printf 'docker.io/%s/%s\n' "$DOCKERHUB_NAMESPACE" "$IMAGE_NAME"
  [ -n "$GHCR_OWNER" ]          && printf 'ghcr.io/%s/%s\n'    "$GHCR_OWNER"          "$IMAGE_NAME"
  return 0
}

# manifest_exists <repo> <tag> -> exit 0 if the tag exists in that registry
manifest_exists() {
  local repo="$1" tag="$2"
  docker buildx imagetools inspect "${repo}:${tag}" >/dev/null 2>&1
}

# published_on_all <version> -> exit 0 iff the version tag exists on EVERY
# configured registry (used for idempotency / skip decisions).
published_on_all() {
  local version="$1" repo found_any=0
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    found_any=1
    manifest_exists "$repo" "$version" || return 1
  done < <(registry_repos)
  [ "$found_any" -eq 1 ] || return 1
  return 0
}
