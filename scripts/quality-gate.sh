#!/usr/bin/env bash
# quality-gate.sh - run the SonarQube quality analysis over THIS repository's
# own artifacts (FR-012/017; Principle V).
#
# Steps:
#   1. Run ShellCheck over scripts/** producing a SonarQube "generic issue"
#      JSON report (imported via sonar.externalIssuesReportPaths in
#      sonar-project.properties), since SonarQube has limited native shell
#      support.
#   2. Invoke sonar-scanner over the repo (scope limited by
#      sonar-project.properties to our scripts/pipeline — never upstream).
#
# The actual PASS/FAIL enforcement happens in the Jenkinsfile via
# `waitForQualityGate` after this scanner run reports to the server. This
# script fails (non-zero) only if the scanner itself cannot run.
#
# Config: SONAR_HOST_URL, SONAR_TOKEN

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
REPORT="${REPO_ROOT}/shellcheck-report.json"

require_cmd shellcheck jq

# --- 1. ShellCheck -> SonarQube generic issue format ------------------------
mapfile -t SH_FILES < <(find "${REPO_ROOT}/scripts" -name '*.sh' -type f)
if [ "${#SH_FILES[@]}" -eq 0 ]; then
  warn "no shell scripts found under scripts/"
  printf '{"rules":[],"issues":[]}\n' > "$REPORT"
else
  log "running ShellCheck over ${#SH_FILES[@]} script(s)"
  # ShellCheck JSON1 -> SonarQube generic external issues.
  # Severity map: error->BLOCKER, warning->MAJOR, info/style->MINOR.
  sc_json="$(shellcheck -x -f json1 "${SH_FILES[@]}" || true)"
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
             }
           } ]
  }' > "$REPORT"
  log "ShellCheck report written to ${REPORT} ($(jq '.issues|length' "$REPORT") issue(s))"
fi

# --- 2. sonar-scanner -------------------------------------------------------
if ! command -v sonar-scanner >/dev/null 2>&1; then
  die "sonar-scanner not installed on the agent"
fi
[ -n "${SONAR_HOST_URL:-}" ] || die "SONAR_HOST_URL not set"
[ -n "${SONAR_TOKEN:-}" ]    || die "SONAR_TOKEN not set"

log "invoking sonar-scanner against ${SONAR_HOST_URL}"
sonar-scanner \
  -Dsonar.host.url="${SONAR_HOST_URL}" \
  -Dsonar.token="${SONAR_TOKEN}"

log "sonar-scanner completed; quality gate result is enforced by waitForQualityGate in the pipeline"
