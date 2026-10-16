# docker.sh — Docker CE + Cockpit Web Console Integration

> **Companion script to `init.sh`.**
> Installs Docker CE and seamlessly connects container management into Cockpit Web Console — with zero manual steps.

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [What Gets Installed](#-what-gets-installed)
- [How It Integrates with init.sh](#-how-it-integrates-with-initsh)
- [Full Architecture](#-full-architecture)
- [Feature Breakdown](#-feature-breakdown-all-13-steps)
- [Cockpit Container Management](#-cockpit-container-management)
- [Docker Quick Reference](#-docker-quick-reference)
- [Troubleshooting](#-troubleshooting)
- [FAQ](#-faq)

---

## 🔍 Overview

`docker.sh` provides production Docker setup and modern zero-overhead host integration:

**Part 1 — Docker CE Installation**
Installs the latest stable Docker CE from Docker's official APT repository, along with Compose v2, BuildKit, containerd, ctop, Lazydocker, and Docker Scout.

**Part 2 — Zero-Overhead Management Integration**
- **Cockpit UI Integration:** Enables container management directly inside the Cockpit Web Console. View running containers, inspect logs, monitor live CPU/RAM usage per container, and start/stop/restart containers from a browser (0 MB idle RAM via systemd socket activation).
- **Ecosystem Monitoring Tools:** Includes terminal-based real-time monitors (`ctop`, `lazydocker`) and native daemon metrics on `:9323`.

```
init.sh installed:               docker.sh adds:
  Cockpit Web Console :9090  ←     Cockpit Container Management (cockpit-podman)
  Node.js PM2 GUI Extension        Native Docker Engine metrics (:9323)
  (0 MB idle RAM)                  Optional: cAdvisor (:8080 via --with-cadvisor)
```

---

## Prerequisites

`docker.sh` is designed to run **after** `init.sh`. The following components are integrated if present:

| Component | Installed By | Path / Port | Role |
|---|---|---|---|
| Ubuntu 20.04 / 22.04 / 24.04 | — | — | Target OS |
| Cockpit | `init.sh` | `:9090` | Web Console & container GUI (0 MB idle) |
| Deploy user | `init.sh` | `/home/<username>` | Added to `docker` group |

> If Cockpit is not detected, `docker.sh` installs Docker CE normally and enables native engine metrics on `:9323`.

---

## ⚡ Quick Start

```bash
# Run everything (recommended)
sudo ./docker.sh

# Specify the deploy user explicitly
sudo ./docker.sh -u mojahid

# Skip monitoring integration (Docker only)
sudo ./docker.sh --no-mon

# Show help
sudo ./docker.sh -h
```

**After the script completes:**

```bash
# Apply docker group without re-logging in
newgrp docker

# Verify Docker works without sudo
docker ps

# Access Cockpit container GUI:
ssh -L 9090:127.0.0.1:9090 <username>@<server-ip>
# Open https://localhost:9090 → Containers
```

---

## 📦 What Gets Installed

### 🐳 Docker CE Stack

| Component | Description |
|---|---|
| `docker-ce` | Docker Community Edition engine |
| `docker-ce-cli` | `docker` CLI client |
| `containerd.io` | OCI-compliant container runtime |
| `docker-buildx-plugin` | BuildKit-powered multi-platform builder |
| `docker-compose-plugin` | Compose v2 — `docker compose` (integrated) |

### 🔧 Ecosystem Tools

| Tool | Purpose | Command |
|---|---|---|
| **ctop** | Live container resource monitor (like `htop`) | `ctop` |
| **Lazydocker** | Full interactive TUI for Docker | `lazydocker` |
| **Docker Scout** | Vulnerability scanner for images | `docker scout quickview <img>` |
| **Bash completion** | Tab-complete all `docker` subcommands | auto |

### 📊 Monitoring & Management Components

| Component | Port | Role |
|---|---|---|
| `cockpit-podman` | `127.0.0.1:9090` | Cockpit Web UI container manager (0 MB idle RAM) |
| `cadvisor` (Optional) | `127.0.0.1:8080` | Optional per-container metrics (`--with-cadvisor`) |
| `docker_engine` | `127.0.0.1:9323` | Native Docker daemon Prometheus metrics |

---

## 🔗 How It Integrates with init.sh

| init.sh Component | docker.sh Behavior |
|---|---|
| Cockpit (`:9090`) | **Extended.** Enables the Containers tab in Cockpit Web Console. |
| Deploy user | **Extended.** Added to `docker` group so they can run Docker without `sudo`. |
| `server_status` | **Integrated.** Running containers are automatically displayed in the status output. |

---

## 🏗️ Full Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                         Your Ubuntu Server                         │
│                                                                    │
│  ┌──── HOST & APPLICATION MANAGEMENT (Cockpit Web Console) ───┐   │
│  │                                                             │   │
│  │  Cockpit Socket :9090 (0 MB Idle RAM)                       │   │
│  │  ├── Host Overview: Real-time CPU, RAM, Disk I/O, Network   │   │
│  │  ├── Node.js (PM2): Process table, actions & live logs      │   │
│  │  ├── Containers Tab: Inspect, logs, start/stop/restart      │   │
│  │  ├── Systemd Services & Journald Log Search                 │   │
│  │  └── Interactive Root Web Terminal                          │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  ┌──── TERMINAL & CLI ECOSYSTEM ──────────────────────────────┐   │
│  │                                                             │   │
│  │  • ctop       — Live container top-like monitor             │   │
│  │  • lazydocker — Full terminal interactive Docker manager    │   │
│  │  • server_status — CLI server health overview               │   │
│  │                                                             │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## 🔬 Feature Breakdown (All 13 Steps)

| Step | Name | Detail |
|---|---|---|
| 01 | Preflight | Checks root, OS, detects deploy user, verifies Cockpit from `init.sh` |
| 02 | Remove old packages | Purges `docker.io`, `docker-engine`, `podman-docker`, etc. Upgrades if already installed. |
| 03 | Prerequisites | Installs `curl`, `gnupg`, `jq`, `lsb-release`, `bash-completion` |
| 04 | Docker APT repo | Adds official `download.docker.com` signed repo with GPG key in `/etc/apt/keyrings/` |
| 05 | Docker CE install | `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin` |
| 06 | daemon.json | Writes production-optimized config: BuildKit, log rotation, overlay2, live-restore, metrics (:9323) |
| 07 | Docker group | `usermod -aG docker <deploy_user>` — no more `sudo docker` |
| 08 | Ecosystem tools | ctop, Lazydocker, Docker Scout, bash completion |
| 09 | Cockpit integration | Installs `cockpit-podman` to surface container management in Cockpit Web Console |
| 10 | cAdvisor (Optional) | Deploys container bound to `127.0.0.1:8080` when requested |
| 11 | Scrape config patch | Checks for scrape targets if TSDB is present |
| 12 | Verify | Smoke test (`hello-world`), endpoint and systemd checks for all components |
| 13 | Summary | Full reference card with commands, Docker commands, and SSH tunnel instructions |

---

## 🖥️ Cockpit Container Management

When `docker.sh` completes, container management is integrated directly into the Cockpit Web Console.

Access Cockpit via SSH tunnel:
```bash
ssh -L 9090:127.0.0.1:9090 deploy_user@<server-ip>
# Open https://localhost:9090 → Containers
```

### Key Capabilities in Cockpit UI:
- **Interactive Container Dashboard:** View running and stopped containers with live CPU % and memory consumption.
- **Service Lifecycle:** Start, stop, restart, pause, or force-kill containers with a single click.
- **Log Viewer:** Inspect container stdout/stderr logs live with search and scrollback, eliminating terminal scrolling.
- **Resource Limits:** Inspect container memory limits, port bindings, and environment variables.
- **Web Terminal:** Shell directly into host or containers.

---

## 📈 PromQL / MetricsQL — Docker Metrics in VictoriaMetrics (VMUI)

Access the VictoriaMetrics visual explorer:
```bash
ssh -L 8428:localhost:8428 deploy_user@<server-ip>
# Open http://localhost:8428/vmui
```

### Container State (Docker Engine)

```promql
# Running containers count
engine_daemon_container_states_containers{state="running"}

# All container states
engine_daemon_container_states_containers
```

### Per-Container CPU (cAdvisor)

```promql
# CPU usage % per container (last 5 min)
rate(container_cpu_usage_seconds_total{name!=""}[5m]) * 100

# Top 5 CPU consumers
topk(5, rate(container_cpu_usage_seconds_total{name!=""}[5m]) * 100)

# CPU for one compose service
rate(container_cpu_usage_seconds_total{compose_service="api"}[5m]) * 100
```

### Per-Container Memory (cAdvisor)

```promql
# Working set memory per container (MB)
container_memory_working_set_bytes{name!=""} / 1024 / 1024

# Memory usage % of configured limit
container_memory_working_set_bytes{name!=""}
  / container_spec_memory_limit_bytes{name!=""} * 100

# Containers using more than 80% of their memory limit
container_memory_working_set_bytes
  / container_spec_memory_limit_bytes > 0.80
```

### Network (cAdvisor)

```promql
# Inbound network Mbps per container
rate(container_network_receive_bytes_total{name!=""}[5m]) / 1024 / 1024

# Outbound network Mbps per container
rate(container_network_transmit_bytes_total{name!=""}[5m]) / 1024 / 1024
```

### OOM Events

```promql
# Containers that were OOM killed
increase(container_oom_events_total[1h]) > 0
```

---

## 🐳 Docker Quick Reference

### Containers

```bash
docker ps                            # list running containers
docker ps -a                         # all containers (inc. stopped)
docker start <name>                  # start a stopped container
docker stop <name>                   # gracefully stop
docker restart <name>                # restart
docker rm <name>                     # remove stopped container
docker rm -f <name>                  # force remove running container
docker logs -f <name>                # follow live logs
docker logs --tail 200 <name>        # last 200 log lines
docker exec -it <name> bash          # shell into running container
docker inspect <name>                # full container JSON details
docker stats                         # live CPU/RAM all containers
docker top <name>                    # processes inside container
```

### Images

```bash
docker images                        # list local images
docker pull node:20-alpine           # pull specific image
docker build -t myapp:1.0 .          # build from Dockerfile
docker buildx build --platform \     # multi-arch build
  linux/amd64,linux/arm64 \
  -t myapp:1.0 --push .
docker rmi <image>                   # remove image
docker image prune -a                # remove all unused images
docker scout quickview <image>       # CVE vulnerability scan
docker scout cves <image>            # full CVE report
```

### Compose v2

```bash
docker compose up -d                 # start all services (detached)
docker compose down                  # stop + remove containers
docker compose ps                    # list services + status
docker compose logs -f               # follow all service logs
docker compose logs -f api           # follow one service
docker compose exec api bash         # shell into service
docker compose build --no-cache      # rebuild images
docker compose pull                  # pull latest images
docker compose restart api           # restart one service
```

### Maintenance

```bash
docker system df                     # disk usage breakdown
docker system prune -af              # remove all unused (images/containers/volumes)
docker volume prune                  # remove unused volumes
docker network prune                 # remove unused networks
docker builder prune                 # clear BuildKit layer cache
```

### Monitoring Containers (docker.sh stack)

```bash
docker ps -f name=cadvisor           # check cAdvisor
docker logs cadvisor --tail 20       # cAdvisor logs
```

---

## ✅ Pros & Cons

### ✅ Pros

| # | Pro | Detail |
|---|---|---|
| 1 | **init.sh-aware** | Integrates cleanly with Cockpit and VictoriaMetrics from `init.sh` |
| 2 | **Zero-overhead GUI** | Cockpit uses systemd socket activation — 0 MB idle RAM for web UI |
| 3 | **Docker CLI & TUI Ecosystem** | Includes ctop, Lazydocker, and BuildKit pre-configured |
| 4 | **Same visual style as init.sh** | Identical colors, section headers, box borders — looks like one suite |
| 5 | **Standard SSH tunnels** | Cockpit (`:9090`) bound safely to localhost (`127.0.0.1`) |
| 6 | **Idempotent** | Safe to re-run — detects existing installs and upgrades cleanly |
| 7 | **BuildKit on by default** | Faster, parallel, layer-cached builds without extra flags |
| 8 | **Log rotation built-in** | daemon.json caps container logs at 20MB × 5 files — disk won't fill |
| 9 | **Live-restore enabled** | Containers survive Docker daemon restarts/upgrades |
| 10 | **Native systemd logs** | Container logs available in Cockpit and journald without heavy agents |
| 11 | **cAdvisor labels compose** | `compose_project` and `compose_service` labels promoted to metrics |
| 12 | **Graceful optional failures** | ctop/Lazydocker/Scout failures emit warnings, never block Docker install |
| 13 | **Zero idle footprint** | Cockpit uses 0 MB idle RAM via socket activation, eliminating continuous background monitoring daemons |
| 14 | **Smoke tested** | `hello-world` container run at end confirms full Docker stack works |
| 15 | **Comprehensive summary** | Summary card includes Docker commands and SSH tunnel instructions |

---

### ❌ Cons

| # | Con | Detail |
|---|---|---|
| 1 | **Requires init.sh first** | Integrates with deploy user and Cockpit Web Console created by `init.sh` |
| 2 | **Ubuntu/Debian only** | No support for CentOS, Fedora, RHEL, Arch, or Alpine |
| 3 | **Overwrites daemon.json** | Existing `/etc/docker/daemon.json` is replaced (backup is saved) |
| 4 | **No version pinning** | Installs latest stable Docker at runtime — not reproducible for locked CI/CD |
| 5 | **cAdvisor needs privileged** | Runs as `--privileged` container — necessary for host filesystem metrics |
| 6 | **curl-pipe-bash for tools** | Lazydocker install uses `curl \| bash` — review before trusting in hardened envs |
| 7 | **No Swarm / Kubernetes** | Standalone Docker CE only — no orchestration layer setup |
| 8 | **No ARM full test** | cAdvisor + node tooling works on `arm64`, but Scout CLI may differ |
| 9 | **docker group = effective root** | Any user in the `docker` group can mount host filesystems — trusted users only |
| 10 | **Internet required** | All images and tools fetched at runtime — no air-gap/offline support |

---

## 🔧 Troubleshooting

### Docker daemon won't start

```bash
sudo journalctl -xu docker --no-pager | tail -30
sudo cat /etc/docker/daemon.json | python3 -m json.tool   # validate JSON
```

### Permission denied running docker

```bash
groups $USER                    # check group membership
newgrp docker                   # apply without logout
id $USER                        # verify docker group listed
```

### cAdvisor not collecting metrics

```bash
docker logs cadvisor --tail 30
curl http://127.0.0.1:8080/metrics | grep container_cpu | head -5
docker inspect cadvisor | grep -A5 Privileged
```

### VictoriaMetrics not scraping Docker targets

```bash
# Check target status in VictoriaMetrics
curl -s http://127.0.0.1:8428/api/v1/targets | python3 -m json.tool | grep -A5 docker

# Check scrape configuration
cat /etc/victoriametrics/scrape.yml

# Reload VictoriaMetrics
sudo systemctl restart victoriametrics
```

### Cockpit Containers page empty

```bash
# Verify cockpit and cockpit-podman
sudo systemctl status cockpit.socket
sudo apt-get install -y cockpit-podman
```

### Port already in use

```bash
sudo ss -tulpn | grep -E '8080|9323|9090|8428'
docker ps -a                         # check for stopped containers holding ports
docker rm -f cadvisor                # force remove, then re-run docker.sh
```

---

## 🗑️ Uninstall / Cleanup

### Remove Docker monitoring container

```bash
docker rm -f cadvisor
```

### Restore VictoriaMetrics scrape config

```bash
# Find the backup created by docker.sh
ls /etc/victoriametrics/scrape.yml.bak.*

# Restore
sudo cp /etc/victoriametrics/scrape.yml.bak.<timestamp> /etc/victoriametrics/scrape.yml
sudo systemctl restart victoriametrics
```

### Remove Docker CE completely

```bash
sudo systemctl stop docker containerd
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker
sudo rm -f  /etc/apt/sources.list.d/docker.list
sudo rm -f  /etc/apt/keyrings/docker.gpg
```

### Remove ecosystem tools

```bash
sudo rm -f /usr/local/bin/ctop
sudo rm -f /usr/local/bin/docker-scout
sudo rm -f /etc/bash_completion.d/docker
rm  -f ~/.local/bin/lazydocker
```

---

## ❓ FAQ

**Q: Can I run docker.sh without running init.sh first?**
Yes. Docker CE will install normally. The monitoring integration steps will be skipped with clear warnings, since `/etc/victoriametrics/scrape.yml` won't exist.

**Q: Will docker.sh break my existing PM2 or Node scrape jobs?**
No. The script checks whether `docker_engine` and `cadvisor` jobs already exist before appending anything. Existing jobs configured by `init.sh` are never modified.

**Q: Can I re-run docker.sh after it's already been run?**
Yes — it's idempotent. Docker will be upgraded if a newer version is available. Container (`cadvisor`) is stopped and recreated cleanly. Scrape jobs are not duplicated.

**Q: How do I view container logs in Cockpit?**
Open Cockpit (`http://localhost:9090` via SSH tunnel) → click **Containers** in the left menu → click your container → switch to the **Logs** tab.

**Q: Will running containers be interrupted when daemon.json is updated?**
No. `daemon.json` includes `"live-restore": true`, which means existing running containers continue running when the Docker daemon is restarted.

**Q: Does Docker bypass UFW firewall rules?**
No. `docker.sh` automatically patches `/etc/ufw/after.rules` using the official `DOCKER-USER` chain filter. This ensures that published container ports (e.g. `-p 8080:8080` or `docker compose`) honor UFW rules and cannot be reached from the public internet unless you explicitly allow them with `sudo ufw allow <port>/tcp`.

---

## 📄 License

MIT — free to use, modify, and distribute.

---

<p align="center">
  Part of the <strong>init.sh</strong> Node.js Production Server Provisioning suite.
</p>
