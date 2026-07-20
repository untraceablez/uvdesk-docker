# Phase 0 Research: Automated Multi-Arch UVdesk Docker Builds

**Feature**: 001-automated-docker-builds | **Date**: 2026-07-20

This document records the technical decisions that resolve the plan's unknowns. All findings are grounded in the actual upstream `uvdesk/community-skeleton` v1.1.8 release artifacts (Dockerfile, entrypoint, releases API) inspected during planning.

---

## D1. Build the unmodified upstream release (honoring FR-018)

**Decision**: Do **not** author a Dockerfile in this repo. Fetch the upstream release source archive for the resolved tag and run `docker buildx` against the **upstream release's own `Dockerfile`**, unmodified.

**Rationale**:
- The upstream release ships a complete `Dockerfile`, a `.docker/` config tree, and `.docker/bash/uvdesk-entrypoint.sh`. Building it as-is means we never touch upstream — FR-018 is satisfied *structurally* (there is nothing here to patch it with), not merely by policy.
- The upstream Dockerfile is already multi-arch-clean (see D2), so no fork/patch is needed to reach arm64.

**Alternatives considered**:
- *Author our own Dockerfile that `COPY`s the upstream source* — rejected: it duplicates upstream's build logic, drifts over time, and blurs the FR-018 boundary (our Dockerfile could inadvertently change behavior).
- *Fork upstream and maintain patches* — rejected outright: directly violates FR-018 and the clarified scope.

**Caveat**: Upstream's `Dockerfile` begins `FROM ubuntu:latest` (a floating base tag) and installs `mysql-server` + PHP from `ppa:ondrej/php`. Builds are therefore **not bit-reproducible** across time. We accept this because pinning would require modifying upstream (forbidden). Traceability is preserved via the exact upstream version tag on every image (FR-015) and a build-time label recording the upstream commit/tag and build timestamp.

---

## D2. Multi-architecture strategy: Buildx + QEMU emulation

**Decision**: Produce `linux/amd64` and `linux/arm64` images with Docker Buildx using QEMU/binfmt emulation on the x86-64 Jenkins agent. A native arm64 build node is an optional future optimization, not required.

**Rationale**:
- The upstream Dockerfile is architecture-agnostic: `FROM ubuntu:latest` resolves per-platform, PHP 8.1 from `ppa:ondrej/php` is published for amd64 and arm64, and gosu is fetched via `dpkg --print-architecture` (`gosu-$dpkgArch`) — so the same Dockerfile builds natively on both arches with no changes.
- QEMU emulation needs no ARM hardware; volume is low (a few builds/year), so the slower emulated `composer install` on arm64 is acceptable.

**Alternatives considered**:
- *Native arm64 Jenkins agent* — faster, but adds infrastructure the maintainer must run; deferred as an optimization.
- *Cross-compilation* — N/A; this is an interpreted-PHP + apt image, not a compiled artifact.

---

## D3. Tagging + all-or-nothing publishing (FR-005/006/007/013)

**Decision**: For each release build to both registries:
- `X.Y.Z` and `latest` → **multi-arch manifest lists** (resolve to the puller's native arch).
- `X.Y.Z-amd64` / `X.Y.Z-arm64` and the friendly `x64` / `arm64` → **architecture-pinned** references.

Achieve atomicity by running a **single `buildx build --platform linux/amd64,linux/arm64`** — buildx fails the whole invocation if either architecture fails, so nothing is pushed on a partial build. Only after that succeeds do we materialize the shared multi-arch tags and then derive the arch-pinned tags via `docker buildx imagetools create` from the already-pushed per-platform digests.

**Rationale**: One buildx invocation gives all-or-nothing for free (FR-013). Deriving arch-pinned tags *after* the atomic push means every extra tag is created only on a fully successful build. `imagetools create` copies manifests without rebuilding.

**Alternatives considered**:
- *Build each arch separately, then `manifest create`* — more moving parts and a window where one arch tag exists without the other; rejected in favor of the atomic single-invocation build.
- *Push per-arch first, gate shared tags* — this was FR-013 Option B, explicitly rejected during clarification in favor of all-or-nothing.

---

## D4. Dual-registry publishing (FR-016)

**Decision**: Push identical tag sets to **Docker Hub** and **GHCR** in the same run. Perform the atomic multi-arch `buildx build --push` targeting both registries' refs; if either registry push fails, the whole run fails (per FR-013/FR-014). Credentials are supplied as Jenkins credentials (Docker Hub token; GHCR PAT/`GITHUB_TOKEN`).

**Rationale**: buildx accepts multiple `-t` refs across registries in one `--push`, keeping tag sets in lockstep. Failure of either push aborts before any "trusted" tag set is considered complete.

**Alternatives considered**:
- *Build once → push to registry A → `imagetools create` copy to registry B* — viable fallback if simultaneous multi-registry push proves flaky under the agent's auth setup; documented as a contingency in the pipeline contract.

---

## D5. Release monitoring + idempotency (FR-009/010/011)

**Decision**: Jenkins polls the GitHub Releases API (`/repos/uvdesk/community-skeleton/releases/latest`) on a schedule (SCM/cron trigger). Select the newest release where `draft == false && prerelease == false` (FR-002). Decide build-vs-skip by checking whether that version's manifest already exists on **both** registries (`imagetools inspect`); if present on both, skip (FR-010). A `FORCE_REBUILD` boolean pipeline parameter overrides the skip and also lets the maintainer target a specific `VERSION` (FR-011).

**Rationale**: Using the registry as the state store removes any separate database and makes idempotency self-evident — "already built" literally means "the tag is published." Checking *both* registries prevents a half-published state from being treated as done.

**Alternatives considered**:
- *Commit a `last-built.txt` marker to this repo* — extra write path, can desync from reality; rejected.
- *GitHub webhook from upstream* — we don't control the upstream repo, so we cannot register a webhook; polling is the only option (matches the spec's monitoring-cadence assumption).

