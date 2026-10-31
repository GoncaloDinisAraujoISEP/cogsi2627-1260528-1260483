# CA4 - Containerization with Docker

Containers for the CA1 applications (chat and Bookstore), built and run with Docker, and the same goals implemented with **Podman** as the alternative solution.

## Contents

| Part | Topic | Report |
|---|---|---|
| Part 1 | Docker images for the chat and the Bookstore: three build strategies, `.dockerignore`, `docker history`, resource monitoring, non-root user, Docker Hub | [part1/README.md](part1/README.md) |
| Part 2 | Bookstore with Docker Compose: proxy, web and db containers, health checks, volume, environment variables, Docker Hub | [part2/README.md](part2/README.md) |
| Alternative, Part 1 | Building and running the chat image with Podman | [alternative/part-1-alternative/README.md](alternative/part-1-alternative/README.md) |
| Alternative, Part 2 | The Part 2 Compose stack with rootless Podman | [alternative/part-2-alternative/README.md](alternative/part-2-alternative/README.md) |

## Repository layout

```
CA4/
├── README.md                   # this index
├── part1/                      # Part 1: chat and Bookstore images
├── part2/                      # Part 2: Docker Compose (proxy, web, db)
└── alternative/
    ├── part-1-alternative/     # Podman, Part 1
    └── part-2-alternative/     # Podman, Part 2
```

## Tags

| Tag | Content |
|---|---|
| `ca4-part1` | end of Part 1 |
| `ca4-part2` | end of Part 2, including the alternative |

## Self-assessment

| Student | Number | Contribution |
|---|---|---|
| Gonçalo Dinis Araújo | 1260528 | 50% |
| Pedro Barbosa | 1260483 | 50% |
