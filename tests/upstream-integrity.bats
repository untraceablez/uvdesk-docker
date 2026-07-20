#!/usr/bin/env bats
# Repo-invariant + guard tests for FR-018 / Constitution Principle I.

setup() {
  load test_helper
  GUARD="${REPO_ROOT}/scripts/lib/assert-unmodified-upstream.sh"
}

@test "repo invariant: no Dockerfile at repository root" {
  [ ! -e "${REPO_ROOT}/Dockerfile" ]
  run bash -c "compgen -G '${REPO_ROOT}/Dockerfile.*'"
  [ "$status" -ne 0 ]
}

@test "repo invariant: no .docker/ override at repository root" {
  [ ! -d "${REPO_ROOT}/.docker" ]
}

@test "guard passes for a clean extracted upstream context" {
  fake_repo="$(mktemp -d)"
  ctx="$(mktemp -d)"
  touch "${ctx}/Dockerfile"
  run env REPO_ROOT="$fake_repo" "$GUARD" "$ctx"
  rm -rf "$fake_repo" "$ctx"
  [ "$status" -eq 0 ]
}

@test "guard fails when a Dockerfile is present at repo root" {
  fake_repo="$(mktemp -d)"
  ctx="$(mktemp -d)"
  touch "${fake_repo}/Dockerfile" "${ctx}/Dockerfile"
  run env REPO_ROOT="$fake_repo" "$GUARD" "$ctx"
  rm -rf "$fake_repo" "$ctx"
  [ "$status" -ne 0 ]
}

@test "guard fails when the extracted context has no Dockerfile" {
  fake_repo="$(mktemp -d)"
  ctx="$(mktemp -d)"   # no Dockerfile inside
  run env REPO_ROOT="$fake_repo" "$GUARD" "$ctx"
  rm -rf "$fake_repo" "$ctx"
  [ "$status" -ne 0 ]
}