**Poll interval**: Default hourly. Rationale: upstream releases a few times per year; hourly gives fast pickup at negligible cost. Interval is a Jenkins config value, easily tuned.

---

## D6. SonarQube quality gate scope + shell coverage (FR-012/017)

**Decision**: The SonarQube analysis covers only this repository's authored artifacts. Because current SonarQube has limited native shell/Groovy support, run **ShellCheck** over `scripts/**` and import its findings into SonarQube via the **generic external issues** format (`sonar.externalIssuesReportPaths`); also enable SonarQube's built-in **Secrets** and **IaC** analyzers over the repo. The Jenkins pipeline calls `sonar-scanner`, then **waits on the SonarQube quality gate** (webhook/`waitForQualityGate`) and **blocks build+publish** if the gate fails (FR-012). Upstream source is never fetched into the scanner's scope (FR-017).

**Rationale**: This gives a meaningful, enforceable gate over the code we actually own (mostly shell), while respecting that we author no PHP/app code. Secrets detection guards against leaking registry credentials into the repo.

**Alternatives considered**:
- *Rely on SonarQube native analysis alone* — rejected: it would find little in a shell/Groovy repo, making the gate hollow.
- *Gate on ShellCheck/hadolint directly in Jenkins, bypassing Sonar* — rejected: the spec designates SonarQube as the quality gate; we route linters *through* Sonar instead of around it. (No `hadolint` needed since we own no Dockerfile.)

---

## D7. First-run model — no additions needed (FR-019)

**Decision**: Rely entirely on the upstream entrypoint. No wrapper entrypoint, no added scripts in the image.

**Rationale**: Inspection of `.docker/bash/uvdesk-entrypoint.sh` confirms it already: reads `MYSQL_USER`/`MYSQL_PASSWORD`/`MYSQL_DATABASE`/`MYSQL_ROOT_PASSWORD`, pings MySQL, `CREATE DATABASE IF NOT EXISTS`, grants privileges, sets root credentials, writes `my.cnf` files, restarts Apache + MySQL, and drops to the `uvdesk` user via gosu — leaving the UVdesk **web installer** to be completed interactively. That is exactly the FR-019 model (env-driven DB config + interactive installer), so the clarified requirement is met by unmodified upstream. The wiki's manual `CREATE USER`/`ALTER USER` steps are only the fallback path when the env vars are not all supplied.

**Implication**: The published-image contract (contracts/image-interface.md) documents these env vars, the exposed port, and persistence volumes so end users get a hands-off DB bring-up.

---

## D8. Failure notification channel (FR-014)

**Decision**: Notify the maintainer by **email** (Jenkins Extended E-mail on `failure`/`unstable`), with an optional chat webhook (Slack/Discord) toggled by a Jenkins config value. Every failed stage (release check, quality gate, build, publish) marks the run failed so a single notification path covers all FR-014 cases.

**Rationale**: Email is universally available in Jenkins with no extra infra and satisfies "maintainer-visible notification within one pipeline run" (SC-007). The webhook hook is additive for maintainers who prefer chat.

**Alternatives considered**: Chat-only — rejected as the default because it assumes infra the maintainer may not run; offered as an opt-in instead.

---

## Resolved unknowns summary

| Unknown | Resolution |
|---|---|
| Do we need our own Dockerfile? | No — build upstream's unmodified (D1) |
| Is upstream multi-arch capable? | Yes — Ubuntu base + ondrej PHP + dynamic gosu arch (D2) |
| How to keep publishing all-or-nothing? | Single `buildx --platform amd64,arm64` invocation (D3) |
| Both registries in lockstep? | Multi-ref `buildx --push`, fail-fast (D4) |
| How to detect "already built"? | Registry manifest existence on both registries (D5) |
| What can SonarQube actually gate here? | ShellCheck→generic issues + Secrets/IaC analyzers, `waitForQualityGate` (D6) |
| Does FR-019 need added code? | No — upstream entrypoint already env-drives the DB (D7) |
| Notification mechanism? | Jenkins email + optional webhook (D8) |

No `NEEDS CLARIFICATION` markers remain.
