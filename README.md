# uvdesk-docker

Automated, multi-architecture Docker image builds of
[`uvdesk/community-skeleton`](https://github.com/uvdesk/community-skeleton), driven by Jenkins with a
SonarQube quality gate.

This repository is a **packaging and automation layer only**. It monitors upstream UVdesk releases and,
for each new eligible release, builds the **unmodified upstream release** into `linux/amd64` and
`linux/arm64` images and publishes them to Docker Hub and GitHub Container Registry (GHCR) with
`latest`, exact-version, and architecture-pinned tags.

> **It never modifies, patches, or forks upstream UVdesk code.** There is deliberately no `Dockerfile`
> in this repo — builds run against the upstream release's own Dockerfile. See
> [`.specify/memory/constitution.md`](.specify/memory/constitution.md), Principle I.

## How it works

```
 (cron poll) → Resolve release → Quality gate → Fetch source → Build (amd64+arm64) → Publish → [notify on failure]
                newest, non-draft   SonarQube      upstream       single atomic buildx   Docker Hub + GHCR
                non-prerelease;      over THIS      tarball,       invocation; all-or-    identical tag sets;
                skip if already      repo's code    unmodified     nothing across arches  latest only if newest
                published on both    blocks publish
```

- **Detection** — Jenkins polls the upstream Releases API; only stable (non-draft, non-prerelease)
  releases are eligible. Already-published versions (present on both registries) are skipped.
- **Quality gate** — SonarQube analyzes this repo's own scripts/pipeline (never upstream source); a
  failing gate blocks the build.
- **Build** — a single `docker buildx` invocation builds both architectures from the upstream
  Dockerfile. If either architecture fails, nothing is published (all-or-nothing).
- **Publish** — identical tag sets go to Docker Hub and GHCR; `latest` advances only for the newest
  eligible release.

## Published tags

For an upstream version `X.Y.Z`, on both `docker.io/<ns>/uvdesk` and `ghcr.io/<owner>/uvdesk`:

| Tag | Type | Resolves to |
|---|---|---|
| `X.Y.Z` | multi-arch | native arch for the puller |
| `latest` | multi-arch | newest eligible release, native arch |
| `X.Y.Z-amd64`, `x64` | arch-pinned | amd64 |
| `X.Y.Z-arm64`, `arm64` | arch-pinned | arm64 |

## Running a published image

See [`docs/usage.md`](docs/usage.md) for the full end-user guide (environment variables, ports,
persistence volumes) and the maintainer/Jenkins setup guide.

Quick start:

```sh
docker run -d --name uvdesk -p 8080:80 \
  -e MYSQL_ROOT_PASSWORD=rootpw -e MYSQL_DATABASE=uvdesk \
  -e MYSQL_USER=uvdesk -e MYSQL_PASSWORD=uvdeskpw \
  -v uvdesk_db:/var/lib/mysql -v uvdesk_app:/var/www/uvdesk \
  <ns>/uvdesk:latest
# then open http://localhost:8080/ and complete the UVdesk web installer
```

## Repository layout

```
Jenkinsfile                 # pipeline: poll → gate → fetch → build → publish → notify
sonar-project.properties    # SonarQube scope (this repo's artifacts only)
scripts/
├── check-release.sh        # resolve newest eligible release + build/skip decision
├── fetch-source.sh         # download + extract the upstream release tarball
├── build-and-push.sh       # atomic multi-arch build + tag + push to both registries
├── quality-gate.sh         # ShellCheck → SonarQube generic issues + scanner
├── notify.sh               # maintainer failure notifications
└── lib/
    ├── common.sh                     # shared helpers + tag computation
    └── assert-unmodified-upstream.sh # mechanical FR-018 / Principle I guard
tests/                      # bats unit tests + smoke test
docs/usage.md               # end-user + maintainer guide
specs/                      # Spec Kit feature docs (spec, plan, tasks, contracts)
```

## Development

```sh
make lint    # ShellCheck over scripts/**
make test    # bats unit tests
make check   # lint + test
```

## Design & governance

- Feature spec, plan, and tasks: [`specs/001-automated-docker-builds/`](specs/001-automated-docker-builds/)
- Project constitution (the non-negotiable principles): [`.specify/memory/constitution.md`](.specify/memory/constitution.md)
