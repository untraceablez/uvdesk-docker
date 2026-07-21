<!--
Sync Impact Report — 2026-07-20 (v1.1.0)
Version change: 1.0.0 → 1.1.0
Bump rationale (MINOR): expanded guidance on Principle I — build-environment base-image
pins (buildx --build-context override of upstream's floating FROM ubuntu:latest) are
explicitly permitted as reproducibility, not modification. Prompted by upstream v1.1.8
failing to build once ubuntu:latest rolled to 26.04 "resolute" (no ondrej/php PPA yet).
Templates/artifacts: build-and-push.sh implements the pin (UBUNTU_BASE_PIN, default
ubuntu:24.04); research.md D1 updated. No principle removed or redefined.

--- Prior: Sync Impact Report — 2026-07-20
Version change: (unratified template) → 1.0.0
Bump rationale: Initial ratification of the project constitution (first concrete adoption).

Modified principles: N/A (initial adoption)
Added principles:
  - I. Upstream Integrity (Never Fork)
  - II. Atomic, All-or-Nothing Publishing
  - III. Traceability & Idempotency
  - IV. Automation-First, Hands-Off Operation
  - V. Quality-Gated Delivery
Added sections:
  - Technology & Scope Constraints
  - Development Workflow & Quality Gates
  - Governance

Templates reviewed for alignment:
  - .specify/templates/plan-template.md ✅ aligned (Constitution Check defers to this file generically; no edit needed)
  - .specify/templates/spec-template.md ✅ aligned (generic; no principle-driven mandatory sections to add)
  - .specify/templates/tasks-template.md ✅ aligned (generic phase/task categorization compatible)
  - .claude/skills/speckit-*/ command files ✅ reviewed (no outdated agent-specific references requiring change)

Follow-up TODOs:
  - specs/001-automated-docker-builds/plan.md "Constitution Check" re-evaluated against Principles I–V —
    all PASS with a per-principle evidence table. ✅ resolved 2026-07-20.
-->

# UVdesk Docker Automation Constitution

This constitution governs the `uvdesk-docker` repository: an automation and packaging layer that
produces multi-architecture Docker images of `uvdesk/community-skeleton` releases. It does not
govern UVdesk's own application code, which is upstream and out of this project's authorship.

## Core Principles

### I. Upstream Integrity (Never Fork)

The project MUST build images exclusively from upstream UVdesk release artifacts exactly as published.
It MUST NOT modify, patch, add features to, or bug-fix upstream application source, and MUST NOT
introduce a repository-authored `Dockerfile` or `.docker/` override that supplants upstream's own.
The build MUST run against the upstream release's own build definition; a mechanical guard MUST fail
the pipeline if a repo-authored Dockerfile/override or any post-extract patch of upstream source is
detected. When an upstream release is defective, the only permitted responses are to skip it and/or
report it — never to patch upstream here.

**Build-environment pins are permitted (clarification, v1.1.0)**: Pinning the *build environment* —
notably resolving upstream's floating `FROM ubuntu:latest` to a specific Ubuntu version via a buildx
`--build-context` override — is NOT a modification of upstream source and IS permitted. It edits no
upstream file, adds no Dockerfile, and changes no application code; it reproduces the build against the
OS the upstream release actually targeted. This is the sanctioned response to upstream's non-pinned
base breaking when `ubuntu:latest` advances ahead of a required PPA. The mechanical integrity guard
(no repo Dockerfile/override, unmodified extracted context) still applies unchanged.

**Rationale**: This repo's value is trustworthy, drift-free repackaging. Forking or patching upstream
would silently diverge behavior, break the "same as upstream" contract users rely on, and create an
unbounded maintenance burden. Enforcing this mechanically (not by convention) is what makes it real.
A build-environment pin serves the same goal — it makes the unmodified upstream build *reproducible*
rather than changing it.

### II. Atomic, All-or-Nothing Publishing

A release version MUST be published for all required architectures and to all target registries, or
not published at all. If any required architecture's build fails, or a push to any target registry
fails, the run MUST publish nothing for that version — no shared tags (`latest`, version) and no
per-architecture tags. Any published tag for a version therefore guarantees every required
architecture is present, on every target registry, in lockstep.

**Rationale**: Partial publishes mislabel availability and produce inconsistent state across registries
and platforms. All-or-nothing is the only policy that makes a tag a reliable signal.

### III. Traceability & Idempotency

Every published image MUST be traceable to the exact upstream version it was built from (recorded via
image labels). The `latest` tag MUST advance only for the newest eligible release; a build of an older
version MUST NOT move `latest`. Publishing MUST be idempotent: an already-published, unchanged version
MUST NOT be rebuilt or republished unless a rebuild is explicitly requested, and previously published
version tags MUST NOT be deleted. Where practical, the container registry is the source of truth for
"already built" state rather than a separate store.

**Rationale**: Users and maintainers must be able to map any image back to an upstream release, trust
that `latest` means newest, and re-run pipelines without producing duplicate or divergent artifacts.

### IV. Automation-First, Hands-Off Operation

Once a new eligible release is detected and its quality gate passes, the build-through-publish flow
MUST complete with no manual maintainer intervention. New eligible releases MUST be detected without
manual initiation. Pipeline runs MUST be single-flight so overlapping cycles cannot corrupt published
tags. Manual action is permitted only for an explicit maintainer override (e.g., targeting or force-
rebuilding a specific version) or to resolve a reported failure. All build, quality-gate, and publish
failures MUST be reported to the maintainer within the run that failed.

**Rationale**: The project exists to remove ongoing human toil and to avoid end-user/administrator
maintenance. Hands-off operation with reliable failure reporting is the core promise.

### V. Quality-Gated Delivery

An automated code-quality analysis MUST run over this repository's own authored artifacts (build and
monitor scripts, pipeline configuration) before any image is published, and a failed quality gate MUST
block publishing for that run. The gate MUST NOT be expected to analyze upstream UVdesk source, which
is fetched by release rather than authored here. There MUST be no path by which a failed gate results
in a published image.

