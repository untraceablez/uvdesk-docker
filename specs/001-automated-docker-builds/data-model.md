# Phase 1 Data Model: Automated Multi-Arch UVdesk Docker Builds

**Feature**: 001-automated-docker-builds | **Date**: 2026-07-20

This feature has no application database. The "data model" here describes the **conceptual entities the pipeline reasons about** — most are derived at runtime from external systems (GitHub Releases API, container registries) rather than persisted by us. Fields marked *(derived)* are read from an external source each run.

---

## Entity: UpstreamRelease

Represents one published release of `uvdesk/community-skeleton`.

| Field | Type | Source | Notes |
|---|---|---|---|
| `tag_name` | string (e.g. `v1.1.8`) | GitHub API *(derived)* | Raw upstream tag |
| `version` | semver (e.g. `1.1.8`) | computed | `tag_name` with leading `v` stripped; used for image tags |
| `draft` | bool | GitHub API *(derived)* | Must be `false` to be eligible |
| `prerelease` | bool | GitHub API *(derived)* | Must be `false` to be eligible |
| `published_at` | timestamp | GitHub API *(derived)* | Used to order releases |
| `tarball_url` | url | GitHub API *(derived)* | Source archive to build from |

**Eligibility rule (FR-002)**: a release is a "latest" candidate iff `draft == false AND prerelease == false`. The eligible release with the newest `published_at` is the build target (FR-001).

**Validation**:
- `version` MUST match `^\d+\.\d+\.\d+$` after stripping `v`; a non-semver tag is skipped and reported.
- `tarball_url` MUST be fetchable and extract to a tree containing a `Dockerfile` at its root; otherwise the run fails cleanly (edge case: malformed archive).

---

## Entity: BuiltImage

A single-architecture image produced from one `UpstreamRelease`.

| Field | Type | Notes |
|---|---|---|
| `upstream_version` | semver | Links back to `UpstreamRelease.version` (FR-015) |
| `architecture` | enum `amd64` \| `arm64` | The two required platforms (FR-004) |
| `digest` | string (sha256) | Content digest after build/push |
| `build_timestamp` | timestamp | Recorded as an image label |
| `upstream_ref_label` | string | Image label capturing upstream tag + commit for traceability (FR-015) |

**State**: a `BuiltImage` only exists once its architecture's build has succeeded. Per FR-013, `BuiltImage` records for a version are only ever published as a **complete pair** (both architectures) — a lone member is never published.

---

## Entity: Tag

A human-facing pointer published to a registry.

| Field | Type | Notes |
|---|---|---|
| `name` | string | One of the four families below |
| `kind` | enum `shared-multiarch` \| `arch-pinned` | Determines manifest type |
| `target` | manifest-list \| single-arch manifest | What the tag resolves to |
| `registry` | enum `dockerhub` \| `ghcr` | Same tag set exists on both (FR-016) |

**Tag families (per version `X.Y.Z`)**:

| Tag | kind | Resolves to |
|---|---|---|
| `X.Y.Z` | shared-multiarch | manifest list → native arch |
| `latest` | shared-multiarch | manifest list of the newest eligible version → native arch |
| `X.Y.Z-amd64`, `x64` | arch-pinned | amd64 image |
| `X.Y.Z-arm64`, `arm64` | arch-pinned | arm64 image |

**Invariants**:
- `latest` points to the same digests as the highest published `X.Y.Z` (FR-006).
- Every tag family for a version exists on **both** registries or on neither (FR-013 + FR-016).
- Arch-pinned tags exist only when the shared multi-arch tags for the same version exist (derived after the atomic build).

---

## Entity: BuildDecision *(derived, not persisted)*

The per-run determination of what to do, computed by `check-release.sh`.

| Field | Type | Notes |
|---|---|---|
| `target_version` | semver | The eligible release under consideration |
| `already_published` | bool | True iff `target_version` manifest exists on **both** registries |
| `force_rebuild` | bool | Jenkins `FORCE_REBUILD` parameter (FR-011) |
| `is_newest` | bool | True iff `target_version` == the newest eligible release; gates whether `latest` advances (FR-006/011) |
| `action` | enum `build` \| `skip` | `skip` iff `already_published AND NOT force_rebuild` (FR-010) |

**Source of truth**: the registries themselves (D5). There is no separate persisted build-state store.

---

## Entity: PipelineRun *(ephemeral)*

One Jenkins execution.

| Field | Type | Notes |
|---|---|---|
| `trigger` | enum `poll` \| `manual` | Scheduled poll (FR-009) or manual (FR-011) |
| `version` | semver | Resolved target (from poll) or supplied parameter (manual) |
| `quality_gate` | enum `passed` \| `failed` \| `skipped` | SonarQube outcome; `failed` ⇒ no publish (FR-012) |
| `outcome` | enum `published` \| `skipped` \| `failed` | Terminal status |
| `notified` | bool | Whether a maintainer notification was emitted (FR-014) |

**State transitions**:

```text
poll/manual → resolve version → BuildDecision
   ├─ action=skip  ─────────────────────────────► outcome=skipped
   └─ action=build → quality_gate
        ├─ failed ──────────► notify ───────────► outcome=failed
        └─ passed → buildx (both arches, atomic)
             ├─ any arch or either-registry push fails → notify → outcome=failed
             └─ success → derive arch-pinned tags ────► outcome=published
```

---

## Relationships

```text
UpstreamRelease 1 ──produces──► 2 BuiltImage (amd64, arm64)   [only as a complete pair]
BuiltImage      * ──referenced by──► Tag                       [shared + arch-pinned]
Tag             * ──published to──► 2 registries               [dockerhub, ghcr — lockstep]
PipelineRun     1 ──evaluates──► 1 BuildDecision ──drives──► 0..* Tag
```

No entity is stored by this feature; all state is read from GitHub and the registries at run time.
