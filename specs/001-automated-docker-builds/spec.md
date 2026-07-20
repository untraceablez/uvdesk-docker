# Feature Specification: Automated Multi-Arch UVdesk Docker Builds

**Feature Branch**: `001-automated-docker-builds`

**Created**: 2026-07-20

**Status**: Draft

**Input**: User description: "I want to build a repo that uses my Jenkins + SonarQube infrastructure to create automated Docker images of uvdesk/community-skeleton for x64 and arm64. UVDesk themselves provide documentation on their persistent docker containers here: https://github.com/uvdesk/community-skeleton/wiki/Docker-Persistent-Container. The goal is that repo would be automated to monitor for new releases of the community-skeleton repo: https://github.com/uvdesk/community-skeleton/releases, grabbing the latest version and rebuilding the Docker images, creating an x64 and arm64 image releases of the newest upstream version. The docker images would have a latest tag, version tags, as well as tags for x64 and arm64."

## Clarifications

### Session 2026-07-20

- Q: How should the build treat the upstream UVdesk release code? → A: Build strictly from the unmodified upstream release artifact — no feature additions and no bug-fix patches to UVdesk application code. This repo is a packaging/automation layer only.
- Q: How much first-run setup automation should the image add (without altering upstream app code)? → A: Environment variables pre-configure the database connection, but the operator completes the UVdesk web installer interactively in the browser on first run.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Publish an image for the current upstream release (Priority: P1)

As a self-hoster who wants to run UVdesk, I want a ready-to-pull Docker image that corresponds to the latest published UVdesk community-skeleton release, so that I can deploy the helpdesk without manually building it from source or following the multi-step manual container setup.

**Why this priority**: This is the core value of the repository. Without a published, pullable image tied to an upstream version, none of the automation, multi-arch, or quality-gate work matters. A single successful build-and-publish of one architecture already delivers usable value.

**Independent Test**: Trigger the pipeline against a known upstream release, then pull the resulting image by its version tag and by `latest` and confirm a UVdesk instance starts and reaches its web installer/login page.

**Acceptance Scenarios**:

1. **Given** upstream UVdesk has a published release (e.g., v1.1.8), **When** the pipeline runs for that release, **Then** an image is published tagged with both the exact upstream version (e.g., `1.1.8`) and `latest`.
2. **Given** a published image for a version, **When** a user pulls that version tag and runs it per the documented run parameters, **Then** the UVdesk application starts and serves its web interface.
3. **Given** the pipeline completed, **When** a user inspects the published tags, **Then** the version and `latest` tags both resolve to the build produced from that same upstream release.

---

### User Story 2 - Get the right image for my CPU architecture (Priority: P2)

As a user running on either an x86-64 server or an ARM64 device (e.g., Apple Silicon, Raspberry Pi, ARM cloud instance), I want to pull a single tag and automatically receive an image that runs natively on my hardware, and I also want the ability to pull an architecture-pinned tag explicitly, so that I get correct, performant behavior on my platform.

**Why this priority**: Broadens the usable audience to ARM users, which is the explicit differentiator the user asked for. It builds on P1 but is a distinct, independently demonstrable slice.

**Independent Test**: On an x86-64 host and on an ARM64 host, pull the same `latest` (and same version) tag and confirm each host runs a natively-matching image; separately, pull the explicit per-architecture tags and confirm each returns the corresponding architecture.

**Acceptance Scenarios**:

1. **Given** a release has been built, **When** a user on x86-64 pulls the version or `latest` tag, **Then** they receive an image that runs natively on x86-64.
2. **Given** a release has been built, **When** a user on ARM64 pulls the same version or `latest` tag, **Then** they receive an image that runs natively on ARM64.
3. **Given** a release has been built, **When** a user pulls the explicit x64 architecture tag or the explicit arm64 architecture tag, **Then** they receive an image of exactly that architecture regardless of the host they pull from.
4. **Given** an architecture-specific build fails, **When** the pipeline evaluates results, **Then** the combined/multi-architecture tags are not updated to a partial set that misrepresents availability.

---

### User Story 3 - Stay current automatically (Priority: P2)

As the maintainer, I want the repository to detect new upstream UVdesk releases on its own and kick off a build, so that new versions are made available without me manually watching the upstream releases page.

**Why this priority**: Automation is central to the request ("automated to monitor for new releases"). It is separable from P1 because P1 can be triggered manually first; automatic detection is the layer that removes ongoing manual effort.

**Independent Test**: Simulate/observe a new upstream release becoming available and confirm the pipeline starts and produces images for that new version without manual intervention; confirm that when no new release exists, no redundant build/publish occurs.

**Acceptance Scenarios**:

