#!/usr/bin/env bats
# Unit tests for release-resolution logic in scripts/lib/common.sh
# (FR-001/002/010). The GitHub API and registry are stubbed so these run offline.

setup() {
  load test_helper
  load_common
}

# Fixture: releases newest-first, mixing a draft and a prerelease before the
# newest stable release (1.1.8).
_fixture_releases() {
  cat <<'JSON'
[
  {"tag_name":"v1.2.0","draft":true,"prerelease":false},
  {"tag_name":"v1.2.0-rc1","draft":false,"prerelease":true},
  {"tag_name":"v1.1.8","draft":false,"prerelease":false},
  {"tag_name":"v1.1.7","draft":false,"prerelease":false}
]
JSON
}

@test "newest_eligible_version skips draft and prerelease, picks newest stable" {
  gh_api() { _fixture_releases; }
  run newest_eligible_version
  [ "$status" -eq 0 ]
  [ "$output" = "1.1.8" ]
}

@test "is_newest_version true for the newest stable" {
  gh_api() { _fixture_releases; }
  run is_newest_version "1.1.8"
  [ "$status" -eq 0 ]
}

@test "is_newest_version false for an older stable (latest must not advance)" {
  gh_api() { _fixture_releases; }
  run is_newest_version "1.1.7"
  [ "$status" -ne 0 ]
}

@test "newest_eligible_version fails when no stable release exists" {
  gh_api() { echo '[{"tag_name":"v2.0.0-rc1","draft":false,"prerelease":true}]'; }
  run newest_eligible_version
  [ "$status" -ne 0 ]
}

@test "published_on_all: skip only when present on BOTH registries" {
  export DOCKERHUB_NAMESPACE="acme"
  export GHCR_OWNER="acme"
  # Present on docker.io but NOT ghcr.io -> not fully published -> build.
  manifest_exists() { case "$1" in docker.io/*) return 0;; *) return 1;; esac; }
  run published_on_all "1.1.8"
  [ "$status" -ne 0 ]
}

@test "published_on_all: succeeds when present on both registries" {
  export DOCKERHUB_NAMESPACE="acme"
  export GHCR_OWNER="acme"
  manifest_exists() { return 0; }
  run published_on_all "1.1.8"
  [ "$status" -eq 0 ]
}
