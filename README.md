# Production-Server

**One-command Ubuntu server provisioning for Node.js, Docker, and Nginx workloads.**

A curated collection of production-grade bash scripts that transform a blank Ubuntu 20.04/22.04/24.04 server into a fully configured, secure, observable hosting environment — in under 15 minutes, with zero manual configuration.

---

## Overview

| Script | Purpose | README |
|--------|---------|--------|
| [`init.sh`](#initsh) | Core server provisioning — user, SSH, PM2, monitoring | [init-README.md](init-README.md) |
| [`docker.sh`](#dockersh) | Docker CE installation + monitoring integration | [Docker-README.md](Docker-README.md) |
| [`nginx.sh`](#nginxsh) | Nginx virtual host setup with SSL | [Nginx-README.md](Nginx-README.md) |

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      Ubuntu Server                      │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐  │
│  │  init.sh  │  │ nginx.sh │  │      docker.sh       │  │
│  │           │  │          │  │                      │  │
│  │ User+SSH  │  │  Nginx   │  │  Docker CE + Compose │  │
│  │ NVM+Node  │  │  vHosts  │  │  cAdvisor metrics    │  │
│  │ PM2       │  │  SSL/TLS │  │  Cockpit integration │  │
│  │ Cockpit   │  │  acme.sh │  │                      │  │
│  │ Vict.Metr.│  └──────────┘  └──────────────────────┘  │
│  │ journald  │                                          │
│  └──────────┘  Lean Monitoring Stack (~100MB Total RAM) │
│                ┌─────────────────────────────────────┐  │
│                │  Cockpit (9090)   ← systemd/journald │  │
│                │  Vict.Metr.(8428) ← PM2 / node / dock│  │
│                │  Built-in VMUI    ← PromQL explorer  │  │
│                └─────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## Scripts

### `init.sh`

**Core provisioning — run this first on every new server.**

Sets up a complete, hardened Node.js hosting environment in a single interactive session.

```bash
wget https://raw.githubusercontent.com/mojahid2021/Production-Server/main/init.sh
chmod +x init.sh
sudo ./init.sh
```

**What it installs:**

| Component | Details |
|-----------|---------|
| OS user | Dedicated deploy user with SSH + password access |
| SSH | Password + key login, root SSH blocked |
| Sudo | Full root access (with password) + NOPASSWD for PM2/apt |
| NVM + Node.js | Selected version via NVM |
| PM2 | Process manager with bulletproof systemd startup |
| PM2 exporter | Prometheus metrics for all PM2 apps (auto-discovered on `:9209`) |
| Cockpit | Web management console & real-time hardware/log viewer on `127.0.0.1:9090` (0 MB idle RAM) |
| VictoriaMetrics | Ultra-lightweight time-series TSDB & VMUI on `127.0.0.1:8428` (48 MB RAM cap) |
| Native journald | System & app log indexing with compact 150MB limit & 30MB buffer |
| Kernel hardening | sysctl — SYN flood, IP spoof, file descriptor tuning |
| fail2ban | SSH brute-force protection (ban after 5 failures) |
| UFW firewall | SSH open; management & monitoring ports bound to localhost |
| Log rotation | PM2 logs: automated rotation, compression, and retention |

→ **Full documentation:** [init-README.md](init-README.md)

---

### `docker.sh`

**Docker CE + monitoring integration — run after `init.sh`.**

Installs Docker CE and seamlessly connects Docker container management into Cockpit and container metrics into VictoriaMetrics.

```bash
wget https://raw.githubusercontent.com/mojahid2021/Production-Server/main/docker.sh
chmod +x docker.sh
sudo ./docker.sh
```

**What it adds on top of `init.sh`:**

| Component | Details |
|-----------|---------|
| Docker CE | Latest stable from official APT repository |
| Docker Compose v2 | Integrated plugin |
| BuildKit | Fast, cached image builds |
| Cockpit Integration | View, start, stop, and inspect containers in Cockpit GUI |
| cAdvisor | Per-container CPU / RAM / network / disk metrics on `:8080` |
| VictoriaMetrics Scrape | Auto-scrapes Docker daemon (`:9323`) and cAdvisor (`:8080`) |
| Ecosystem Tools | ctop, Lazydocker, and Docker Scout |

→ **Full documentation:** [Docker-README.md](Docker-README.md)

---

### `nginx.sh`

**Nginx virtual host setup — run after `init.sh`, once per domain.**

Fully interactive script that configures a production-hardened Nginx virtual host with SSL, security headers, and optional reverse-proxy for Node.js/Laravel/PHP applications.

```bash
wget https://raw.githubusercontent.com/mojahid2021/Production-Server/main/nginx.sh
chmod +x nginx.sh
sudo ./nginx.sh
```

**What it configures:**

| Feature | Details |
|---------|---------|
| Domains | Single or dual-domain (www + apex) |
| SSL | acme.sh — Let's Encrypt, ZeroSSL, Buypass (no certbot) |
| Site types | Static, Node.js proxy, Laravel, PHP-FPM, custom |
| Security headers | HSTS, CSP, X-Frame-Options, referrer policy |
| File uploads | Configurable max upload size per virtual host |
| Auto-renewal | cron-based certificate renewal, zero downtime |

→ **Full documentation:** [Nginx-README.md](Nginx-README.md)

---

## Recommended Workflow

```
1.  Provision the server
    sudo ./init.sh

2.  (Optional) Add Docker support
    sudo ./docker.sh

3.  Deploy a Node.js app
    ssh <user>@<server>
    git clone https://github.com/you/repo.git ~/projects/myapp
    cd ~/projects/myapp && npm install
    pm2 start app.js --name myapp -- --port 3000
    pm2 save

4.  Add an Nginx virtual host + SSL
    sudo ./nginx.sh

5.  Monitor everything in Cockpit & VictoriaMetrics
    # Cockpit Host Management & Logs:
    ssh -L 9090:localhost:9090 <user>@<server>
    # open http://localhost:9090  (Login with deploy user / password)
    #   System tab     → Real-time CPU, RAM, Disk I/O, Network
    #   Services tab   → Start/stop/restart PM2, Nginx, Docker units
    #   Logs tab       → Filter and search systemd-journald logs
    #   Containers tab → Manage Docker containers

    # VictoriaMetrics Time-Series Explorer (VMUI):
    ssh -L 8428:localhost:8428 <user>@<server>
    # open http://localhost:8428/vmui
    #   Query metrics  → PromQL / MetricsQL for PM2, Docker, Node
```

---

## Monitoring & Management Stack

All services are bound to `127.0.0.1` and accessed via SSH port forwarding. Nothing is exposed to the public internet.

| Service | Address | Purpose |
|---------|---------|---------|
| Cockpit | `127.0.0.1:9090` | Web Console — system management, journald logs, Docker (0 MB idle RAM) |
| VictoriaMetrics | `127.0.0.1:8428` | Time-series TSDB & VMUI visual explorer (48 MB RAM cap) |
| PM2 exporter | `127.0.0.1:9209` | PM2 process metrics (heap, CPU, event loop, restarts) |
| Docker Daemon | `127.0.0.1:9323` | Native Docker engine metrics (via docker.sh, 0 extra containers) |
| cAdvisor | `127.0.0.1:8080` | Optional per-container metrics (via `docker.sh --with-cadvisor`) |

**Accessing Cockpit Web Console:**

```bash
# Forward Cockpit port over SSH
ssh -L 9090:localhost:9090 <user>@<server-ip>

# Then open in your browser
http://localhost:9090
# Login using your deploy user credentials (or root)
```

**Accessing VictoriaMetrics VMUI:**

```bash
# Forward VictoriaMetrics port over SSH
ssh -L 8428:localhost:8428 <user>@<server-ip>

# Then open in your browser
http://localhost:8428/vmui
```

**Useful MetricsQL / PromQL Queries in VMUI:**

```promql
# PM2 App Memory Usage (Heap & RSS)
pm2_process_memory_usage_bytes{instance="pm2_apps"}

# PM2 App CPU Utilization
pm2_process_cpu_usage_ratio{instance="pm2_apps"}

# PM2 Process Restarts
pm2_process_restart_count{instance="pm2_apps"}

# Docker Container CPU Usage (via cAdvisor)
container_cpu_usage_seconds_total
```

---

## Requirements

| Requirement | Details |
|-------------|---------|
| OS | Ubuntu 20.04, 22.04, or 24.04 LTS |
| Access | Must run as root (`sudo`) |
| Internet | Required (downloads binaries from GitHub and package repos) |
| Architecture | amd64 or arm64 |

---

## Security Notes

- Monitoring ports are **localhost-only** — not reachable from the public internet.
- SSH root login is **disabled** by `init.sh`. Use `ssh <user>@<server>` then `sudo -i`.
- UFW firewall allows only port 22 (SSH) by default. Open additional ports as needed with `sudo ufw allow <port>/tcp`.
- All downloaded binaries come from official sources (GitHub releases, Ubuntu APT, Docker APT).
- Cockpit authenticates securely using native Linux system user credentials via PAM.

---

## Compatibility

| Script | Ubuntu 20.04 | Ubuntu 22.04 | Ubuntu 24.04 |
|--------|:---:|:---:|:---:|
| `init.sh` | ✔ | ✔ | ✔ |
| `docker.sh` | ✔ | ✔ | ✔ |
| `nginx.sh` | ✔ | ✔ | ✔ |

---

## License

MIT — see individual script headers for details.
