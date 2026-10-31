# CA4 - Part 2 Alternative: Podman

The Part 2 stack (proxy, web, db) running on **Podman** instead of Docker, using the **same** `docker-compose.yml`, Dockerfiles and `.env` from [`CA4/part2`](../../part2/README.md). Only the container engine changes, which makes the comparison direct.

## Why Podman

- **Compatible with Docker:** it runs the same images (OCI) and builds the same Dockerfiles.
- **No daemon:** each container is a child process of the command that started it.
- **Rootless by default:** containers run as the normal user, inside a user namespace.

These are the differences this part tests against the Docker solution.

## Prerequisites

Ubuntu VM with Docker Compose already installed (from Part 2):

```bash
sudo apt install -y podman
podman --version                       # 5.7.0
systemctl --user enable --now podman.socket
podman login docker.io -u pbarbosa08   # paste a Docker Hub access token as password
```

`podman compose` does not implement Compose itself. It calls an external provider, here the `docker-compose` plugin, and points it to the Podman API socket (`podman.socket`) of the current user. Because the full Compose implementation is used, `depends_on: condition: service_healthy`, health checks, networks and volumes work without changing the file.

`podman-compose` (the Python tool) was not used, because its support for `depends_on` conditions is limited.

## Script

[`run-podman.sh`](run-podman.sh), run from the repository root:

```bash
bash CA4/alternative/part-2-alternative/run-podman.sh
```

| Step | What it does |
|---|---|
| 1 | enables the rootless Podman API socket |
| 2 | pulls the base images (`eclipse-temurin:17-jre`, `17-jdk`, `nginx:1.27-alpine`) with Podman |
| 3 | `podman compose -f CA4/part2/docker-compose.yml -p ca4-part2-podman up -d --build` |
| 4 | waits until the proxy answers `/books` |
| 5 | lists the containers and their health |
| 6 | end-to-end request through the proxy |

- **`PROXY_PORT=8081`:** exported by the script. Shell variables take priority over `.env`, so the Podman stack (port 8081) can run next to the Docker stack (port 8080).
- **`-p ca4-part2-podman`:** a separate project name, so containers, networks and the volume do not clash with the Docker ones.

<img width="923" height="181" alt="image" src="https://github.com/user-attachments/assets/8b8972d4-3ef3-432c-bb77-a914d4af0b18" />

<img width="923" height="181" alt="image" src="https://github.com/user-attachments/assets/7758821c-b8a3-412a-9744-a8f13ce3afad" />

To stop it:

```bash
podman compose -f CA4/part2/docker-compose.yml -p ca4-part2-podman down
```

## Requirements check

```bash
P="podman compose -f CA4/part2/docker-compose.yml -p ca4-part2-podman"
```

| Part 2 requirement | With Podman | Command |
|---|---|---|
| Three services | same compose file | `podman ps` |
| Name resolution between containers | Netavark + Aardvark DNS | `$P exec web getent hosts db`, `$P exec proxy nslookup web` |
| `db` health check before `web` | same health check, `service_healthy` respected | `podman inspect --format '{{.State.Health.Status}}' ca4-part2-podman-db-1` |
| `web` health check before `proxy` | same | idem for `web` |
| Volume for the database | named volume `ca4-part2-podman_h2-data` | POST a book, `down`, `up -d`, GET |
| Configuration by environment variables | same `.env`, with `PROXY_PORT` overridden | `$P config` |
| Images on Docker Hub | the same images; Podman can also push them | `podman push docker.io/pbarbosa08/cogsi-ca4-web:1.0` |

## Differences found compared with Docker

### Rootless and user namespaces

```bash
ps -o user,pid,cmd -C java
```

The Java processes run as the normal user (`pbarbosa`). With Docker they are children of `dockerd`, which runs as root.

```bash
V=$(podman volume inspect ca4-part2-podman_h2-data --format '{{.Mountpoint}}')
ls -ln "$V"
podman unshare ls -ln "$V"
```

- **Outside the namespace (`ls`):** the database file belongs to a high UID from the user's sub-UID range.
- **Inside (`podman unshare`):** it belongs to the `h2` user of the image.

The `h2` user of the container is not a real user on the host. Even if the container were compromised, the process would only have the rights of an unprivileged user.

<img width="923" height="150" alt="image" src="https://github.com/user-attachments/assets/e1ee1481-38ca-42ba-b744-b05310f1f058" />

### No daemon

There is no `dockerd`. The API socket only serves the Compose provider and is started on demand by systemd for the user. Health checks are run by systemd timers instead of a daemon.

### Build

The images are built by **Buildah**, not BuildKit:

- **`# syntax=docker/dockerfile:1`:** Buildah ignores the line, but supports the features used (`ADD --chmod`, `COPY --chmod`, multi-stage).
- **Bake warning:** Compose prints *"configured to build using Bake, but buildkit isn't enabled"*. It is only a warning, and the build continues.

### Registry credentials

Podman keeps its own credentials (`podman login`), separate from Docker's. Before logging in, Podman fell back to the credentials saved by `docker login`, and Docker Hub rejected them on some pulls (`incorrect username or password`). Logging in with an access token in Podman solved it.

### Short image names

Docker always assumes `docker.io`. Podman asks which registry to use for short names like `nginx`, unless the call enforces one. Through the Compose API, `docker.io` is enforced (*"to docker.io (enforced by caller)"*). On the command line, the full names (`docker.io/library/...`) were used.


## Requirements not covered

| Item | Status | Reason |
|---|---|---|
| Compose engine | depends on `docker-compose` | Podman uses Docker's Compose CLI as the provider. Only the CLI is used, not the Docker daemon. |
| Publishing | not repeated | the images are identical to the Docker ones and already on Docker Hub; `podman push` works with the same names |
| Port 80 on the host | not used | rootless containers cannot bind ports below 1024 by default; the stack uses 8081 |