1. **Given** a new upstream release is published that has not yet been built, **When** the monitoring cycle runs, **Then** a build for that new version is started automatically.
2. **Given** the newest upstream release has already been built and published, **When** the monitoring cycle runs, **Then** no duplicate build or publish is performed.
3. **Given** the monitoring cycle cannot reach or read the upstream releases source, **When** it runs, **Then** it reports the failure and does not publish or mislabel any images.

---

### User Story 4 - Only ship builds that pass quality gates (Priority: P3)

As the maintainer of this repository, I want each build to pass an automated code-quality analysis before its images are published, so that broken or low-quality build definitions do not result in published images that users trust.

**Why this priority**: Adds trust and maintainability but is not required to deliver a working image. It gates P1/P2 rather than replacing them.

**Independent Test**: Introduce a change that fails the configured quality gate and confirm no images are published; revert it and confirm publishing resumes.

**Acceptance Scenarios**:

1. **Given** the repository's build definitions are analyzed, **When** the quality gate fails, **Then** no images are published for that run and the failure is surfaced to the maintainer.
2. **Given** the quality gate passes, **When** the pipeline continues, **Then** images are built and published as in P1/P2.

---

### Edge Cases

- **Upstream release exists but its source archive is unavailable or malformed** → the build fails cleanly, nothing is published, and the failure is reported.
- **Partial multi-arch build** (one architecture succeeds, the other fails) → nothing is published for that version at all (all-or-nothing per FR-013); no shared or per-architecture tags advance.
- **Re-run for a version already published** → behavior is idempotent; an intentional re-run overwrites the same version's images rather than creating divergent artifacts.
- **Upstream pre-release / draft release** → excluded from "latest" selection (only stable, non-draft, non-prerelease versions are considered the newest).
- **Upstream re-tags or deletes a release** → the pipeline does not delete previously published images and surfaces the discrepancy rather than silently reacting.
- **Registry is unreachable or authentication fails during publish** → the run fails after build, nothing is partially published under trusted tags, and the maintainer is notified.
- **Two monitoring cycles overlap** → concurrent runs for the same version do not corrupt each other's published tags.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST determine the newest eligible upstream release of `uvdesk/community-skeleton` from its published releases.
- **FR-002**: The system MUST treat only stable, non-draft, non-prerelease upstream releases as candidates for the "latest" image.
- **FR-003**: The system MUST build a Docker image for the selected upstream release, using UVdesk's documented persistent-container setup as the basis for the image.
- **FR-004**: The system MUST produce images for both x86-64 (x64) and ARM64 (arm64) architectures for each built release.
- **FR-005**: The system MUST publish images tagged with the exact upstream version identifier (e.g., `1.1.8`).
- **FR-006**: The system MUST publish/advance a `latest` tag that points to the images built from the newest eligible upstream release. The system MUST advance `latest` ONLY when the version being built is the newest eligible upstream release; a build of any older version (e.g., a manual or forced rebuild per FR-011) MUST NOT move `latest`.
- **FR-007**: The system MUST publish architecture-identifiable tags such that a user can explicitly obtain the x64 image and the arm64 image independent of their own host architecture.
- **FR-008**: A user pulling the version tag or `latest` without specifying an architecture MUST receive an image that runs natively on their host architecture (for the two supported architectures).
- **FR-009**: The system MUST automatically detect the availability of a new eligible upstream release without manual initiation.
- **FR-010**: The system MUST NOT rebuild or republish a version that has already been successfully built and published, unless a rebuild is explicitly requested.
- **FR-011**: The system MUST allow the maintainer to manually trigger a build for a specific upstream version (including re-building an already-published version). When the manually targeted version is not the newest eligible release, the run MUST publish that version's own tags (version + arch-pinned) but MUST NOT advance `latest` (see FR-006).
- **FR-012**: The system MUST run an automated code-quality analysis of the repository's own build definitions/scripts, and MUST NOT publish images for a run whose quality gate fails.
- **FR-013**: If any required architecture's build fails, the run MUST publish nothing for that version — no shared tags (`latest`, version) AND no per-architecture tags are advanced (all-or-nothing). This guarantees that any published tag for a version means all required architectures are present.
- **FR-014**: The system MUST report build, quality-gate, and publish failures to the maintainer through a notification channel.
- **FR-015**: The system MUST record which upstream version each published image corresponds to, so that published images are traceable to an upstream release.
- **FR-016**: The system MUST publish images to both Docker Hub and GitHub Container Registry (GHCR) in the same run, from which end users can pull them. Equivalent tags (version, `latest`, and per-architecture) MUST be present on both registries for a successful run, and a publish failure to either registry MUST be treated as a failed run per FR-013/FR-014.
- **FR-017**: The code-quality analysis (quality gate) MUST cover this repository's own authored artifacts — the build/monitor scripts and pipeline configuration (this repo authors no Dockerfile; see FR-018) — and MUST NOT be expected to analyze upstream UVdesk source, which is fetched by release rather than developed here.
- **FR-018**: The system MUST build images exclusively from the upstream UVdesk release artifact as published. It MUST NOT modify, patch, add features to, or bug-fix the upstream UVdesk application source. This repository provides only a packaging/automation layer around unmodified upstream releases; if an upstream release is defective, the correct response is to skip/report it, not to patch upstream code here.
- **FR-019**: The image MAY include a repository-authored packaging/automation layer (e.g., a container entrypoint and environment-variable-driven configuration) that pre-configures the database connection so the operator does not run manual in-container SQL commands. The UVdesk web-based installer is completed interactively by the operator on first run. This packaging layer MUST NOT alter upstream application code (consistent with FR-018).
- **FR-020**: Once a version is detected and passes the quality gate, the build-through-publish flow MUST require no manual maintainer intervention (fully hands-off); manual action is required only for the explicit override in FR-011 or to resolve a reported failure.

