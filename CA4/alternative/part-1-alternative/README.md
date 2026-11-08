# CA4 - Part 1 Alternative: Rootless & Daemonless Containers with Podman

## Overview & Pedagogical Objective

In **CA4 Part 1**, we containerized the Chat Server and Bookstore applications using the standard Docker engine. While Docker is the industry reference, it traditionally relies on a central background service running with root privileges (`dockerd`). If the daemon is compromised, the host can be exposed.

This tutorial explores **Podman** (Pod Manager) as an alternative container runtime. Podman implements the Open Container Initiative (OCI) specification, meaning it reuses the exact same `Dockerfile` configurations created in Part 1, but introduces two critical architectural security advantages:
1. **Daemonless Architecture:** No persistent background daemon. Podman forks directly from the user's shell using standard Linux process management (`fork`/`exec`), avoiding a single point of failure.
2. **Rootless by Default:** Containers run entirely within unprivileged user namespaces (`User Namespaces`), meaning a process running as UID 0 *inside* the container is mapped to an unprivileged UID *outside* on the host.

---

## 1. Technical Comparison: Docker vs. Podman

| Feature | Docker | Podman | Pedagogical / Security Impact |
| :--- | :--- | :--- | :--- |
| **Architecture** | Client-Server (Docker CLI talks to `dockerd` daemon) | Fork-Exec (Daemonless, processes run directly under the caller) | No central process running as root; avoids privilege escalation attack surfaces. |
| **Execution Mode** | Historically Rootful (Rootless requires dedicated daemon mode) | Rootless by default | Safe execution in multi-tenant environments and high-security clusters. |
| **CLI Compatibility** | `docker <command>` | `podman <command>` (OCI syntax drop-in replacement) | Zero friction: existing build instructions and syntax translate directly. |
| **System Integration** | Monitored by the daemon | Monitored directly via `systemd` or standard OS tools | Container lifecycles integrate natively into system unit services. |

---

## 2. Directory Structure & Script Architecture

The alternative implementation is organized as follows:

```
CA4/
├── alternative/
│   ├── part-1-alternative/
│   │   ├── README.md         # This comprehensive tutorial
│   │   └── run-podman.sh     # Automation and test script
│   └── part-2-alternative/
└── part1/
    ├── chat/
    │   └── Dockerfile.v3     # Reused OCI-compliant multi-stage specification
    └── bookstore/
        └── Dockerfile.v3
```

### Automation Script: `run-podman.sh`

The test script automates the complete lifecycle: building the OCI multi-stage artifact, instantiating the unprivileged container, querying resource statistics, and performing idempotent cleanup.

```bash
#!/bin/bash
set -e

echo "=== 1. Building Chat V3 with Podman (Rootless & Daemonless) ==="
podman build -f CA4/part1/chat/Dockerfile.v3 -t podman-chat:v3 CA4/part1/chat

echo "=== 2. Running Container ==="
podman run -d --name podman-chat-app -p 59002:59001 podman-chat:v3

echo "=== 3. Container Stats ==="
sleep 3
podman stats podman-chat-app --no-stream

echo "=== 4. Cleaning Up ==="
podman stop podman-chat-app && podman rm podman-chat-app
echo "Podman execution test completed successfully."
```

---

## 3. Step-by-Step Hands-On Tutorial

### Step 1: Install Podman Prerequisites (Ubuntu / Debian / WSL)

If Podman is not yet installed in your environment, execute:

```bash
sudo apt update
sudo apt install -y podman
podman --version
```

### Step 2: Build the Container Image

We reuse the secure `Dockerfile.v3` multi-stage specification created in Part 1. Run the build command from the repository root:

```bash
podman build -f CA4/part1/chat/Dockerfile.v3 -t podman-chat:v3 CA4/part1/chat
```

<img width="1270" height="261" alt="image" src="https://github.com/user-attachments/assets/b67d26c8-a99b-4ee4-a74d-19ae50d233d2" />


### Step 3: Run the Application in Rootless Mode

Launch the container exposing port `59002` mapped to internal port `59001`:

```bash
podman run -d --name podman-chat-app -p 59002:59001 podman-chat:v3
```

Verify that the container is active and review its state:

```bash
podman ps
```

<img width="1191" height="180" alt="image" src="https://github.com/user-attachments/assets/02bcdeef-ca31-42ef-ac77-ffa0e4f3d7cc" />


### Step 4: Validate Security and User Namespaces

Confirm that the application inside the container runs with the non-privileged service user (`appuser`, UID 10001) as configured in `Dockerfile.v3`:

```bash
# Verify process table
podman top podman-chat-app

# Inspect user ID resolution inside the container
podman run --rm podman-chat:v3 id
```

Expected output:
```text
uid=10001(appuser) gid=10001(appuser) groups=10001(appuser)
```

> **[INSERT SCREENSHOT HERE: podman top and podman run --rm id proving UID 10001 execution]**

### Step 5: Resource Consumption Analysis

Query the container's memory and CPU usage snapshot:

```bash
podman stats podman-chat-app --no-stream
```

> **[INSERT SCREENSHOT HERE: podman stats showing memory and CPU usage]**

### Step 6: Automated Test Execution

You can run the entire workflow end-to-end using the prepared script:

```bash
chmod +x CA4/alternative/part-1-alternative/run-podman.sh
./CA4/alternative/part-1-alternative/run-podman.sh
```

> **[INSERT SCREENSHOT HERE: Full execution output of run-podman.sh]**

---

## 4. Architectural Conclusions

1. **Drop-in Compatibility:** Podman successfully built and ran the exact same multi-stage `Dockerfile.v3` configured for Docker without requiring any alterations to the code or build logic.
2. **Defense in Depth:** Combining an unprivileged runtime user (`UID 10001`) with Podman's rootless user namespace architecture ensures that even in the event of an arbitrary code execution vulnerability, an attacker remains restricted to an unprivileged namespace on the host machine.
