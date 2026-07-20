#!/usr/bin/env bash
# Shared bats helper: locate repo root and source the library under test.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

load_common() {
  # shellcheck source=scripts/lib/common.sh
  . "${REPO_ROOT}/scripts/lib/common.sh"
}
