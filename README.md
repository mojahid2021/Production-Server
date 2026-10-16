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
| Cockpit Web Console | System management, journald logs & native Node.js PM2 GUI on `127.0.0.1:9090` (0 MB idle RAM) |
| Native journald | System & app log indexing with compact 150MB limit & 30MB buffer |
| Kernel hardening | sysctl — SYN flood, IP spoof, file descriptor tuning, memory cushion |
| fail2ban | SSH brute-force protection (ban after 5 failures) |
| UFW firewall | SSH open; management & monitoring ports bound strictly to localhost |
| Log rotation | PM2 logs: automated rotation, compression, and retention |

→ **Full documentation:** [init-README.md](init-README.md)

---

### `docker.sh`

**Docker CE + Cockpit integration — run after `init.sh`.**

Installs Docker CE and seamlessly connects Docker container management into Cockpit Web Console.

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
| cAdvisor | Optional per-container CPU / RAM / network / disk metrics on `:8080` (`--with-cadvisor`) |
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

5.  Monitor everything in Cockpit Web Console (0 MB Idle RAM)
    # Forward Cockpit port over SSH:
    ssh -L 9090:127.0.0.1:9090 <user>@<server>
    # Open https://localhost:9090 in your browser (Login with deploy user / password):
    #   Overview tab   → Real-time CPU, RAM, Disk I/O, Network
    #   Node.js (PM2)  → Live PM2 app process monitor, Start/Stop/Restart, Logs modal
    #   Services tab   → Start/stop/restart PM2, Nginx, Docker units
    #   Logs tab       → Filter and search systemd-journald logs
    #   Containers tab → Manage Docker containers (when docker.sh is installed)
```

---

## Monitoring & Management Stack

All management services are bound strictly to `127.0.0.1` and accessed via SSH port forwarding. Nothing is exposed to the public internet, and there is **zero background daemon overhead** when idle:

| Service | Address | Purpose | Idle RAM |
|---------|---------|---------|:---:|
| **Cockpit Web Console** | `127.0.0.1:9090` | Web Console — system management, journald logs | **0 MB** (socket-activated) |
| **Node.js PM2 Extension** | Inside Cockpit | Real-time PM2 process monitor, start/stop/restart, live logs | **0 MB** (on-demand CLI bridge) |
| **Containers GUI** | Inside Cockpit | Docker container lifecycle & stats (`cockpit-podman`) | **0 MB** (on-demand CLI bridge) |
| **System Journald** | Local host | Capped binary logs (150MB disk / 30MB buffer) | **~0 MB** (native kernel service) |

**Accessing Cockpit Web Console:**

```bash
# Forward Cockpit port over SSH from your local computer
ssh -L 9090:127.0.0.1:9090 <user>@<server-ip>

# Then open in your browser:
https://localhost:9090
# Login using your deploy user credentials (or root)
```

**Quick CLI Health & Tunnel Helpers:**

```bash
server_status   # Instant CLI overview of CPU, RAM, disk, swap, and PM2 apps
tunnel          # Displays SSH tunneling command for Cockpit
pstatus         # PM2 status shortcut
pmonit          # Terminal-based per-process CPU & RAM monitor
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
