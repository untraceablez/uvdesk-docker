---
description: "Task list for Automated Multi-Arch UVdesk Docker Builds"
---

# Tasks: Automated Multi-Arch UVdesk Docker Builds

**Input**: Design documents from `/specs/001-automated-docker-builds/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Included — the plan's Testing section and quickstart.md explicitly call for ShellCheck, `bats` unit tests, and an image smoke test. Test tasks are scoped to the story they validate.

**Organization**: Tasks are grouped by user story (US1–US4) so each can be implemented and validated as an independent increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1–US4, mapping to spec.md user stories
- Exact file paths are given in each task

## Path Conventions

Single-project CI automation layout at repo root (per plan.md): `Jenkinsfile`, `sonar-project.properties`, `scripts/`, `scripts/lib/`, `tests/`, `tests/smoke/`, `docs/`. **There is deliberately no `Dockerfile` in this repo** — builds run against the upstream release's own Dockerfile (FR-018).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Repo housekeeping and skeleton for the automation layer

- [X] T001 Remove obsolete `.unraid/` template assets and rewrite `README.md` to describe this repo's purpose (automated multi-arch UVdesk image builds) at repo root
- [X] T002 [P] Create the directory structure `scripts/`, `scripts/lib/`, `tests/`, `tests/smoke/`, `docs/` with `.gitkeep` placeholders where empty (repo root)
- [X] T003 [P] Bootstrap the test/lint harness: add `bats` test scaffolding under `tests/` and a `Makefile` (or `scripts/dev.sh`) exposing `lint` (ShellCheck over `scripts/**`) and `test` (bats) targets at repo root

**Checkpoint**: Repo reflects the Docker-automation transition; tooling entrypoints exist.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared helpers and pipeline scaffold every user story depends on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Implement `scripts/lib/common.sh`: structured logging helpers, a GitHub API fetch wrapper (`curl`+`jq`), a registry manifest-existence check via `docker buildx imagetools inspect` (both registries), and a pure tag-computation function that takes the version plus an `is_newest` boolean and returns the tag names, INCLUDING `latest` only when `is_newest` is true (`X.Y.Z`, `X.Y.Z-amd64`, `X.Y.Z-arm64`, `x64`, `arm64`, and `latest` iff newest — FR-006)
- [X] T005 [P] Implement `scripts/notify.sh`: send a maintainer notification (email via `NOTIFY_EMAIL`, optional webhook via `NOTIFY_WEBHOOK_URL`) taking version + failed-stage + run-URL args (FR-014); source `scripts/lib/common.sh`
- [X] T006 Create `Jenkinsfile` skeleton: declarative pipeline with `options { disableConcurrentBuilds() }` (single-flight, guarding the overlapping-cycle edge case), parameters `VERSION` (string) and `FORCE_REBUILD` (boolean), credential/env bindings (`DOCKERHUB_*`, `GHCR_*`, `SONAR_*`, `NOTIFY_*`), agent setup that registers QEMU/binfmt and creates a buildx builder, empty ordered stage scaffold, and a `post { failure { sh 'scripts/notify.sh ...' } }` block (contracts/pipeline-interface.md)
- [X] T007 [P] Document Jenkins prerequisites in `docs/usage.md`: required credentials, config values, and the buildx/QEMU builder bootstrap (contracts/pipeline-interface.md configuration table)
- [X] T008 [P] Implement `scripts/lib/assert-unmodified-upstream.sh` (called by the build stage): assert this repo contributes NO `Dockerfile` or `.docker/` override at repo root, and that the build context passed to buildx is exactly the freshly-extracted upstream release directory (no repo files copied in, no post-extract patching). Fail the pipeline if any check trips — mechanical enforcement of FR-018

**Checkpoint**: Shared helpers + pipeline skeleton + notifications + upstream-integrity guard ready.

---

## Phase 3: User Story 1 - Publish an image for the current upstream release (Priority: P1) 🎯 MVP

**Goal**: A manual run builds a working (amd64) image from a specified unmodified upstream release and publishes `X.Y.Z` (+ `latest` when newest) to both Docker Hub and GHCR.

**Independent Test**: Run with `VERSION=1.1.8`; pull `:1.1.8` and `:latest` from both registries and boot the container — it reaches the UVdesk web installer.

- [X] T009 [US1] Implement `scripts/fetch-source.sh`: resolve the release tarball URL for a given `VERSION` via the GitHub API, download + extract to a work dir, and assert a root `Dockerfile` exists (fail cleanly + notify on missing/malformed archive); source `scripts/lib/common.sh`. For US1 standalone independence, also compute a self-contained `is_newest` value here (compare the target `VERSION` against the newest eligible release, or accept a manual `IS_NEWEST` override) so US1's `latest` gating does not depend on US3's `check-release.sh`. **Builds nothing itself — consumes upstream unmodified (FR-018)**
- [X] T010 [US1] Implement `scripts/build-and-push.sh` (single-arch path): `docker buildx build --platform linux/amd64` against the extracted upstream `Dockerfile`, tagging `X.Y.Z` (and `latest` only when the build is the newest eligible release, via the `is_newest` flag from `common.sh` — FR-006) for **both** `docker.io/$DOCKERHUB_NAMESPACE/uvdesk` and `ghcr.io/$GHCR_OWNER/uvdesk`, and `--push` (FR-003/005/006/016); source `scripts/lib/common.sh`
- [X] T011 [US1] Add build-time traceability labels (upstream tag, upstream commit ref, build timestamp) to the build invocation in `scripts/build-and-push.sh` (FR-015)
- [X] T012 [US1] Wire the US1 stages into `Jenkinsfile`: `Fetch source` → (`assert-unmodified-upstream.sh`) → `Build & Push`, driven by the manual `VERSION` parameter, with failures routed to the `post` notify block
- [X] T013 [P] [US1] Implement `tests/smoke/run-image.sh`: boot the built amd64 image with `MYSQL_ROOT_PASSWORD/MYSQL_DATABASE/MYSQL_USER/MYSQL_PASSWORD` set, map `-p 0:80`, then assert BOTH (a) the web installer responds HTTP 200 AND (b) the upstream entrypoint actually provisioned the DB — i.e. `MYSQL_DATABASE` exists and `MYSQL_USER` can authenticate (e.g. `mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -e 'SHOW DATABASES' | grep $MYSQL_DATABASE`). Fail the build if provisioning did not occur, guarding FR-019 against an upstream entrypoint regression (contracts/image-interface.md)
- [X] T014 [P] [US1] Add the end-user pull/run section to `docs/usage.md`: tags, `MYSQL_*` env vars, port `80`, and persistence volumes `/var/lib/mysql` + `/var/www/uvdesk` (contracts/image-interface.md)

**Checkpoint**: MVP — a manually-triggered amd64 build publishes `version` (+ `latest` if newest) to both registries and the image boots to the installer. NOTE: FR-004 (both arches) and FR-013 (all-or-nothing across arches) are NOT yet satisfied at this checkpoint — they close in US2.

---

## Phase 4: User Story 2 - Get the right image for my CPU architecture (Priority: P2)

**Goal**: Produce amd64 **and** arm64 images all-or-nothing, with shared multi-arch tags plus explicit arch-pinned tags, on both registries.

**Independent Test**: After a build, `imagetools inspect :1.1.8` lists both platforms; `:x64`/`:arm64` each resolve to a single platform; a partial-arch failure publishes nothing.

- [X] T015 [US2] Extend `scripts/build-and-push.sh` to a single atomic multi-arch build: `docker buildx build --platform linux/amd64,linux/arm64 --push` — if either architecture fails, nothing is pushed (FR-004/013)
- [X] T016 [US2] After the atomic multi-arch push, derive arch-pinned tags in `scripts/build-and-push.sh` via `docker buildx imagetools create`: `X.Y.Z-amd64` + `x64` (amd64) and `X.Y.Z-arm64` + `arm64` (arm64), to both registries (FR-007)
- [X] T017 [US2] Enforce dual-registry lockstep in `scripts/build-and-push.sh`: push identical tag sets to Docker Hub and GHCR and fail the run if either registry push fails (FR-016 + FR-013)
- [X] T018 [P] [US2] Add `tests/tag-scheme.bats`: assert `scripts/lib/common.sh` computes exactly the expected tag names — the five per-version tags always, plus `latest` only when `is_newest` is true (shared + arch-pinned)
- [X] T019 [US2] Extend `tests/smoke/run-image.sh` to boot both `linux/amd64` and `linux/arm64` (arm64 via QEMU) and run the full FR-008 + FR-019 assertion set (installer reachable AND DB auto-provisioned) against each architecture natively
- [X] T020 [US2] Update the `Jenkinsfile` build stage to invoke the atomic multi-arch path and the arch-pinned tag derivation

**Checkpoint**: Both architectures, all-or-nothing, all six tags present on both registries.

---

## Phase 5: User Story 3 - Stay current automatically (Priority: P2)

**Goal**: Detect new eligible upstream releases on a schedule and build them hands-off, skipping already-published versions, with a manual override.

**Independent Test**: Point at an unbuilt version → it builds and publishes with no manual steps; re-run → it skips; `FORCE_REBUILD=true` → it rebuilds.

- [X] T021 [US3] Implement `scripts/check-release.sh`: fetch `releases/latest`, select the newest release with `draft==false && prerelease==false`, validate semver, and compute the `build|skip` decision by checking manifest existence on **both** registries (FR-001/002/010); source `scripts/lib/common.sh`
- [X] T022 [US3] Add manual-override handling across `scripts/check-release.sh` + `Jenkinsfile`: honor an explicit `VERSION` and the `FORCE_REBUILD` flag to rebuild an already-published version, and emit an `is_newest` signal (target == newest eligible release) that `build-and-push.sh` uses to decide whether `latest` advances (FR-011/FR-006)
- [X] T023 [US3] Add the cron poll trigger (`POLL_SCHEDULE`) and the `Resolve release` stage to `Jenkinsfile`, ending the run as `skipped` (no build/publish/notify) when the decision is skip (FR-009/020)
- [X] T024 [US3] Handle unreachable/unreadable upstream source in `scripts/check-release.sh` + `scripts/fetch-source.sh`: fail cleanly, notify, and publish/mislabel nothing (spec Edge Cases)
- [X] T025 [P] [US3] Add `tests/check-release.bats`: cover newest-eligible selection, draft/prerelease exclusion, skip-when-present-on-both-registries, and `FORCE_REBUILD` override

**Checkpoint**: Hands-off scheduled detection with idempotent skip and manual override.

---

## Phase 6: User Story 4 - Only ship builds that pass quality gates (Priority: P3)

**Goal**: A SonarQube quality gate over this repo's own artifacts blocks build+publish on failure.

**Independent Test**: Introduce a ShellCheck error or committed secret → gate fails → no images published + maintainer notified; revert → publishing resumes.

- [X] T026 [US4] Author `sonar-project.properties`: set `sonar.sources` to `scripts/`, `Jenkinsfile`, config and docs; explicitly exclude the fetched/extracted upstream work dir so upstream source is never analyzed (FR-017)
- [X] T027 [US4] Implement `scripts/quality-gate.sh`: run ShellCheck over `scripts/**` emitting a report wired via `sonar.externalIssuesReportPaths`, invoke `sonar-scanner`, and rely on SonarQube Secrets/IaC analyzers (FR-012/017)
- [X] T028 [US4] Add a `Quality Gate` stage to `Jenkinsfile` **before** Fetch/Build: run `scripts/quality-gate.sh` then `waitForQualityGate`, aborting the run (no build, no publish) on any non-OK result (FR-012, SC-004)
- [X] T029 [P] [US4] Verify gate-failure path routes through `scripts/notify.sh` and marks the run failed, and add a `bats` assertion for the gate stage's block-on-failure behavior in `tests/quality-gate.bats`

**Checkpoint**: A failing gate produces zero published images and a maintainer notification.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Finalize docs, validation, and cross-story guarantees

- [X] T030 [P] Finalize `README.md`: architecture overview, how the poll→gate→build→publish flow works, and a maintainer runbook
- [ ] T031 Run all `quickstart.md` scenarios A–E end-to-end and record outcomes (SC-001 through SC-007)
- [X] T032 [P] ShellCheck-clean pass over all `scripts/**`, confirm `lint`/`test` targets are green, and add a repo-invariant test asserting no `Dockerfile` exists at repo root (FR-018 regression guard)
- [X] T033 Document non-destructive history + concurrency behavior in `docs/usage.md`: older version tags are never deleted, and overlapping poll cycles are prevented by `disableConcurrentBuilds()` (T006) so runs cannot corrupt published tags (spec Edge Cases)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories (`common.sh`, `notify.sh`, `Jenkinsfile` skeleton, `assert-unmodified-upstream.sh`)
- **User Stories (Phase 3–6)**: All depend on Foundational
  - US1 (P1) is the MVP and should be built first
  - US2 (P2) extends `scripts/build-and-push.sh` from US1 — build US2 after US1
  - US3 (P2) is largely independent (new `check-release.sh`) but its "publish" path exercises US1/US2 build code; it provides the authoritative `is_newest` signal for automated runs, while US1 (T009) computes its own fallback `is_newest` so the MVP stays independently correct
  - US4 (P3) is independent (new `quality-gate.sh` + Sonar config + one Jenkinsfile stage)
- **Polish (Phase 7)**: After all targeted stories are complete

### Key File-Level Dependencies (shared files ⇒ sequential)

- `scripts/build-and-push.sh`: T010 (US1) → T015 → T016 → T017 (US2) — same file, must be sequential
- `tests/smoke/run-image.sh`: T013 (US1) → T019 (US2)
- `Jenkinsfile`: T006 (foundational) → T012 (US1) → T020 (US2) → T022/T023 (US3) → T028 (US4) — same file, sequential
- `scripts/lib/common.sh` (T004) must precede every script that sources it
- `scripts/lib/assert-unmodified-upstream.sh` (T008) must precede the build stage (T012/T020)

### Within Each User Story

- Implement scripts before wiring the Jenkinsfile stage
- `[P]` test/docs tasks can run alongside implementation once their target script exists

---

## Parallel Opportunities

- **Setup**: T002 and T003 in parallel (after T001)
- **Foundational**: T005, T007, and T008 in parallel with T004/T006 (different files)
- **US1**: T013 and T014 in parallel once T010 exists
- **US2**: T018 in parallel with T015–T017 (different file)
- **US3**: T025 in parallel with T021–T024 (different file)
- **US4**: T029 in parallel with T026–T028 once the stage exists
- **Cross-story (if staffed)**: US3 and US4 can proceed in parallel with US2, since they touch different scripts (coordinate only on the shared `Jenkinsfile`)

### Parallel Example: User Story 1

```bash
# After scripts/build-and-push.sh (T010) exists, run in parallel:
Task: "Smoke test tests/smoke/run-image.sh (T013)"
Task: "End-user usage docs in docs/usage.md (T014)"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 Setup → Phase 2 Foundational (CRITICAL — blocks all stories)
2. Phase 3 US1 → **STOP and VALIDATE**: `VERSION=1.1.8` builds an amd64 image, publishes `version` (+`latest` if newest) to both registries, and boots to the installer
3. Demo the MVP

### Incremental Delivery

1. Setup + Foundational → foundation ready
2. US1 → single-arch publish (MVP) → demo
3. US2 → multi-arch + arch-pinned tags, all-or-nothing → demo
4. US3 → hands-off scheduled detection + idempotency → demo
5. US4 → SonarQube quality gate blocking publish → demo
6. Polish → docs + full quickstart validation

### Notes

- **FR-018 (never modify upstream)** is satisfied structurally AND enforced mechanically: no task authors or patches upstream code; T009/T010 build the upstream release's own Dockerfile as-is, and T008 fails the pipeline if a repo Dockerfile/override or post-extract patch is detected.
- **FR-019 (env DB + interactive installer)** needs no image code — it is provided by the unmodified upstream entrypoint; US1 tasks document it (T014) and actively assert it still works per built version (T013/T019).
- **FR-006 (`latest` gating)**: `latest` advances only for the newest eligible release; the `is_newest` decision flows common.sh (T004) → check-release (T022) → build-and-push (T010).
- `[P]` = different files, no incomplete dependencies. Commit after each task or logical group. Stop at any checkpoint to validate a story independently.
