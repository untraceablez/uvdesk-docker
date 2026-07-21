#!/usr/bin/env bash
# run-image.sh - smoke test a built UVdesk image on each required architecture
# (FR-008 + FR-019).
#
# For each platform it: boots the image with MYSQL_* env, waits for startup,
# then asserts BOTH
#   (a) the web installer responds HTTP 200, AND
#   (b) the upstream entrypoint actually provisioned the DB — MYSQL_DATABASE
#       exists and MYSQL_USER can authenticate.
# Fails if either assertion fails (guards FR-019 against upstream entrypoint drift).
#
# Usage:
#   IMAGE_REF=docker.io/ns/uvdesk:1.1.8 PLATFORMS="linux/amd64 linux/arm64" tests/smoke/run-image.sh

set -euo pipefail

IMAGE_REF="${IMAGE_REF:?set IMAGE_REF to the image to test}"
PLATFORMS="${PLATFORMS:-linux/amd64 linux/arm64}"
WAIT_SECONDS="${WAIT_SECONDS:-120}"

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpw}"
MYSQL_DATABASE="${MYSQL_DATABASE:-uvdesk}"
MYSQL_USER="${MYSQL_USER:-uvdesk}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-uvdeskpw}"

log()  { printf '[smoke] %s\n' "$*" >&2; }
fail() { printf '[smoke] FAIL: %s\n' "$*" >&2; exit 1; }

test_platform() {
  local platform="$1" cname port rc=0
  cname="uvdesk-smoke-${platform##*/}-$$"
  log "starting ${IMAGE_REF} on ${platform} as ${cname}"

  docker run -d --name "$cname" --platform "$platform" \
    -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
    -e MYSQL_DATABASE="$MYSQL_DATABASE" \
    -e MYSQL_USER="$MYSQL_USER" \
    -e MYSQL_PASSWORD="$MYSQL_PASSWORD" \
    -P "$IMAGE_REF" >/dev/null

  # Resolve the mapped host port for container :80.
  port="$(docker port "$cname" 80/tcp | head -n1 | sed 's/.*://')"
  [ -n "$port" ] || { docker rm -f "$cname" >/dev/null 2>&1 || true; fail "no host port mapped for :80 (${platform})"; }

  # (a) Wait for the web installer to respond 200.
  local i=0 ok=0
  while [ "$i" -lt "$WAIT_SECONDS" ]; do
    if curl -fsS -o /dev/null "http://127.0.0.1:${port}/"; then ok=1; break; fi
    sleep 2; i=$((i+2))
  done
  [ "$ok" -eq 1 ] || rc=1
  [ "$ok" -eq 1 ] && log "web installer reachable on ${platform} (port ${port})"

  # (b) Assert env-driven DB provisioning happened (FR-019).
  if [ "$rc" -eq 0 ]; then
    if docker exec "$cname" sh -c \
      "mysql -u\"$MYSQL_USER\" -p\"$MYSQL_PASSWORD\" -e 'SHOW DATABASES;' 2>/dev/null | grep -qx \"$MYSQL_DATABASE\""; then
      log "DB auto-provisioning verified on ${platform} (db=${MYSQL_DATABASE}, user=${MYSQL_USER})"
    else
      rc=1
      log "DB auto-provisioning NOT verified on ${platform}"
    fi
  fi

  docker logs "$cname" > "uvdesk-smoke-${platform##*/}.log" 2>&1 || true
  docker rm -f "$cname" >/dev/null 2>&1 || true

  [ "$rc" -eq 0 ] || fail "smoke test failed on ${platform}"
  log "PASS ${platform}"
}

read -ra _platforms <<< "$PLATFORMS"
for p in "${_platforms[@]}"; do
  test_platform "$p"
done

log "all platforms passed: ${PLATFORMS}"
