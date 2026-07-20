# Quickstart & Validation Guide

**Feature**: 001-automated-docker-builds | **Date**: 2026-07-20

How to validate that the automation works end-to-end. Each scenario maps to spec Success Criteria. See [contracts/pipeline-interface.md](./contracts/pipeline-interface.md) and [contracts/image-interface.md](./contracts/image-interface.md) for the interfaces referenced here; this guide does not restate them.

## Prerequisites

- Jenkins with the Docker Pipeline + Docker Buildx available on a Linux x86-64 agent, with QEMU/binfmt registered (`docker run --privileged --rm tonistiigi/binfmt --install all`).
- SonarQube server reachable, with a webhook back to Jenkins configured for `waitForQualityGate`.
- Jenkins credentials/config set per the pipeline-interface contract (Docker Hub token, GHCR token, Sonar token, namespaces, notify email).
- `docker`, `jq`, `curl`, `shellcheck`, `sonar-scanner` on the agent.

## One-time setup

1. Create the Jenkins Pipeline job pointing at this repo's `Jenkinsfile`.
2. Populate the configuration values from the pipeline-interface contract.
3. Set `POLL_SCHEDULE` (default hourly) and save.

---

## Scenario A — Build & publish the current release (SC-001, SC-006)

**Goal**: prove a manual run produces working multi-arch images on both registries.

1. Run the job with `VERSION` empty, `FORCE_REBUILD=false` (or set `VERSION=1.1.8` to pin).
2. Expect: quality gate passes → both arches build → tags pushed to Docker Hub **and** GHCR.

**Verify** (replace namespace/owner):

```sh
# Shared multi-arch tags exist on both registries and list both platforms
docker buildx imagetools inspect docker.io/<ns>/uvdesk:1.1.8 | grep -E 'linux/amd64|linux/arm64'
docker buildx imagetools inspect ghcr.io/<owner>/uvdesk:latest | grep -E 'linux/amd64|linux/arm64'

# Arch-pinned tags resolve to a single platform each
docker buildx imagetools inspect docker.io/<ns>/uvdesk:x64   | grep 'linux/amd64'
docker buildx imagetools inspect docker.io/<ns>/uvdesk:arm64 | grep 'linux/arm64'

# Traceability: image records its upstream version (FR-015)
docker buildx imagetools inspect --raw docker.io/<ns>/uvdesk:1.1.8 | jq '.. | .annotations? // empty'
```

**Boot test on each arch** (arm64 via emulation on the x64 agent):

```sh
for arch in amd64 arm64; do
  docker run -d --platform linux/$arch --name uvdesk-$arch \
    -e MYSQL_ROOT_PASSWORD=rootpw -e MYSQL_DATABASE=uvdesk \
    -e MYSQL_USER=uvdesk -e MYSQL_PASSWORD=uvdeskpw \
    -p 0:80 docker.io/<ns>/uvdesk:1.1.8
done
# Expected: each container reaches the UVdesk web installer/login (HTTP 200) — see tests/smoke/run-image.sh
```

Pass criteria: both containers serve the web installer (FR-008, FR-019).

---

## Scenario B — Automatic detection of a new release (SC-002)

**Goal**: prove hands-off pickup (FR-009, FR-020).

- With no matching image published, let the scheduled poll fire (or trigger the poll manually with `VERSION` empty).
- Expect: the pipeline resolves the newest eligible release and publishes it with **no manual steps**.
- Negative check: run the poll again immediately → run ends `skipped` (idempotent, FR-010), no duplicate push.

To rehearse without waiting for a real upstream release, target a version you have **not** yet built with `VERSION=<older-tag>` and confirm build+publish, then re-run to confirm skip.

---

## Scenario C — All-or-nothing on a failed arch (SC-003)

**Goal**: prove a partial build publishes nothing (FR-013).

- Simulate an arm64 failure (e.g., temporarily point the builder at an unsupported base, or inject a failing build step in a scratch branch).
- Expect: the `buildx` invocation fails; **no** tags (shared or arch-pinned) appear on either registry for that version.

**Verify** the version tag is absent on both:

```sh
docker buildx imagetools inspect docker.io/<ns>/uvdesk:<ver>  # expect: not found
docker buildx imagetools inspect ghcr.io/<owner>/uvdesk:<ver> # expect: not found
```

---

## Scenario D — Quality gate blocks publish (SC-004)

**Goal**: prove the SonarQube gate stops publishing (FR-012).

- On a scratch branch, introduce a change that fails the gate (e.g., a ShellCheck error in `scripts/` or a committed secret).
- Run the job. Expect: stage 2 fails on `waitForQualityGate`, **no build/publish occurs**, and a maintainer notification is sent.
- Revert and re-run → publishing resumes.

---

## Scenario E — Failure notifications (SC-007)

**Goal**: prove maintainer visibility (FR-014).

- Trigger any failure (unreachable GitHub API in stage 1, bad registry credential in stage 5, or the gate failure from Scenario D).
- Expect: an email (and optional webhook) naming the target version, failed stage, and run link arrives within the same run.

---

## Automation self-tests

Run the repo's own tests before relying on the pipeline:

```sh
shellcheck scripts/**/*.sh
bats tests/            # release-selection + tag-scheme unit tests
```

Pass criteria: ShellCheck clean; `check-release` correctly picks the newest non-draft/non-prerelease version and returns `skip` when both registries already have it; tag-scheme computes the six expected tags for a given version.