**Rationale**: The gate protects the automation code we own — the only code whose quality we control —
and prevents low-quality or secret-leaking changes from producing images users would trust.

## Technology & Scope Constraints

- **In scope**: detecting upstream releases, building unmodified upstream releases into multi-
  architecture images, quality-gating this repo's own artifacts, tagging, and publishing.
- **Out of scope**: modifying/patching upstream UVdesk source, adding UVdesk application features,
  providing end-user application support, and hosting or operating a running UVdesk instance.
- **Architectures**: `linux/amd64` and `linux/arm64` are both required for every built release.
- **Registries**: images are published to all designated registries in the same run with identical
  tag sets; a failure to any one fails the run (see Principle II).
- **Infrastructure**: Jenkins provides pipeline execution and scheduling; SonarQube provides the
  quality gate. These are pre-existing, maintainer-operated systems, not provisioned by this project.
- **Known accepted trade-off**: upstream's build definition may use floating base images, so builds
  are not bit-reproducible over time; traceability is provided by version tags and image labels
  (Principle III) rather than by pinning, since pinning would require modifying upstream (Principle I).

## Development Workflow & Quality Gates

- Every change MUST keep the mechanical upstream-integrity guard (Principle I) passing.
- Automation scripts MUST pass linting (e.g., ShellCheck) and their unit tests before merge; the
  quality gate (Principle V) MUST pass before any publish.
- Changes affecting tagging, atomicity, or publishing MUST include or update tests that assert the
  all-or-nothing and `latest`-gating behaviors (Principles II, III).
- Image changes MUST be validated by a smoke test that boots the produced image on each required
  architecture and confirms it functions as the unmodified upstream release intends.
- Pull requests MUST verify compliance with these principles; any deviation MUST be justified in the
  PR description and, if it conflicts with a principle, MUST be resolved before merge rather than
  waived.

## Governance

This constitution supersedes other practices for this repository. It is authoritative for planning
(`/speckit-plan` Constitution Check), analysis (`/speckit-analyze`), and implementation review.

- **Amendments**: proposed via pull request that edits this file, states the rationale, and updates
  the version and Sync Impact Report. Amendments require maintainer approval before merge.
- **Versioning policy** (semantic):
  - MAJOR — backward-incompatible governance changes: removing or redefining a principle in a way that
    invalidates existing compliance.
  - MINOR — adding a new principle/section or materially expanding guidance.
  - PATCH — clarifications, wording, and non-semantic refinements.
- **Compliance review**: `/speckit-analyze` treats any conflict with a MUST principle here as a
  CRITICAL finding to be resolved (by adjusting spec/plan/tasks) before implementation. Principle
  changes themselves occur only through an explicit amendment to this file, never by reinterpretation
  during analysis.

**Version**: 1.1.0 | **Ratified**: 2026-07-20 | **Last Amended**: 2026-07-20
