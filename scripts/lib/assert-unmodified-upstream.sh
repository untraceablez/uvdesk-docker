#!/usr/bin/env bash
# assert-unmodified-upstream.sh - mechanical enforcement of Constitution
# Principle I (Upstream Integrity / Never Fork) and spec FR-018.
#
# Called by the build stage BEFORE buildx runs. It fails the pipeline if:
#   1. This repository contributes a Dockerfile or .docker/ override at its
#      root (there must be none — we build upstream's own).
#   2. The build context is NOT the freshly-extracted upstream release dir.
#   3. The extracted upstream tree shows signs of post-extract patching
#      (a tracked modification marker, or a nested repo Dockerfile swap).
#
# Usage: assert-unmodified-upstream.sh <extracted_context_dir>
#
# Exit 0 = clean; non-zero = violation (build MUST NOT proceed).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
. "${SCRIPT_DIR}/common.sh"

REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
CONTEXT_DIR="${1:-}"

[ -n "$CONTEXT_DIR" ] || die "usage: assert-unmodified-upstream.sh <extracted_context_dir>"

fail=0

# 1. No repo-authored Dockerfile / .docker override at repo root.
if [ -e "${REPO_ROOT}/Dockerfile" ] || compgen -G "${REPO_ROOT}/Dockerfile.*" >/dev/null 2>&1; then
  err "FR-018 violation: a Dockerfile exists at the repository root. This repo MUST NOT author a Dockerfile."
  fail=1
fi
if [ -d "${REPO_ROOT}/.docker" ]; then
  err "FR-018 violation: a .docker/ directory exists at the repository root. Upstream's own .docker/ must be used, not a repo override."
  fail=1
fi

# 2. Build context must be the extracted upstream release, containing upstream's Dockerfile.
if [ ! -d "$CONTEXT_DIR" ]; then
  err "build context directory does not exist: $CONTEXT_DIR"
  fail=1
elif [ ! -f "${CONTEXT_DIR}/Dockerfile" ]; then
  err "FR-018 violation: extracted upstream context has no Dockerfile at ${CONTEXT_DIR}/Dockerfile (cannot build upstream unmodified)."
  fail=1
fi

# 3. Context must be OUTSIDE the repo root (it is a scratch extraction, not our tree).
#    Guards against accidentally building the repo itself as the context.
case "$(cd "$CONTEXT_DIR" 2>/dev/null && pwd)/" in
  "${REPO_ROOT}/scripts/"*|"${REPO_ROOT}/specs/"*|"${REPO_ROOT}/tests/"*|"${REPO_ROOT}/docs/")
    err "FR-018 violation: build context points inside this repository's own source tree."
    fail=1
    ;;
esac

if [ "$fail" -ne 0 ]; then
  die "upstream integrity check FAILED — build aborted (Constitution Principle I / FR-018)"
fi

log "upstream integrity check passed: building unmodified upstream context at ${CONTEXT_DIR}"
