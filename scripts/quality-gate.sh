#!/usr/bin/env sh
# quality-gate.sh - run the SonarQube quality analysis over THIS repository's
# own artifacts (FR-012/017; Principle V).
#
# POSIX sh (NOT bash): this runs inside the Alpine sonarsource/sonar-scanner-cli
# container on an in-cluster Jenkins agent, which has no bash. Avoid arrays,
# mapfile, [[ ]], and other bashisms.
#
# Steps:
#   1. If ShellCheck + jq are available, emit a SonarQube generic-issue report
#      from ShellCheck over scripts/** (imported via sonar.externalIssuesReportPaths).
#      The in-cluster scanner image has neither, so an empty (but valid) report is
#      written instead — shell linting is enforced separately by GitHub Actions.
#   2. Run sonar-scanner (scope limited by sonar-project.properties to our own
#      scripts/pipeline — never upstream). PASS/FAIL is enforced by the pipeline's
#      waitForQualityGate after this reports to the server.
#
# Config: SONAR_HOST_URL + SONAR_TOKEN|SONAR_AUTH_TOKEN (injected by withSonarQubeEnv).

set -eu

# Neutralize CDPATH so `cd` never echoes a resolved path into the substitution.
CDPATH=''
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT="${REPO_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}"
REPORT="${REPO_ROOT}/shellcheck-report.json"

log() { printf '[quality-gate] %s\n' "$*" >&2; }
die() { printf '[quality-gate] ERROR: %s\n' "$*" >&2; exit 1; }

# --- 1. ShellCheck -> SonarQube generic issue report (best-effort) ----------
if command -v shellcheck >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  files=$(find "${REPO_ROOT}/scripts" -name '*.sh' -type f 2>/dev/null || true)
  if [ -n "$files" ]; then
    log "running ShellCheck over scripts/**"
    # shellcheck disable=SC2086 # intentional word-splitting; our paths have no spaces
    sc_json=$(shellcheck -x -f json1 $files 2>/dev/null || true)
    printf '%s' "$sc_json" | jq '{
      rules: [ .comments[] | {id: ("SC" + (.code|tostring)), name: ("ShellCheck SC" + (.code|tostring)),
               engineId: "shellcheck", cleanCodeAttribute: "LOGICAL",
               impacts: [ {softwareQuality: "RELIABILITY",
                 severity: (if .level=="error" then "HIGH" elif .level=="warning" then "MEDIUM" else "LOW" end)} ] } ]
             | unique_by(.id),
      issues: [ .comments[] | {
               ruleId: ("SC" + (.code|tostring)),
               primaryLocation: {
                 message: .message,
                 filePath: .file,
                 textRange: {startLine: .line, endLine: (.endLine // .line)}
               } } ]
    }' > "$REPORT"
    log "ShellCheck report: $(jq '.issues|length' "$REPORT") issue(s)"
  else
    printf '%s' '{"rules":[],"issues":[]}' > "$REPORT"
  fi
else
  log "shellcheck/jq unavailable (expected in the scanner container) — writing empty external-issues report; shell lint is gated by GitHub Actions"
  printf '%s' '{"rules":[],"issues":[]}' > "$REPORT"
fi

# --- 2. sonar-scanner -------------------------------------------------------
# withSonarQubeEnv injects SONAR_HOST_URL and SONAR_AUTH_TOKEN; accept either name.
SONAR_TOKEN="${SONAR_TOKEN:-${SONAR_AUTH_TOKEN:-}}"
[ -n "${SONAR_HOST_URL:-}" ] || die "SONAR_HOST_URL not set (run inside withSonarQubeEnv, or export it)"
[ -n "${SONAR_TOKEN}" ]      || die "SONAR token not set (SONAR_TOKEN / SONAR_AUTH_TOKEN)"

log "invoking sonar-scanner against ${SONAR_HOST_URL}"
if command -v sonar-scanner >/dev/null 2>&1; then
  sonar-scanner \
    -Dsonar.host.url="${SONAR_HOST_URL}" \
    -Dsonar.token="${SONAR_TOKEN}"
elif command -v docker >/dev/null 2>&1; then
  log "sonar-scanner binary absent; using container ${SONAR_SCANNER_IMAGE:-sonarsource/sonar-scanner-cli:latest}"
  docker run --rm \
    -e SONAR_HOST_URL="${SONAR_HOST_URL}" \
    -e SONAR_TOKEN="${SONAR_TOKEN}" \
    -v "${REPO_ROOT}:/usr/src" \
    "${SONAR_SCANNER_IMAGE:-sonarsource/sonar-scanner-cli:latest}"
else
  die "no sonar-scanner binary and no docker available"
fi

log "sonar-scanner completed; quality gate result is enforced by waitForQualityGate in the pipeline"
