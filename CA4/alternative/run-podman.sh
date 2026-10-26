#!/bin/bash
set -e

echo "=== 1. Building Chat V3 with Podman (Rootless & Daemonless) ==="
podman build -f CA4/chat/Dockerfile.v3 -t podman-chat:v3 CA4/chat

echo "=== 2. Running Container ==="
podman run -d --name podman-chat-app -p 59002:59001 podman-chat:v3

echo "=== 3. Container Stats ==="
sleep 3
podman stats podman-chat-app --no-stream

echo "=== 4. Cleaning Up ==="
podman stop podman-chat-app && podman rm podman-chat-app
echo "Podman execution test completed successfully."