### Key Entities *(include if feature involves data)*

- **Upstream Release**: A published version of `uvdesk/community-skeleton` identified by a semantic version (e.g., `1.1.8`), with attributes: version identifier, stable/prerelease/draft status, publish date, and a source archive to build from.
- **Built Image**: A Docker image produced from one upstream release for one architecture. Attributes: upstream version, architecture (x64/arm64), build timestamp, and the set of tags it is published under.
- **Tag**: A human-facing pointer to one or more built images. Categories: `latest`, exact-version (e.g., `1.1.8`), and architecture-specific (e.g., an x64 tag and an arm64 tag).
- **Build Record / State**: The record of which upstream versions have already been successfully built and published, used to avoid duplicate work and provide traceability.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For the current newest eligible upstream release, a user can pull the corresponding version tag and `latest` and successfully start a working UVdesk instance on both x86-64 and ARM64 hosts.
- **SC-002**: When a new eligible upstream release is published, corresponding multi-architecture images are available to pull within one monitoring cycle of detection, with no manual steps required.
- **SC-003**: 100% of published `latest`/version tags correspond to a build that completed successfully for both required architectures (no partial/mislabeled shared tags).
- **SC-004**: A run whose quality gate fails results in zero images published for that run, 100% of the time.
- **SC-005**: Re-running the pipeline for an already-published, unchanged version produces no duplicate or divergent published artifacts.
- **SC-006**: Every published image can be traced to the exact upstream release version it was built from.
- **SC-007**: Any build, quality-gate, or publish failure produces a maintainer-visible notification within one pipeline run.

## Assumptions

- **Tagging model**: The version and `latest` tags are multi-architecture references that resolve to the correct architecture for the puller's host, while the "x64" and "arm64" tags are explicit architecture-pinned references. This matches standard multi-arch image distribution and satisfies the request for `latest`, version, x64, and arm64 tags simultaneously.
- **Atomicity policy (FR-013, resolved)**: Builds are all-or-nothing per version. No tags of any kind (shared or per-architecture) are published unless every required architecture builds successfully; a single-architecture failure aborts publishing for that version entirely.
- **Registry targets (FR-016, resolved)**: Images are published to both Docker Hub and GHCR each run, with matching tag sets on both.
- **Quality-gate scope (FR-017, resolved)**: SonarQube analyzes only this repository's own authored artifacts; upstream UVdesk source is out of scope for the gate.
- **Upstream build basis**: The image is built from UVdesk's documented persistent-container approach (Apache + PHP application + supporting database, as described in the UVdesk Docker wiki), using the unmodified upstream release artifact (FR-018). Whether the database runs inside the same image or is expected as an external service is an implementation detail settled during planning; the spec only requires that the published image starts and reaches UVdesk's web installer/login per UVdesk's documented run parameters.
- **First-run model (Session 2026-07-20)**: Environment variables pre-configure the database connection (removing the manual in-container SQL steps from the upstream docs), but the operator completes the UVdesk web installer interactively on first run (FR-019). "A working instance" therefore means the container starts and serves the web installer/login, not a fully pre-seeded application.
- **Infrastructure**: Jenkins provides pipeline execution and scheduling/monitoring; SonarQube provides the quality-gate analysis. These are pre-existing, maintainer-operated systems and are not provisioned by this feature.
- **Monitoring cadence**: Upstream releases are polled on a recurring schedule (rather than via an upstream-provided webhook), since the upstream project is not assumed to push notifications to this repository. The exact interval is an implementation detail.
- **Scope boundaries (explicit out-of-scope)**: This feature covers detecting, building, quality-gating, tagging, and publishing images. It explicitly does NOT cover: modifying, patching, or bug-fixing upstream UVdesk application source (FR-018); adding application features to UVdesk; providing end-user application support; or hosting/operating a running UVdesk instance. Ongoing per-release maintainer effort is also out of scope — the pipeline is hands-off after the quality gate passes (FR-020).
- **Non-destructive to history**: Previously published images for older versions are retained; the feature does not garbage-collect or delete historical version tags.
