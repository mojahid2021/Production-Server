# docker.sh — Docker CE + Monitoring Integration

> **Companion script to `init.sh`.**
> Installs Docker CE and connects every Docker metric and log into the Prometheus + Grafana stack already provisioned by `init.sh` — with zero manual steps.

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [What Gets Installed](#-what-gets-installed)
- [How It Integrates with init.sh](#-how-it-integrates-with-initsh)
- [Full Architecture](#-full-architecture)
- [Feature Breakdown](#-feature-breakdown-all-16-steps)
- [Grafana Dashboards](#-grafana-dashboards)
- [LogQL — Querying Docker Logs](#-logql--querying-docker-logs-in-grafana)
- [PromQL — Docker Metrics Queries](#-promql--docker-metrics-queries)
- [Docker Quick Reference](#-docker-quick-reference)
- [Pros & Cons](#-pros--cons)
- [Troubleshooting](#-troubleshooting)
- [Uninstall](#-uninstall--cleanup)
- [FAQ](#-faq)

---

## 🔍 Overview

`docker.sh` does two things in one run:

**Part 1 — Docker CE Installation**
Installs the latest stable Docker CE from Docker's official APT repository, along with Compose v2, BuildKit, containerd, ctop, Lazydocker, and Docker Scout.

**Part 2 — Monitoring Integration**
Connects Docker completely into the Prometheus + Grafana stack installed by `init.sh`. This means you get metrics *and* logs for every container, automatically, with dashboards pre-loaded — all without touching your existing `node_exporter`, Prometheus, or Grafana configuration.

```
init.sh already installed:        docker.sh adds:
  Prometheus   :9090          ←     docker_engine metrics  :9323
  Grafana      :3001          ←     cAdvisor metrics       :8080
  node_exporter:9100          ←     Loki* log backend      :3100
  Loki         :3100 (v7+)    ←     Promtail (Docker logs)
  Promtail     :9080 (v7+)    ←     5 Docker dashboards
  PM2 exporter :9209 (v7+)         Loki datasource (if not already present)
  (all untouched)

* When init.sh v7+ has already installed native Loki/Promtail, docker.sh reuses
  the existing Loki service and routes Docker Promtail to it via host networking.
  No port conflict, no duplicate service.
```

---

## Prerequisites

`docker.sh` is designed to run **after** `init.sh`. The following must already be present:

| Requirement | Installed By | Path / Port |
|---|---|---|
| Ubuntu 20.04 / 22.04 / 24.04 | — | — |
| Prometheus | `init.sh` | `/etc/prometheus/prometheus.yml` · `:9090` |
| Grafana | `init.sh` | `/etc/grafana/provisioning` · `:3001` |
| node_exporter | `init.sh` | `127.0.0.1:9100` |
| Deploy user | `init.sh` | `/home/<username>` |
| Loki *(optional)* | `init.sh` ≥ v7.0.0 | `127.0.0.1:3100` |
| Promtail *(optional)* | `init.sh` ≥ v7.0.0 | `127.0.0.1:9080` |

> If Prometheus or Grafana are missing, `docker.sh` will install Docker and skip the monitoring integration, printing a clear warning.
> When `init.sh` ≥ v7.0.0 has already installed native Loki/Promtail, `docker.sh` will reuse them instead of deploying conflicting Docker containers.

---

## ⚡ Quick Start

```bash
# Run everything (recommended)
sudo ./docker.sh

# Specify the deploy user explicitly
sudo ./docker.sh -u mojahid

# Skip monitoring integration (Docker only)
sudo ./docker.sh --no-mon

# Skip Loki/Promtail log pipeline only
sudo ./docker.sh --no-loki

# Show help
sudo ./docker.sh -h
```

**After the script completes:**

```bash
# Apply docker group without re-logging in
newgrp docker

# Verify Docker works without sudo
docker ps

# Open Grafana dashboards (same SSH tunnel as init.sh)
ssh -L 3001:localhost:3001 <username>@<server-ip>
# Open: http://localhost:3001 → Dashboards → Docker
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

### 📊 Monitoring Containers (Docker-based)

| Container | Port | Role |
|---|---|---|
| `cadvisor` | `127.0.0.1:8080` | Per-container CPU/RAM/net/disk metrics |
| `loki` | `127.0.0.1:3100` | Docker log aggregation backend |
| `promtail` | `127.0.0.1:9080` | Docker log collector → ships to Loki |

### ⚙️ Configuration Changes

| What | Where | Detail |
|---|---|---|
| `daemon.json` | `/etc/docker/daemon.json` | BuildKit, log rotation, metrics, live-restore |
| Prometheus scrape jobs | `/etc/prometheus/prometheus.yml` | `docker_engine` + `cadvisor` appended |
| Loki datasource | `/etc/grafana/provisioning/datasources/loki-docker.yaml` | Auto-provisioned |
| Docker dashboards | `/var/lib/grafana/dashboards/docker/` | 5 dashboards downloaded |
| Dashboard provider | `/etc/grafana/provisioning/dashboards/docker-dashboards.yaml` | Points to dashboard dir |

---

## 🔗 How It Integrates with init.sh

`docker.sh` is carefully designed to **extend** `init.sh` without breaking anything:

| init.sh Component | docker.sh Behavior |
|---|---|
| `node_exporter` (`:9100`) | **Left untouched.** Already scraped by Prometheus — no duplicate job added. |
| `prometheus.yml` | **Appended only.** `docker_engine` + `cadvisor` jobs added. Existing jobs preserved. Backup created. |
| Grafana (`:3001`) | **Extended.** Loki datasource + Docker dashboards added. Existing Prometheus datasource and `System` folder untouched. |
| Deploy user | **Extended.** Added to `docker` group so they can run Docker without `sudo`. |
| SSH tunnel (`:3001`) | **Same tunnel.** No new ports to forward — everything goes through the existing `:3001` tunnel from `init.sh`. |
| `server_status` script | **Compatible.** Docker containers will appear in `docker ps` output referenced by `server_status`. |

---

## 🏗️ Full Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                         Your Ubuntu Server                          │
│                                                                    │
│  ┌──── INSTALLED BY init.sh ──────────────────────────────────┐   │
│  │                                                             │   │
│  │  node_exporter ──────────────────────────────────────────┐ │   │
│  │  :9100 (host OS metrics)                                  │ │   │
│  │                                                           ▼ │   │
│  │  Prometheus :9090 ◄── scrapes ── docker_engine :9323 ────┤ │   │
│  │  /etc/prometheus/prometheus.yml   cadvisor      :8080 ────┤ │   │
│  │  (patched by docker.sh)                                   │ │   │
│  │                            │                              │ │   │
│  │  Grafana :3001 ◄───────────┘                              │ │   │
│  │  /etc/grafana/provisioning/         ◄── Loki :3100 ───────┘ │   │
│  │  (datasource + dashboards added)                             │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  ┌──── INSTALLED BY docker.sh ────────────────────────────────┐   │
│  │                                                             │   │
│  │  Docker CE daemon                                           │   │
│  │  /etc/docker/daemon.json                                    │   │
│  │  Metrics → :9323/metrics                                    │   │
│  │                                                             │   │
│  │  [cadvisor container]   → :8080/metrics → Prometheus        │   │
│  │  Per-container CPU/RAM/net/disk                             │   │
│  │                                                             │   │
│  │  [loki container]       → :3100 ← Grafana query            │   │
│  │  Log storage, 31-day retention                              │   │
│  │                                                             │   │
│  │  [promtail container]   reads ──────────────────────────►  │   │
│  │  /var/lib/docker/containers/*/*-json.log    push → Loki    │   │
│  │                                                             │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘

Access:   ssh -L 3001:localhost:3001 <user>@<server>
          http://localhost:3001  →  Dashboards  →  Docker
```

---

## 🔬 Feature Breakdown (All 16 Steps)

| Step | Name | Detail |
|---|---|---|
| 01 | Preflight | Checks root, OS, detects deploy user, verifies Prometheus + Grafana from init.sh |
| 02 | Remove old packages | Purges `docker.io`, `docker-engine`, `podman-docker`, etc. Upgrades if already installed. |
| 03 | Prerequisites | Installs `curl`, `gnupg`, `jq`, `lsb-release`, `bash-completion` |
| 04 | Docker APT repo | Adds official `download.docker.com` signed repo with GPG key in `/etc/apt/keyrings/` |
| 05 | Docker CE install | `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin` |
| 06 | daemon.json | Writes production-optimized config: BuildKit, log rotation, overlay2, live-restore, metrics |
| 07 | Docker group | `usermod -aG docker <deploy_user>` — no more `sudo docker` |
| 08 | Ecosystem tools | ctop, Lazydocker, Docker Scout, bash completion |
| 09 | cAdvisor | Deploys container bound to `127.0.0.1:8080` — per-container metrics with compose labels |
| 10 | Loki + Promtail | Loki on `:3100`, Promtail reads all container JSON logs, 31-day retention |
| 11 | Prometheus patch | Appends `docker_engine` + `cadvisor` jobs to `prometheus.yml`, validates with `promtool`, reloads |
| 12 | Loki datasource | Writes `/etc/grafana/provisioning/datasources/loki-docker.yaml` |
| 13 | Dashboards | Downloads 5 dashboards from grafana.com, fixes datasource UIDs, saves to provisioning dir |
| 14 | Reload Grafana | Restarts `grafana-server` to apply new datasource + dashboards |
| 15 | Verify | Smoke test (`hello-world`), endpoint checks for all components |
| 16 | Summary | Full reference card with commands, LogQL queries, access instructions |

---

## 📊 Grafana Dashboards

After running `docker.sh`, open Grafana → **Dashboards → Docker folder**:

| Dashboard | Grafana ID | Shows |
|---|---|---|
| **cAdvisor Exporter** | 14282 | Per-container CPU, RAM, network, disk I/O with graphs |
| **Docker + System Monitoring** | 893 | Combined host + container overview |
| **Docker Host** | 10619 | Host resources as seen through cAdvisor |
| **Docker Container Overview** | 15120 | Running containers table, state, restarts |
| **Loki Docker Logs** | 12611 | Log explorer, error rate, log volume per container |

> The `System` folder (from `init.sh`'s Node Exporter Full dashboard) remains untouched in a separate folder.

---

## 🔎 LogQL — Querying Docker Logs in Grafana

Open **Grafana → Explore → select Loki datasource**:

### Basic Selectors

```logql
{job="docker"}                          # all container logs
{container_name="nginx"}                # one specific container
{compose_project="myapp"}              # all services in a compose project
{compose_service="api"}                 # one compose service across all projects
{job="docker", stream="stderr"}         # stderr only (errors/warnings)
{job="docker_daemon"}                   # Docker daemon itself
```

### Filtering Log Lines

```logql
{job="docker"} |= "error"              # lines containing "error"
{job="docker"} != "healthcheck"        # exclude health check noise
{container_name="api"} |~ "(?i)fail|exception|panic"   # case-insensitive regex
{job="docker"} |= "error" != "404"     # errors but not 404s
```

### Parsing JSON Logs

```logql
{job="docker"} | json                              # parse JSON fields
{job="docker"} | json | level="error"              # structured error level
{container_name="api"} | json | status >= 500      # HTTP 5xx errors
{job="docker"} | json | duration > 1000            # slow requests > 1s
```

### Rate / Volume Metrics from Logs

```logql
# Error rate per container (per minute)
sum by (container_name) (
  rate({job="docker"} |= "error" [1m])
)

# Log volume per compose service
sum by (compose_service) (
  rate({job="docker"}[5m])
)
```

---

## 📈 PromQL — Docker Metrics Queries

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
docker ps -f name=loki               # check Loki
docker ps -f name=promtail           # check Promtail
docker logs cadvisor --tail 20       # cAdvisor logs
docker logs loki --tail 20           # Loki logs
docker logs promtail --tail 20       # Promtail logs
```

---

## ✅ Pros & Cons

### ✅ Pros

| # | Pro | Detail |
|---|---|---|
| 1 | **init.sh-aware** | Knows exactly where Prometheus/Grafana live — no manual path detection |
| 2 | **Never duplicates node_exporter** | init.sh's node_exporter job left 100% untouched |
| 3 | **Safe prometheus.yml patching** | Backup created, promtool validates before reload, HTTP reload (zero downtime) |
| 4 | **Same visual style as init.sh** | Identical colors, section headers, box borders — looks like one suite |
| 5 | **Same SSH tunnel** | Uses the same `:3001` SSH tunnel from init.sh — no new ports to remember |
| 6 | **Idempotent** | Safe to re-run — detects existing installs and upgrades cleanly |
| 7 | **BuildKit on by default** | Faster, parallel, layer-cached builds without extra flags |
| 8 | **Log rotation built-in** | daemon.json caps container logs at 20MB × 5 files — disk won't fill |
| 9 | **Live-restore enabled** | Containers survive Docker daemon restarts/upgrades |
| 10 | **31-day log retention** | Loki compactor enforces retention — no manual cleanup |
| 11 | **cAdvisor labels compose** | `compose_project` and `compose_service` labels promoted to metrics |
| 12 | **Graceful optional failures** | ctop/Lazydocker/Scout failures emit warnings, never block Docker install |
| 13 | **promtool validation** | Prometheus config validated before reload — config errors auto-rollback |
| 14 | **Smoke tested** | `hello-world` container run at end confirms full Docker stack works |
| 15 | **Comprehensive summary** | Summary card includes LogQL examples, PromQL queries, access instructions |

---

### ❌ Cons

| # | Con | Detail |
|---|---|---|
| 1 | **Requires init.sh first** | Monitoring integration is skipped if Prometheus/Grafana aren't present |
| 2 | **Ubuntu/Debian only** | No support for CentOS, Fedora, RHEL, Arch, or Alpine |
| 3 | **Overwrites daemon.json** | Existing `/etc/docker/daemon.json` is replaced (backup is saved) |
| 4 | **No version pinning** | Installs latest stable Docker at runtime — not reproducible for locked CI/CD |
| 5 | **cAdvisor needs privileged** | Runs as `--privileged` container — necessary for host filesystem metrics |
| 6 | **Promtail reads raw log files** | Needs access to `/var/lib/docker/containers` — runs privileged |
| 7 | **curl-pipe-bash for tools** | Lazydocker install uses `curl \| bash` — review before trusting in hardened envs |
| 8 | **No Swarm / Kubernetes** | Standalone Docker CE only — no orchestration layer setup |
| 9 | **Grafana restart (not reload)** | Grafana is restarted (not hot-reloaded) to apply provisioning — brief downtime |
| 10 | **No ARM full test** | cAdvisor + node tooling works on `arm64`, but Scout CLI may differ |
| 11 | **docker group = effective root** | Any user in the `docker` group can mount host filesystems — trusted users only |
| 12 | **Internet required** | All images and tools fetched at runtime — no air-gap/offline support |

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

### Prometheus not scraping Docker targets

```bash
# Check target state in Prometheus
curl http://127.0.0.1:9090/api/v1/targets | python3 -m json.tool | grep -A5 docker

# Validate prometheus.yml
promtool check config /etc/prometheus/prometheus.yml

# Manual reload
curl -X POST http://127.0.0.1:9090/-/reload
```

### No logs appearing in Loki / Grafana

```bash
docker logs promtail --tail 30
curl http://127.0.0.1:3100/ready
curl http://127.0.0.1:3100/loki/api/v1/labels | python3 -m json.tool
# In Grafana Explore, select Loki and run: {job="docker"}
```

### Grafana dashboards not appearing

```bash
sudo systemctl status grafana-server
sudo journalctl -xu grafana-server --no-pager | tail -20
ls /var/lib/grafana/dashboards/docker/
ls /etc/grafana/provisioning/dashboards/
sudo systemctl restart grafana-server
```

### Port already in use

```bash
sudo ss -tulpn | grep -E '8080|3100|9323|9080'
docker ps -a                         # check for stopped containers holding ports
docker rm -f cadvisor loki promtail  # force remove, then re-run docker.sh
```

---

## 🗑️ Uninstall / Cleanup

### Remove Docker monitoring containers

```bash
docker rm -f cadvisor loki promtail
docker network rm monitoring
sudo rm -rf /opt/docker-monitoring
```

### Remove Grafana provisioning added by docker.sh

```bash
sudo rm -f  /etc/grafana/provisioning/datasources/loki-docker.yaml
sudo rm -f  /etc/grafana/provisioning/dashboards/docker-dashboards.yaml
sudo rm -rf /var/lib/grafana/dashboards/docker/
sudo systemctl restart grafana-server
```

### Restore Prometheus config

```bash
# Find the backup created by docker.sh
ls /etc/prometheus/prometheus.yml.bak.*

# Restore
sudo cp /etc/prometheus/prometheus.yml.bak.<timestamp> /etc/prometheus/prometheus.yml
curl -X POST http://127.0.0.1:9090/-/reload
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
Yes. Docker CE will install normally. The monitoring integration steps will be skipped with clear warnings, since `/etc/prometheus/prometheus.yml` and `/etc/grafana/provisioning` won't exist.

**Q: Will docker.sh break my existing node_exporter scrape job?**
No. The script checks whether a `docker_engine` job already exists before appending anything. The `node` job added by `init.sh` is never modified.

**Q: My Prometheus config has custom jobs. Is it safe to run?**
Yes. `docker.sh` only *appends* new scrape jobs to `prometheus.yml`. It creates a timestamped backup before any change, validates with `promtool`, and rolls back if validation fails.

**Q: Can I re-run docker.sh after it's already been run?**
Yes — it's idempotent. Docker will be upgraded if a newer version is available. Containers (`cadvisor`, `loki`, `promtail`) are stopped and recreated cleanly. Prometheus jobs are not duplicated (it checks first).

**Q: Why is Grafana on port 3001 instead of 3000?**
`init.sh` configures Grafana on `3001` to avoid conflicting with Node.js apps (which commonly run on port 3000). `docker.sh` uses the same port — no changes needed.

**Q: How do I add more Docker dashboards?**
Place any `.json` dashboard file in `/var/lib/grafana/dashboards/docker/` and it will auto-load within 30 seconds (the dashboard provider `updateIntervalSeconds` is set to 30). Or import via Grafana UI → Dashboards → Import → enter a grafana.com dashboard ID.

**Q: Will running containers be interrupted when daemon.json is updated?**
No. `daemon.json` includes `"live-restore": true`, which means existing running containers continue running when the Docker daemon is restarted.

---

## 📄 License

MIT — free to use, modify, and distribute.

---

<p align="center">
  Part of the <strong>init.sh</strong> Node.js Production Server Provisioning suite.
</p>
