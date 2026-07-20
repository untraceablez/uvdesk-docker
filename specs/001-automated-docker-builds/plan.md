# Implementation Plan: Automated Multi-Arch UVdesk Docker Builds

**Branch**: `001-automated-docker-builds` | **Date**: 2026-07-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-automated-docker-builds/spec.md`

## Summary

Automate the production of multi-architecture (linux/amd64 + linux/arm64) Docker images of `uvdesk/community-skeleton`, driven by a Jenkins pipeline with a SonarQube quality gate. The pipeline monitors upstream GitHub releases, and for each new eligible (stable, non-draft, non-prerelease) release it builds the **unmodified upstream release** — which already ships its own multi-arch-clean `Dockerfile` and an env-driven entrypoint — using Docker Buildx, then publishes to both Docker Hub and GHCR with `latest`, exact-version, and architecture-pinned tags. Builds are all-or-nothing across architectures, and the SonarQube gate covers only this repository's own automation artifacts (not upstream source).

**Key technical approach**: This repo is a *packaging/automation layer only*. It contains no Dockerfile and no application code — it drives `docker buildx` against the upstream release's own Dockerfile, so FR-018 (never modify upstream) is satisfied structurally rather than by policy. The upstream entrypoint's existing `MYSQL_*` handling satisfies FR-019 with no additions.

## Technical Context

**Language/Version**: Bash (POSIX-ish, targeting `bash`) for pipeline scripts; Groovy (Declarative) for the Jenkins pipeline; no application code authored here.

**Primary Dependencies**: Jenkins (executor + scheduler/poller), Docker Engine with Buildx plugin + QEMU/binfmt (cross-arch emulation), SonarQube Scanner CLI, `gh`/`curl` + `jq` (GitHub Releases API), ShellCheck (shell linting fed into SonarQube via generic issue import).

**Storage**: None provisioned. "Already-built" state is derived from the container registries themselves (manifest existence check) — the registry is the source of truth; no separate database.

**Testing**: `bats`/shell assertions + ShellCheck for the automation scripts; a smoke test that runs the produced image and asserts it reaches the UVdesk web installer/login on both architectures (arm64 via QEMU on the CI host).

**Target Platform**: CI runs on a Linux x86-64 Jenkins agent; produced images target `linux/amd64` and `linux/arm64`.

**Project Type**: CI/CD automation repository (single project, scripts + pipeline config). No app source, no frontend/backend split.

**Performance Goals**: A full multi-arch build+publish completes within a single scheduled poll interval (SC-002). arm64 built under emulation is the slow path (`composer install`); target end-to-end build under ~45 min on a standard agent (informational, not a hard SLA).

**Constraints**: Never modify upstream source (FR-018); all-or-nothing publishing across both arches (FR-013); identical tag sets on both registries (FR-016); hands-off after quality gate (FR-020); upstream `Dockerfile` uses `FROM ubuntu:latest` (a floating tag) which we accept unmodified — see research.md reproducibility caveat.

**Scale/Scope**: Low volume — one build per new upstream release (upstream cadence is roughly a handful of releases per year). Two architectures, two registries, ~4 tag families per release.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against the ratified constitution v1.0.0 (`.specify/memory/constitution.md`, Principles I–V).

| Principle | Verdict | How this design satisfies it |
|---|---|---|
| **I. Upstream Integrity (Never Fork)** | ✅ PASS | No repo Dockerfile; build runs against the upstream release's own Dockerfile (research D1). Mechanical guard `scripts/lib/assert-unmodified-upstream.sh` (T008) fails the pipeline on any repo Dockerfile/override or post-extract patch. Defective upstream ⇒ skip/report (FR-018). |
| **II. Atomic, All-or-Nothing Publishing** | ✅ PASS | Single `buildx --platform amd64,arm64` invocation (T015); dual-registry lockstep with fail-on-either-push (T017); nothing published on partial build (FR-013/016, research D3/D4). |
| **III. Traceability & Idempotency** | ✅ PASS | Version/commit/timestamp labels (T011); `latest` gated to newest via `is_newest` (T004/T010/T022); registry-as-state skip of already-published versions (T021); historical tags never deleted (FR-006/010/015). |
| **IV. Automation-First, Hands-Off Operation** | ✅ PASS | Cron poll detection (T023); no manual step after gate (FR-020); `disableConcurrentBuilds()` single-flight (T006); in-run failure notifications (T005/notify, FR-014). |
| **V. Quality-Gated Delivery** | ✅ PASS | SonarQube over this repo's artifacts only, `waitForQualityGate` blocks publish (T026/T027/T028); upstream source excluded from scanner scope (FR-012/017, research D6). |

- **Initial gate (pre-Phase 0)**: PASS — the feature's requirements were authored to these invariants before the constitution formalized them.
- **Post-design gate (post-Phase 1)**: PASS. No complexity deviations to track; the Complexity Tracking section remains empty.

## Project Structure

### Documentation (this feature)

```text
specs/001-automated-docker-builds/
├── plan.md              # This file
├── spec.md              # Feature specification (input)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── image-interface.md      # Published image contract (env, ports, volumes, tags)
│   └── pipeline-interface.md   # Jenkins params, triggers, quality-gate + notification contracts
└── checklists/
    └── requirements.md  # Spec quality checklist (already passing)
```

### Source Code (repository root)

```text
Jenkinsfile                    # Declarative pipeline: poll → gate → build → publish → notify
sonar-project.properties       # SonarQube project config (scopes analysis to this repo's artifacts)
scripts/
├── check-release.sh           # Resolve latest eligible upstream release; decide build-or-skip via registry state
├── fetch-source.sh            # Download + extract the upstream release tarball for the resolved tag
├── build-and-push.sh          # buildx both platforms (all-or-nothing) → push version/latest/per-arch to both registries
├── quality-gate.sh            # Run ShellCheck → generic issues; invoke sonar-scanner; block on gate result
├── notify.sh                  # Emit maintainer notification on build/gate/publish failure
└── lib/
    └── common.sh              # Shared helpers (logging, registry manifest inspection, tag computation)
tests/
├── check-release.bats         # Unit tests for release selection + idempotency logic
├── tag-scheme.bats            # Unit tests for tag computation (version/latest/x64/arm64)
└── smoke/
    └── run-image.sh           # Boots a built image per arch, asserts web installer reachable
docs/
└── usage.md                   # End-user pull/run instructions (env vars, ports, volumes)
README.md                      # Repo overview + how the automation works
```

**Structure Decision**: Single-project CI automation layout. There is deliberately **no `Dockerfile` in this repo** — the build consumes the upstream release's own `Dockerfile`, which structurally guarantees FR-018. `scripts/` holds the automation stages the `Jenkinsfile` orchestrates; `tests/` covers the automation logic and an image smoke test; `docs/` + `README.md` are the human-facing run/maintenance guides. This layout supersedes the `.unraid/` template assets being removed per the repo's stated transition to a full Docker image.

## Complexity Tracking

> Constitution v1.0.0 Principles I–V all PASS with no deviations, so there are no violations to justify. This section is intentionally empty.
