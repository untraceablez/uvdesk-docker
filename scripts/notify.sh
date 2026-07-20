#!/usr/bin/env bash
# notify.sh - send a maintainer failure notification (FR-014).
#
# Usage: notify.sh <version> <failed_stage> <run_url> [message]
#
# Sends email to $NOTIFY_EMAIL (via `mail`/`sendmail` if available) and, if
# $NOTIFY_WEBHOOK_URL is set, posts a JSON payload to that webhook.
# Notification failures are logged but never abort the caller (the run has
# already failed; we must not mask the original error).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

VERSION="${1:-unknown}"
STAGE="${2:-unknown}"
RUN_URL="${3:-${BUILD_URL:-n/a}}"
MESSAGE="${4:-Pipeline failure}"

SUBJECT="[uvdesk-docker] build FAILED — version=${VERSION} stage=${STAGE}"
BODY="$(cat <<EOF
uvdesk-docker pipeline failure

Version : ${VERSION}
Stage   : ${STAGE}
Run     : ${RUN_URL}
Detail  : ${MESSAGE}
Time    : $(_ts)
EOF
)"

sent=0

# --- Email ---
if [ -n "${NOTIFY_EMAIL:-}" ]; then
  if command -v mail >/dev/null 2>&1; then
    if printf '%s\n' "$BODY" | mail -s "$SUBJECT" "$NOTIFY_EMAIL"; then
      log "notification emailed to ${NOTIFY_EMAIL}"
      sent=1
    else
      warn "failed to send email via 'mail' to ${NOTIFY_EMAIL}"
    fi
  elif command -v sendmail >/dev/null 2>&1; then
    if printf 'Subject: %s\nTo: %s\n\n%s\n' "$SUBJECT" "$NOTIFY_EMAIL" "$BODY" | sendmail -t; then
      log "notification emailed to ${NOTIFY_EMAIL} via sendmail"
      sent=1
    else
      warn "failed to send email via 'sendmail' to ${NOTIFY_EMAIL}"
    fi
  else
    warn "NOTIFY_EMAIL set but neither 'mail' nor 'sendmail' available; relying on Jenkins mailer"
  fi
fi

# --- Webhook (optional) ---
if [ -n "${NOTIFY_WEBHOOK_URL:-}" ]; then
  payload=$(printf '{"text":"%s","version":"%s","stage":"%s","run":"%s"}' \
    "$(printf '%s' "$SUBJECT" | sed 's/"/\\"/g')" "$VERSION" "$STAGE" "$RUN_URL")
  if curl -fsS -X POST -H 'Content-Type: application/json' -d "$payload" "$NOTIFY_WEBHOOK_URL" >/dev/null 2>&1; then
    log "notification posted to webhook"
    sent=1
  else
    warn "failed to post notification to webhook"
  fi
fi

if [ "$sent" -eq 0 ]; then
  warn "no notification channel delivered (NOTIFY_EMAIL / NOTIFY_WEBHOOK_URL unset or unavailable)"
fi

# Always succeed — notification must not mask the original failure.
exit 0
