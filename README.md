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
│  │ NVM+Node  │  │  vHosts  │  │  cAdvisor + Loki     │  │
│  │ PM2       │  │  SSL/TLS │  │  Docker dashboards   │  │
│  │ Prometheus│  │  acme.sh │  │                      │  │
│  │ Grafana   │  └──────────┘  └──────────────────────┘  │
│  │ Loki      │                                          │
│  │ Promtail  │  Monitoring stack (port 3001)            │
│  └──────────┘  ┌─────────────────────────────────────┐  │
│                │  Grafana  ←  Prometheus  ←  node_exp │  │
│                │  Grafana  ←  Loki  ←  Promtail       │  │
│                │  Grafana  ←  PM2 exporter  ←  PM2    │  │
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
| PM2 exporter | Prometheus metrics for all PM2 apps (auto-discovered) |
| Prometheus | Metrics database — node, PM2, system (15-day retention) |
| Grafana | Dashboard UI on `127.0.0.1:3001` |
| Loki | Log aggregation backend on `127.0.0.1:3100` |
| Promtail | Log agent — collects syslog, auth, kern, PM2 app logs |
| Kernel hardening | sysctl — SYN flood, IP spoof, file descriptor tuning |
| fail2ban | SSH brute-force protection (ban after 5 failures) |
| UFW firewall | SSH open; monitoring ports bound to localhost |
| Log rotation | PM2 logs: 14-day retention, daily, compressed |

→ **Full documentation:** [init-README.md](init-README.md)

---

### `docker.sh`

**Docker CE + monitoring integration — run after `init.sh`.**

Installs Docker CE and connects all Docker metrics and logs into the existing Prometheus + Grafana + Loki stack without touching any existing configuration.

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
| cAdvisor | Per-container CPU / RAM / network / disk metrics |
| Loki + Promtail | Container log pipeline via Docker socket |
| 5 Grafana dashboards | Docker Overview, Container Stats, Logs, and more |

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

5.  Monitor everything in Grafana
    ssh -L 3001:localhost:3001 <user>@<server>
    # open http://localhost:3001  (admin / admin — change immediately)
    #   System tab  → Node Exporter Full  (CPU, RAM, disk, network)
    #   Apps tab    → PM2 Process Monitor (per-app status, CPU, RAM, restarts)
    #   Explore     → Loki datasource     (system logs, auth, PM2 app logs)
```

---

## Monitoring Stack

All monitoring services are bound to `127.0.0.1` and accessed via SSH port forwarding. Nothing is exposed to the public internet.

| Service | Address | Purpose |
|---------|---------|---------|
| Grafana | `127.0.0.1:3001` | Dashboard UI — metrics + logs |
| Prometheus | `127.0.0.1:9090` | Metrics database |
| node_exporter | `127.0.0.1:9100` | System metrics collector |
| PM2 exporter | `127.0.0.1:9209` | PM2 process metrics (auto-discovered) |
| Loki | `127.0.0.1:3100` | Log aggregation backend |
| Promtail | `127.0.0.1:9080` | Log collection agent |

**Accessing Grafana:**

```bash
# Forward port over SSH
ssh -L 3001:localhost:3001 <user>@<server-ip>

# Then open in your browser
http://localhost:3001
# Default credentials: admin / admin  (change on first login)
```

**Pre-provisioned dashboards:**

| Dashboard | Folder | Data Source |
|-----------|--------|-------------|
| Node Exporter Full | System | Prometheus |
| PM2 Process Monitor | Apps | Prometheus |

**Querying logs in Grafana (Explore → Loki):**

```logql
# All PM2 app logs
{job="pm2"}

# Only error lines from PM2 apps
{job="pm2"} |= "error"

# Authentication log (SSH logins, sudo)
{job="auth"}

# System syslog
{job="syslog"}

# Kernel messages
{job="kern"}
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
- All downloaded binaries come from official sources (GitHub releases, Grafana APT, Docker APT).
- Change the Grafana default password (`admin/admin`) immediately after first login.

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
