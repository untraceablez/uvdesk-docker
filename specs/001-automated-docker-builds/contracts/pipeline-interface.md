# Contract: Pipeline Interface

**Feature**: 001-automated-docker-builds | **Date**: 2026-07-20

Defines the interface of the Jenkins automation: its triggers, parameters, stage contract, quality-gate contract, and notification contract. This is what a maintainer interacts with.

## Triggers

| Trigger | Mechanism | Behavior |
|---|---|---|
| Scheduled poll | Jenkins cron trigger (default hourly) | Resolves newest eligible upstream release; builds if not already published (FR-009) |
| Manual | "Build with Parameters" | Uses supplied parameters; can force a rebuild (FR-011) |

## Parameters (manual runs)

| Parameter | Type | Default | Effect |
|---|---|---|---|
| `VERSION` | string | empty | If set (e.g. `1.1.8`), targets that exact upstream version instead of auto-resolving |
| `FORCE_REBUILD` | boolean | `false` | If true, rebuild + republish even if the version already exists on both registries (FR-010/011) |

## Configuration values (Jenkins env / credentials, not per-run params)

| Key | Kind | Purpose |
|---|---|---|
| `DOCKERHUB_NAMESPACE`, `GHCR_OWNER` | env | Target image namespaces |
| `DOCKERHUB_CREDENTIALS` | credential | Docker Hub push token |
| `GHCR_CREDENTIALS` | credential | GHCR push token (PAT / `GITHUB_TOKEN`) |
| `SONAR_HOST_URL`, `SONAR_TOKEN` | env + credential | SonarQube server + auth |
| `POLL_SCHEDULE` | env | Cron expression for the poll trigger |
| `NOTIFY_EMAIL` | env | Maintainer notification recipient (FR-014) |
| `NOTIFY_WEBHOOK_URL` | env (optional) | Optional chat webhook |

## Stage contract (ordered)

| # | Stage | Input | Success condition | On failure |
|---|---|---|---|---|
| 1 | Resolve release | GitHub Releases API | Newest eligible version determined; `action=build\|skip` computed | notify → fail (FR-009 edge: source unreachable) |
| 2 | Quality gate | this repo's artifacts | `sonar-scanner` run + `waitForQualityGate` == OK | notify → fail, **no build** (FR-012) |
| 3 | Fetch source | `tarball_url` | Archive extracted; root `Dockerfile` present | notify → fail |
| 4 | Build (both arches) | upstream Dockerfile | Single `buildx --platform linux/amd64,linux/arm64` succeeds for BOTH | notify → fail, **no tags pushed** (FR-013) |
| 5 | Publish | built images | Version + `latest` multi-arch manifests pushed to **both** registries; arch-pinned tags derived | notify → fail (partial push ⇒ run fails) |
| 6 | Notify (always-on-failure) | run status | Maintainer notified within the run on any failure (SC-007) | — |

**Skip path**: if stage 1 yields `action=skip`, the run ends `outcome=skipped` with no build, no publish, no failure notification (FR-010).

## Quality-gate contract (FR-012/017)

- **Scope**: `sonar-project.properties` restricts analysis to this repo's authored artifacts (`scripts/**`, `Jenkinsfile`, config, docs). Upstream source is never on the scanner path (FR-017).
- **Shell coverage**: ShellCheck runs over `scripts/**`; results are imported via `sonar.externalIssuesReportPaths` (generic issue format). SonarQube Secrets + IaC analyzers are enabled.
- **Enforcement**: the pipeline calls `waitForQualityGate`; a non-`OK` status aborts the run before any build/publish. There is no override that lets a failed gate publish.

## Publishing contract (FR-013/016)

- Atomicity: a **single** `buildx build --platform linux/amd64,linux/arm64` — if either arch fails, nothing is pushed.
- Lockstep: identical tag sets pushed to Docker Hub and GHCR; failure to either registry fails the run.
- Idempotency: before building, `imagetools inspect` checks both registries for the target version; present-on-both ⇒ skip unless `FORCE_REBUILD` (FR-010/011).
- Non-destructive: older version tags are never deleted (spec: non-destructive to history).

## Notification contract (FR-014)

- Any stage failure sends an email to `NOTIFY_EMAIL` (and optional `NOTIFY_WEBHOOK_URL`) identifying the target version, the failed stage, and a link to the run — within the same pipeline run (SC-007).
- Successful `published` and benign `skipped` runs do not notify by default (configurable).
