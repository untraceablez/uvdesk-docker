# Contract: Published Image Interface

**Feature**: 001-automated-docker-builds | **Date**: 2026-07-20

This is the contract the **produced Docker image** exposes to end users. It is dictated by the *unmodified upstream* Dockerfile/entrypoint (FR-018) — we publish and document it, we do not define new behavior. Verified against `uvdesk/community-skeleton` v1.1.8.

## Image references

Published to **both** Docker Hub and GHCR with identical tags:

```text
docker.io/<namespace>/uvdesk:<X.Y.Z>        # multi-arch (amd64+arm64)
docker.io/<namespace>/uvdesk:latest         # multi-arch, newest eligible release
docker.io/<namespace>/uvdesk:<X.Y.Z>-amd64  # amd64 only
docker.io/<namespace>/uvdesk:<X.Y.Z>-arm64  # arm64 only
docker.io/<namespace>/uvdesk:x64            # amd64 only (friendly alias)
docker.io/<namespace>/uvdesk:arm64          # arm64 only (friendly alias)
```

…and the same six tag names under `ghcr.io/<owner>/uvdesk:*`. The exact `<namespace>`/`<owner>` are Jenkins configuration values, not fixed by this contract.

## Supported platforms

| Platform | Support |
|---|---|
| `linux/amd64` | Yes |
| `linux/arm64` | Yes |

A `docker pull` of a shared tag on either platform returns the natively-matching image (FR-008).

## Environment variables (consumed by the upstream entrypoint)

When **all four** are provided, the entrypoint auto-creates the database + user and configures credentials on first start; the operator then completes the UVdesk web installer in the browser (FR-019).

| Variable | Required for auto-setup | Purpose |
|---|---|---|
| `MYSQL_ROOT_PASSWORD` | yes | Sets the in-image MySQL root password |
| `MYSQL_DATABASE` | yes | Database created if absent |
| `MYSQL_USER` | yes | Application DB user (granted all privileges on `MYSQL_DATABASE`) |
| `MYSQL_PASSWORD` | yes | Password for `MYSQL_USER` |

If any are omitted, the entrypoint skips auto-setup and the operator must configure MySQL manually (upstream fallback path).

## Ports

| Container port | Service | Notes |
|---|---|---|
| `80` | Apache (UVdesk web UI + installer) | Map to a host port, e.g. `-p 8080:80`. Upstream does not `EXPOSE` it explicitly; documented here for users. |

MySQL runs inside the same container (all-in-one image) and is not required to be published externally for normal use.

## Persistence volumes

For a persistent container, mount:

| Container path | Holds |
|---|---|
| `/var/lib/mysql` | MySQL data |
| `/var/www/uvdesk` | Application (includes config + uploads) |

Configuration-only persistence may instead mount `/var/www/uvdesk/config`. Exact volume guidance mirrors the upstream Docker-Persistent-Container wiki.

## First-run behavior (informative)

On container start the upstream entrypoint: restarts Apache + MySQL → (if `MYSQL_*` present) pings MySQL, `CREATE DATABASE IF NOT EXISTS`, grants privileges, sets root credentials, writes `my.cnf` → drops to the non-root `uvdesk` user via gosu. The UVdesk **web installer** at `http://<host>:<port>/` is then completed interactively (admin account, mail, final config).

## Traceability labels

Each image carries labels recording the upstream version/tag, upstream commit ref, and build timestamp so any published image maps back to its exact upstream release (FR-015).
