# Usage Guide

Two audiences: **end users** who pull and run the published image, and **maintainers** who operate the
Jenkins pipeline. See the source spec in
[`specs/001-automated-docker-builds/`](../specs/001-automated-docker-builds/) for full detail.

---

## For end users — running a published image

Images are published to both Docker Hub (`docker.io/<ns>/uvdesk`) and GHCR (`ghcr.io/<owner>/uvdesk`).

### Tags

| Tag | Resolves to |
|---|---|
| `X.Y.Z` | multi-arch — native to your host (amd64/arm64) |
| `latest` | newest released version, native to your host |
| `X.Y.Z-amd64`, `x64` | amd64 explicitly |
| `X.Y.Z-arm64`, `arm64` | arm64 explicitly |

### Environment variables

Provide all four to have the database provisioned automatically on first start (the container's
upstream entrypoint creates the database + user and grants privileges — no manual SQL needed):

| Variable | Purpose |
|---|---|
| `MYSQL_ROOT_PASSWORD` | in-image MySQL root password |
| `MYSQL_DATABASE` | database created if absent |
| `MYSQL_USER` | application DB user (granted on `MYSQL_DATABASE`) |
| `MYSQL_PASSWORD` | password for `MYSQL_USER` |

If you omit them, you must configure MySQL manually inside the container (upstream fallback).

### Ports & volumes

- Container port **80** serves the UVdesk web UI and installer — map it, e.g. `-p 8080:80`.
- Persist with volumes: `/var/lib/mysql` (database) and `/var/www/uvdesk` (application). MySQL runs
  inside the same container (all-in-one image).

### Run

```sh
docker run -d --name uvdesk -p 8080:80 \
  -e MYSQL_ROOT_PASSWORD=rootpw -e MYSQL_DATABASE=uvdesk \
  -e MYSQL_USER=uvdesk -e MYSQL_PASSWORD=uvdeskpw \
  -v uvdesk_db:/var/lib/mysql -v uvdesk_app:/var/www/uvdesk \
  <ns>/uvdesk:latest
```

Then open `http://localhost:8080/` and complete the **UVdesk web installer** (admin account, mail,
final configuration). The installer step is interactive by design.

---

## For maintainers — Jenkins setup

### Agent prerequisites

- Docker Engine with the Buildx plugin.
- QEMU/binfmt for cross-arch emulation (the pipeline registers it, or run once:
  `docker run --privileged --rm tonistiigi/binfmt --install all`).
- `curl`, `jq`, `shellcheck`, `sonar-scanner` on the agent.
- SonarQube server reachable, with a webhook back to Jenkins so `waitForQualityGate` resolves.

### Credentials (Jenkins credential IDs referenced by the `Jenkinsfile`)

| ID | Type | Purpose |
|---|---|---|
| `dockerhub-token` | username + password/token | push to Docker Hub |
| `ghcr-token` | username + PAT | push to GHCR |
| `sonarqube-token` | secret text | SonarQube auth |
| `github-token` | secret text | raises GitHub API rate limit (optional) |

### Configuration values (Jenkins env / folder properties)

| Key | Purpose |
|---|---|
| `DOCKERHUB_NAMESPACE`, `GHCR_OWNER` | image namespaces |
| `IMAGE_NAME` | image name (default `uvdesk`) |
| `SONAR_HOST_URL` | SonarQube server URL |
| `POLL_SCHEDULE` | cron for the poll trigger (default `H * * * *`) |
| `NOTIFY_EMAIL` | maintainer failure recipient |
| `NOTIFY_WEBHOOK_URL` | optional chat webhook |

Also configure a SonarQube server named `SonarQube` in **Manage Jenkins → System** so
`withSonarQubeEnv('SonarQube')` resolves.

### Triggers & parameters

- **Automatic**: the cron poll builds any new eligible upstream release with no manual action.
- **Manual** ("Build with Parameters"):
  - `VERSION` — target an exact upstream version (empty = newest eligible).
  - `FORCE_REBUILD` — rebuild/republish even if already published on both registries.

### Manual invocation from a shell (outside Jenkins)

```sh
export DOCKERHUB_NAMESPACE=... GHCR_OWNER=... SONAR_HOST_URL=... SONAR_TOKEN=...
scripts/check-release.sh            # decide build/skip; writes .work/decision.env
scripts/fetch-source.sh 1.1.8       # extract upstream; writes .work/build.env
scripts/build-and-push.sh           # atomic multi-arch build + publish
```

---

## Operational guarantees

- **All-or-nothing publishing**: a version is published for both architectures and both registries, or
  not at all. A failed architecture or registry push publishes nothing for that version.
- **`latest` gating**: `latest` advances only for the newest eligible release. A manual/forced build of
  an older version publishes that version's own tags but never moves `latest`.
- **Non-destructive history**: previously published version tags are **never deleted** by the pipeline.
  Old versions remain pullable indefinitely.
- **Concurrency safety**: the pipeline uses `disableConcurrentBuilds()`, so overlapping poll cycles are
  serialized and cannot race to corrupt published tags. An already-published version is skipped
  (idempotent) rather than rebuilt, unless `FORCE_REBUILD` is set.
- **Failure visibility**: any build, quality-gate, or publish failure notifies the maintainer within
  the same run (email and/or webhook).
