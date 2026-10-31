#!/bin/bash
# Part 2 with Podman: same docker-compose.yml and Dockerfiles as CA4/part2.
# Run from the repository root:  bash CA4/alternative/part-2-alternative/run-podman.sh
set -e

COMPOSE_FILE=CA4/part2/docker-compose.yml
PROJECT=ca4-part2-podman
# Different host port, so it can run next to the Docker stack (8080)
export PROXY_PORT=8081

echo "=== 1. Podman API socket (rootless) ==="
systemctl --user enable --now podman.socket

echo "=== 2. Build and start db, web and proxy ==="
podman compose -f "$COMPOSE_FILE" -p "$PROJECT" up -d --build

echo "=== 3. Waiting for the proxy (it only starts after web is healthy) ==="
for i in $(seq 1 30); do
  if curl -fs "http://localhost:${PROXY_PORT}/books" > /dev/null; then break; fi
  sleep 5
done

echo "=== 4. Containers and health ==="
podman ps --filter "label=com.docker.compose.project=$PROJECT" \
  --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo "=== 5. End-to-end request through the proxy ==="
curl -s "http://localhost:${PROXY_PORT}/books"; echo
