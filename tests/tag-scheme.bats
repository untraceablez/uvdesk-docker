#!/usr/bin/env bats
# Unit tests for tag computation in scripts/lib/common.sh (FR-005/006/007).

setup() {
  load test_helper
  load_common
}

@test "shared_tags: newest release includes latest" {
  run shared_tags "1.1.8" "true"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "1.1.8" ]
  [ "${lines[1]}" = "latest" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "shared_tags: non-newest release omits latest (FR-006 gating)" {
  run shared_tags "1.1.7" "false"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "1.1.7" ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "amd64_tags: version-amd64 and x64" {
  run amd64_tags "1.1.8"
  [ "${lines[0]}" = "1.1.8-amd64" ]
  [ "${lines[1]}" = "x64" ]
}

@test "arm64_tags: version-arm64 and arm64" {
  run arm64_tags "1.1.8"
  [ "${lines[0]}" = "1.1.8-arm64" ]
  [ "${lines[1]}" = "arm64" ]
}

@test "all_tag_names: newest yields all six tags" {
  run all_tag_names "1.1.8" "true"
  [ "${#lines[@]}" -eq 6 ]
  printf '%s\n' "${lines[@]}" | grep -qx "1.1.8"
  printf '%s\n' "${lines[@]}" | grep -qx "latest"
  printf '%s\n' "${lines[@]}" | grep -qx "1.1.8-amd64"
  printf '%s\n' "${lines[@]}" | grep -qx "x64"
  printf '%s\n' "${lines[@]}" | grep -qx "1.1.8-arm64"
  printf '%s\n' "${lines[@]}" | grep -qx "arm64"
}

@test "all_tag_names: non-newest yields five tags (no latest)" {
  run all_tag_names "1.1.7" "false"
  [ "${#lines[@]}" -eq 5 ]
  ! printf '%s\n' "${lines[@]}" | grep -qx "latest"
}
