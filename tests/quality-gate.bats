#!/usr/bin/env bats
# Tests for the quality gate (FR-012). Verifies it FAILS CLOSED — i.e. it never
# succeeds silently when SonarQube is not configured — and that it produces the
# ShellCheck external-issues report. The publish-blocking itself is enforced in
# the Jenkinsfile via `waitForQualityGate abortPipeline: true`.

setup() {
  load test_helper
  command -v shellcheck >/dev/null 2>&1 || skip "shellcheck not installed"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  cd "$REPO_ROOT"
  rm -f shellcheck-report.json
}

teardown() {
  rm -f "$REPO_ROOT/shellcheck-report.json"
}

@test "quality-gate.sh fails closed when SonarQube is unconfigured" {
  # Unset Sonar config -> the gate must NOT pass (exit non-zero).
  run env -u SONAR_HOST_URL -u SONAR_TOKEN scripts/quality-gate.sh
  [ "$status" -ne 0 ]
}

@test "quality-gate.sh produces a valid ShellCheck external-issues report" {
  run env -u SONAR_HOST_URL -u SONAR_TOKEN scripts/quality-gate.sh
  [ -f "$REPO_ROOT/shellcheck-report.json" ]
  # Report must be valid JSON with the SonarQube generic-issue shape.
  run jq -e '.issues and .rules' "$REPO_ROOT/shellcheck-report.json"
  [ "$status" -eq 0 ]
}
