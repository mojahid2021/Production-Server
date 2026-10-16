# init.sh

**Production Node.js Server Provisioner — v7.0.0**  
Ubuntu 20.04 / 22.04 / 24.04 LTS

---

## What Is This?

`init.sh` is a single bash script that turns a **blank Ubuntu server** into a **fully configured, production-ready Node.js hosting environment** — in one command, in under 10 minutes.

Without this script, setting up a server properly takes 3–5 hours and requires deep knowledge of Linux, SSH, Nginx, PM2, systemd, firewall configuration, and monitoring tools. This script handles all of it automatically, correctly, and consistently every time.

You run it once. It asks your username, password, and Node.js version. Then it sets everything up. After that, your workflow is simply:

```
git clone → npm install → pm2 start → nginx_add_site
```

---

## Requirements

| Requirement | Details |
|---|---|
| OS | Ubuntu 20.04, 22.04, or 24.04 LTS |
| Access | Must run as root (`sudo`) |
| Internet | Required (downloads NVM and Node.js) |
| Fresh server | Recommended — works on existing servers too |

---

## Quick Start

```bash
# Download and make executable
wget https://raw.githubusercontent.com/mojahid2021/Production-Server/main/init.sh
chmod +x init.sh

# Run interactively (recommended)
sudo ./init.sh

# Or pass values directly (skips prompts for those values)
sudo ./init.sh -u mojahid -n 20
```

When run interactively, the script asks:

1. **Username** — validated in real-time (checks format + checks if already exists)
2. **Password** — type your own, or press Enter to auto-generate a secure 16-character password
3. **Node.js version** — press Enter to accept the default (v20)
4. **Additional Firewall Ports** — choose nginx (80/443), email, or custom ports
5. **Memory Cushion & Swap Allocation** — displays current RAM and existing swap, provides an intelligent size recommendation (e.g. 2GB), allows custom sizing, and sets the physical RAM usage trigger (e.g. swap activates only after 90% RAM is utilized, `vm.swappiness=10`).

A confirmation summary is shown before anything happens. You type `y` to proceed or `n` to cancel.

---

## All Options

| Flag | What it does | Default |
|---|---|---|
| `-u USERNAME` | Set deploy username | asked interactively |
| `-p PASSWORD` | Set a custom password | auto-generated |
| `-k PUBKEY` | Install an SSH public key file | none |
| `-n NODE_VER` | Node.js version: `18`, `20`, `22`, `lts/*` | `20` |
| `--swap-size SIZE` | Set swap size: `2G`, `1G`, `4G`, `0` to skip | auto-detected |
| `--swap-threshold %` | RAM % usage when swap activates (e.g. `90`) | `90%` |
| `--swappiness VAL` | Direct kernel swappiness 0–100 | `10` |
| `--no-nvm` | Skip NVM + Node.js installation | — |
| `--no-pm2` | Skip PM2 installation | — |
| `--no-fw` | Skip UFW firewall configuration | — |
| `--no-mon` | Skip Cockpit Web Console monitoring installation | — |
| `-h` | Show help and exit | — |

---

## Features — Everything This Script Does

### 1. Interactive Setup Wizard

The script does not require you to memorise flags. When you run it without arguments, it walks you through setup step by step with clear prompts and real-time input validation.

- **Username validation:** must be lowercase, letters/digits/underscore, max 31 chars, start with a letter, not already exist on the system
- **Password:** your choice, or auto-generated via `openssl` (16 chars, mixed characters)
- **Confirmation screen:** shows a full summary of what will happen before any change is made
- **Abort option:** type `n` at the confirmation prompt to exit safely with zero changes

---

### 2. OS User Account

A dedicated Linux user is created for deploying and running your Node.js projects. This user is separate from root — it has controlled, auditable access.

- Linux user + primary group created with the name you choose
- Home directory at `/home/<username>`
- Password set (custom or auto-generated)
- `umask 022` — files created by this user are readable by the system but not world-writable
- Command history with timestamps, auto-deduplication

---

### 3. SSH Access — Password + Key (both work)

You can connect to the server using either a password or an SSH key.

```bash
# Password login
ssh mojahid@your-server-ip

# SSH key login (faster, no password prompt)
ssh -i ~/.ssh/id_ed25519 mojahid@your-server-ip
```

**Root SSH login is permanently blocked.** You must log in as your deploy user first, then switch to root:

```bash
ssh mojahid@your-server-ip   # step 1 — login as your user
# Note: after provisioning this script configures sudo so `sudo -i` requires the *root* account password.
sudo -i                       # step 2 — enter ROOT password (root account)
# do root work here
exit                          # step 3 — leave root, back to mojahid
```

**Why block direct root SSH?**  
`ssh root@server` leaves no audit trail — you cannot tell what was done or when. The `sudo -i` approach logs every privilege escalation in `/var/log/auth.log`, which is the standard practice for all production servers.

- `PasswordAuthentication yes` — password login allowed
- `PermitRootLogin no` — direct root SSH permanently blocked
- SSH key installed if `-k` flag was used during provisioning
- Add a key anytime: `ssh-copy-id -i ~/.ssh/id_ed25519.pub mojahid@<server-ip>`

---

### 4. Sudo Access — Flexible, Layered

The deploy user has full root access when needed, plus passwordless shortcuts for the most common operations.

> **Which password does `sudo` ask for?** By default sudo asks for the calling user's password, but this provisioning config changes that behavior for the deploy user: `sudo` will require the **root account's password** for authentication (except for commands explicitly listed as `NOPASSWD`, such as `apt` and certain `systemctl` operations).

| Operation | Password needed? |
|---|---|
| `sudo -i` — become root | ✅ Yes |
| `sudo su -` — switch to root | ✅ Yes |
| Any general `sudo` command | ✅ Yes |
| `sudo apt install <package>` | ❌ No |
| `sudo systemctl reload nginx` | ❌ No |
| `sudo systemctl restart nginx` | ❌ No |
| `sudo systemctl restart pm2-<user>` | ❌ No |
| `sudo certbot --nginx -d domain.com` | ❌ No |
| `sudo nginx_add_site ...` | ❌ No |

The sudo session stays active for 15 minutes after entering the password — you will not be asked again during that window.

---

### 5. Git

Git is installed and ready to use immediately. Clone your projects straight from GitHub.

```bash
# Public repository
git clone https://github.com/you/myapp.git

# Private repository — using a personal access token
git clone https://<your-token>@github.com/you/myapp.git
```

Built-in aliases:

```bash
pull   # git pull origin main
gs     # git status
gl     # git log --oneline -10
```

---

### 6. NVM + Node.js

NVM (Node Version Manager) is installed under the user's home directory. This means the Node.js installation is completely isolated to this user — it does not affect root or any other user on the system.

- The version you specify is installed and set as the default
- You can install and switch between multiple versions at any time
- NVM is automatically loaded on every login via `.deploy_env`

```bash
nvm install 22        # install Node.js v22
nvm use 22            # switch to it for this session
nvm alias default 22  # make v22 the permanent default
nvm ls                # list all installed versions
node --version        # confirm active version
npm --version         # confirm npm version
```

---

### 7. PM2 — Process Manager (Bulletproof Startup)

PM2 keeps your Node.js apps running permanently. If an app crashes, PM2 restarts it automatically. If the server reboots, PM2 brings all your apps back up automatically.

This script sets up PM2 correctly in three steps that previous versions got wrong:

1. `npm install -g pm2` — installed under the user with the exact NVM node binary path
2. `pm2 startup systemd -u <username>` — registered as a proper systemd service with the correct node binary in PATH (this step often fails silently in other scripts — this one uses `env PATH=...` to ensure it works)
3. `systemctl enable pm2-<username>` — service enabled to survive reboot
4. `pm2 save` — initial empty process list saved (required for the service to start cleanly)

```bash
pm2 start app.js --name myapp     # start your app
pm2 save                          # ← ALWAYS run after changes — survives reboot
pm2 status                        # see all running apps
pm2 logs                          # live log stream (all apps)
pm2 logs myapp                    # live log stream (one app)
pm2 restart myapp                 # restart one app
pm2 stop myapp                    # stop one app
pm2 delete myapp                  # remove from PM2
pm2 monit                         # live CPU + RAM dashboard in terminal
pm2 reload all                    # zero-downtime reload (cluster mode)
```

Aliases available after login:

```bash
logs      # pm2 logs
pstatus   # pm2 status
prestart  # pm2 restart all
pmonit    # pm2 monit
psave     # pm2 save
```

> **Rule:** always run `pm2 save` after starting, stopping, or removing any app. Without it, your changes are lost after a server reboot.

---

### 8. Nginx — Multi-Project Reverse Proxy (via `nginx.sh`)

> **Note:** Nginx setup is handled by the companion script `nginx.sh`, not by `init.sh`. Run `init.sh` first to create the server environment, then run `sudo ./nginx.sh` to configure sites.

#### How Nginx Works

Nginx sits between the internet and your Node.js apps. It is the **front door** of your server.

```
Browser: https://myapp.com
         │
         ▼
   [Internet]
         │
         ▼
  ┌─────────────┐
  │  Nginx      │  ← receives ALL traffic on port 80 / 443
  │  :80 / :443 │  ← reads the domain name from the request
  └──────┬──────┘
         │
         │  "Host: myapp.com" → forward to port 3000
         │  "Host: blog.com"  → forward to port 4000
         │  "Host: api.com"   → forward to port 5000
         ▼
  Your Node.js app
  (running on localhost, invisible to the internet)
```

Your Node.js app **never** talks to the internet directly. Nginx handles all the complexity:

| Nginx handles | Your app does not need to |
|---|---|
| SSL/HTTPS termination | Manage SSL certificates |
| Domain routing | Know which domain it is on |
| Security headers | Set `X-Frame-Options` etc. |
| Blocking `.env` files | Protect secrets |
| Health check routing | Handle `/health` separately |

#### Multiple Projects on One Server

This is the most powerful feature. Each project gets its own Nginx config file and runs on its own port. Nginx reads the domain name from each incoming request and routes it to the right project.

```
myapp.com   → /etc/nginx/sites-available/myapp  → localhost:3000  ← Node app 1
blog.com    → /etc/nginx/sites-available/blog   → localhost:4000  ← Node app 2
api.com     → /etc/nginx/sites-available/api    → localhost:5000  ← Node app 3
```

To add a new project — run one command:

```bash
sudo nginx_add_site -n myapp -d myapp.com -p 3000
```

Done. The `nginx_add_site` helper:
1. Creates the Nginx config file in `sites-available/`
2. Creates the symlink in `sites-enabled/`
3. Tests the config with `nginx -t`
4. Reloads Nginx
5. Optionally runs `certbot` for a free SSL certificate

#### `nginx_add_site` — Full Usage

```bash
sudo nginx_add_site -n <name> -d <domain> -p <port>
```

| Flag | Description |
|---|---|
| `-n NAME` | Short project name — no spaces (e.g. `blog`, `api`, `shop`) |
| `-d DOMAIN` | Your domain name (e.g. `blog.com`) |
| `-p PORT` | The port your Node.js app is running on |
| `-s` | Skip SSL — useful when DNS is not pointed yet |

```bash
# Examples
sudo nginx_add_site -n blog  -d blog.com  -p 3000
sudo nginx_add_site -n api   -d api.com   -p 4000
sudo nginx_add_site -n shop  -d shop.com  -p 5000

# Skip SSL (add it later once DNS is pointed)
sudo nginx_add_site -n myapp -d myapp.com -p 3000 -s
# ... then add SSL later:
sudo certbot --nginx -d myapp.com
```

Nginx aliases:

```bash
nginx-reload  # sudo systemctl reload nginx
nginx-test    # sudo nginx -t
nginx-logs    # tail -f /var/log/nginx/*.log
```

---

### 9. Monitoring — Cockpit Web Console + Node.js (PM2) GUI (0 MB Idle RAM)

`init.sh` implements a **zero-idle-overhead** monitoring architecture that completely eliminates background monitoring daemons like VictoriaMetrics, Prometheus, Loki, ClickHouse, and `node_exporter`.

Instead, it couples **Cockpit** (systemd socket-activated host management) with a custom **Native Cockpit Node.js (PM2) GUI extension**. When you are not actively viewing the web console, the monitoring system consumes **0 MB RAM**:

| Service | Address | Purpose | Memory Footprint |
|---|---|---|:---:|
| **Cockpit Web Console** | `127.0.0.1:9090` | Host management, hardware charts, journald logs, Docker | **0 MB** (socket-activated) |
| **Node.js (PM2) Extension** | Inside Cockpit | Process monitor, start/stop/restart, live log viewer | **0 MB** (on-demand CLI bridge) |
| **Native journald** | Local host | System & app log indexing with 150MB limit & 30MB buffer | **~0 MB** (native kernel service) |

#### Layer 1: `server_status` — Instant CLI Overview

Run from anywhere in your shell after login:

```bash
server_status
```

Displays in one screen:
- **CPU load** (1-minute average) with color coding
- **Physical Memory** — used / total / percentage (green/yellow/red)
- **Swap Memory & Trigger** — used / total and RAM threshold trigger percentage
- **Disk** — used / total / percentage (green/yellow/red)
- **Uptime**
- **PM2 apps** — full `pm2 list` status table
- **Firewall (UFW)** — active status summary
- **Cockpit Web Console** — status and SSH tunnel access instructions

#### Layer 2: Native Journald & Shell Log Helpers

Direct access to structured system and application logs with zero agent overhead:

```bash
sys_logs       # View recent system journal logs
sys_errors     # View system error logs only (priority err..emerg)
nginx_logs     # View Nginx access & error logs
pm2_jlogs      # View PM2 systemd journal logs
pm2 monit      # Live per-process CPU + memory in terminal
pm2 logs       # Live scrolling log output from all apps
tunnel         # Prints the exact SSH tunneling command to open Cockpit
```

#### Layer 3: Cockpit — Web-Based Host Management & Journal Logs

Cockpit runs via `systemd` socket activation (`cockpit.socket`) bound strictly to `127.0.0.1:9090`. When not in use, the daemon stops and consumes **0 MB RAM**:

```bash
# Forward port over SSH from your local computer:
ssh -L 9090:127.0.0.1:9090 deploy_user@<server-ip>

# Open in browser:
https://localhost:9090
# Log in with your server deploy user and password (or root)
```

Features:
- **Host Overview:** Real-time interactive CPU, RAM, disk I/O, and network usage graphs.
- **Logs:** Search and filter `systemd-journald` logs by priority, time, and service unit.
- **Services:** Inspect, start, stop, and restart any systemd service (PM2, Nginx, Docker).
- **Terminal:** Interactive web terminal with full root/sudo access.
- **Containers:** Integrated container management via `cockpit-podman` (when `docker.sh` is run).
- **Accounts & Updates:** Manage system accounts, SSH keys, and apply security package updates.

#### Layer 4: Native Cockpit Node.js (PM2) GUI Extension

Installed directly into `/usr/share/cockpit/node-pm2/`, this custom PatternFly-styled extension interfaces with `/usr/local/bin/pm2-admin` to manage your Node.js apps without needing heavy external daemons or Prometheus exporters:

Features:
- **Stat Cards:** Real-time summary cards displaying Online Apps, Total Restarts, Total App Memory, and Average CPU.
- **Application Controls:** Interactive table listing all PM2 apps with status badges, PID, uptime, memory, CPU, and one-click actions:
  - **Restart** — Restart individual application
  - **Stop** — Gracefully stop application
  - **Start** — Start stopped application
  - **View Logs** — Opens a live 100-line log tail modal
- **Global Actions:** **Restart All** and **Save State** (`pm2 save`) buttons.
- **Auto-Refresh:** Polls PM2 status every 3 seconds while the tab is open, stopping immediately when you navigate away.

---

### 10. fail2ban — Brute Force Protection

fail2ban monitors `/var/log/auth.log` and automatically bans IP addresses that fail SSH login too many times.

- **Threshold:** 5 failed attempts within 10 minutes
- **Ban duration:** 1 hour
- **Scope:** SSH only

If someone tries to brute-force your server's password, their IP is blocked before they can do damage.

---

### 11. Kernel Hardening (sysctl)

The following kernel-level protections are applied via `/etc/sysctl.d/99-node-provision.conf`:

| Setting | Protects against |
|---|---|
| `rp_filter = 1` | IP spoofing attacks |
| `tcp_syncookies = 1` | SYN flood / DDoS |
| `accept_redirects = 0` | ICMP redirect attacks |
| `send_redirects = 0` | Man-in-the-middle routing attacks |
| `log_martians = 1` | Logs packets with impossible source addresses |
| `icmp_echo_ignore_broadcasts = 1` | Smurf attacks |
| `protected_hardlinks = 1` | TOCTOU race condition exploits |
| `protected_symlinks = 1` | Symlink-based privilege escalation |
| `fs.file-max = 100000` | Increases max open files (needed for Node.js under load) |
| `net.core.somaxconn = 65535` | Increases max connection queue (Node.js performance) |

---

### 12. UFW Firewall

UFW (Uncomplicated Firewall) is configured with a deny-all default policy. Only necessary ports are opened.

| Port | Open? | Reason |
|---|---|---|
| 22 (SSH) | ✅ | Remote access |
| 80 (HTTP) | ✅ | Nginx + Let's Encrypt |
| 443 (HTTPS) | ✅ | Nginx SSL |
| 9090, 9100, 13001 (monitoring) | ❌ | Bound to 127.0.0.1 — no external rule needed |
| 3000, 4000, 5000... | ❌ | App ports — localhost only via Nginx |

Your Node.js apps are **never** directly exposed to the internet. Traffic always goes through Nginx.

```bash
# Open a custom port if needed
sudo ufw allow 8080/tcp
sudo ufw status         # see current rules
```

---

### 13. Log Rotation

Logs are rotated automatically so your disk does not fill up.

| Log location | Retention | Rotation |
|---|---|---|
| `/home/<user>/.pm2/logs/*.log` | 14 days | Daily |
| `/var/log/nginx/*.log` | 30 days | Daily |

All rotated logs are compressed. PM2 is signalled to reopen its log files after each rotation.

---

### 14. Hardened Shell Profile

Every login session is configured with sane, secure defaults written to `~/.deploy_env` and sourced from `~/.bashrc`.

- `umask 022` — new files are not world-writable
- `HISTCONTROL=ignoreboth:erasedups` — no duplicate history entries
- `HISTTIMEFORMAT` — timestamps on every history entry
- Colorised prompt showing `user@host:path`
- NVM auto-loaded
- PM2 autocomplete enabled
- All aliases pre-configured

---

## Pros

| Pro | Why it matters |
|---|---|
| **One command setup** | No manual errors, nothing forgotten |
| **Interactive wizard** | No need to memorise flags |
| **Real-time input validation** | Catches bad usernames before anything is created |
| **Confirmation before changes** | Safe — you see exactly what will happen first |
| **Dry-run mode** | Test on production without risk |
| **PM2 startup is bulletproof** | Uses the exact NVM binary path — does not silently fail |
| **Multi-project Nginx** | Host unlimited projects on one server |
| **`nginx_add_site` helper** | Add a new project to Nginx in one command |
| **Zero-idle-overhead monitoring** | Instant terminal status, PM2 CLI monitor, and Cockpit web console (:9090) with native Node.js PM2 GUI (0 MB idle RAM) |
| **Both SSH auth methods** | Password and key — flexible for different workflows |
| **Sudo is layered** | Common tasks need no password, sensitive operations do |
| **Kernel hardening** | Protection applied at OS level, not just app level |
| **Log rotation built-in** | Disk will not fill up from old logs |
| **Repeatable** | Run again with a different `-u` to add a second deploy user |
| **Idiomatic Linux** | Correct directories, correct permissions, follows standards |

---

## Cons and Limitations

| Limitation | Explanation and workaround |
|---|---|
| **Ubuntu only** | Tested on Ubuntu 20.04, 22.04, 24.04. Other Debian-based distros may work but are not guaranteed |
| **Requires internet** | NVM and Node.js are downloaded during provisioning. Offline servers must use `--no-nvm` and `--no-mon` and install manually |
| **One user per run** | Each run provisions one user. Run the script again with a different username to add another user |
| **SSH password login is enabled** | More convenient but less secure than key-only. Add your public key with `-k` and consider disabling password auth in sshd after that |
| **Root SSH login is blocked** | You cannot `ssh root@server` directly — this is intentional. Login as your user then run `sudo -i` |
| **No database setup** | PostgreSQL, MySQL, Redis, MongoDB — you install and configure these separately |
| **No CI/CD pipeline** | The script sets up the environment — connecting GitHub Actions or GitLab CI to this server is a separate step |
| **Cockpit has no email alerts by default** | Cockpit provides live system status, logs, and service control. Alerts can be integrated via VictoriaMetrics vmalert if required |
| **fail2ban covers SSH only** | Nginx brute force protection is not configured by default |
| **No automatic SSL renewal check** | Certbot installs a renewal cron automatically, but verify it: `sudo certbot renew --dry-run` |
| **NVM is per-user** | Other users on the same server do not share this Node.js installation. This is intentional — it provides isolation |

---

## What This Script Does NOT Do

Be clear about the scope. You need to handle these separately:

- **Install Docker** — Docker is installed and managed by root separately. This script does not touch Docker.
- **Set up a database** — PostgreSQL, MySQL, MongoDB, Redis — install these as root after provisioning.
- **Point your domain** — Log into your domain registrar and set an A record pointing to your server IP.
- **Configure CI/CD** — GitHub Actions, GitLab CI, Bitbucket Pipelines — set these up in your repo settings.
- **Configure external alerting** — VictoriaMetrics and Cockpit provide metrics and live inspection; email/webhook alerts can be layered with vmalert.
- **Backup strategy** — No automated backup system is configured.

---

## Deploying Projects

### Node.js Project

```bash
# 1. SSH into server
ssh mojahid@your-server-ip

# 2. Clone your project from GitHub
git clone https://github.com/you/myapp.git ~/projects/myapp

# 3. Install dependencies
cd ~/projects/myapp
npm install

# 4. Create your environment file
nano .env

# 5. Start with PM2 on any free port
pm2 start app.js --name myapp -- --port 3000

# 6. Save PM2 state — REQUIRED for reboot survival
pm2 save

# 7. Add Nginx + free SSL in one command
sudo nginx_add_site -n myapp -d myapp.com -p 3000

# Visit https://myapp.com — done.
```

### Second Project (same server)

Just repeat the process with a different port and domain:

```bash
git clone https://github.com/you/blog.git ~/projects/blog
cd ~/projects/blog
npm install
nano .env
pm2 start server.js --name blog -- --port 4000
pm2 save
sudo nginx_add_site -n blog -d blog.com -p 4000
# Visit https://blog.com
```

Each project is completely independent:
- Different port → no conflicts
- Different Nginx config → different domain
- Different PM2 process → separate logs, separate restart
- They do not know about each other

### Update a Running Project

```bash
cd ~/projects/myapp
git pull origin main   # or: pull
npm install
pm2 restart myapp
pm2 save
```

---

## Shell Aliases Reference

All aliases are available immediately after login.

| Alias | Expands to | Category |
|---|---|---|
| `logs` | `pm2 logs` | PM2 |
| `pstatus` | `pm2 status` | PM2 |
| `prestart` | `pm2 restart all` | PM2 |
| `pmonit` | `pm2 monit` | PM2 |
| `psave` | `pm2 save` | PM2 |
| `pull` | `git pull origin main` | Git |
| `gs` | `git status` | Git |
| `gl` | `git log --oneline -10` | Git |
| `nginx-reload` | `sudo systemctl reload nginx` | Nginx |
| `nginx-test` | `sudo nginx -t` | Nginx |
| `nginx-logs` | `tail -f /var/log/nginx/*.log` | Nginx |
| `status` | `server_status` | Monitoring |

---

## File & Directory Reference

| Path | What it is |
|---|---|
| `/home/<user>/` | User home directory |
| `/home/<user>/.nvm/` | NVM installation + all Node.js versions |
| `/home/<user>/.pm2/` | PM2 data: config, logs, process list |
| `/home/<user>/.pm2/logs/` | PM2 app logs (rotated every 14 days) |
| `/home/<user>/.deploy_env` | Shell profile: aliases, NVM loader, prompt |
| `/etc/nginx/sites-available/` | Nginx config files — one per project |
| `/etc/nginx/sites-enabled/` | Symlinks to active configs |
| `/var/log/nginx/` | Nginx access and error logs (rotated every 30 days) |
| `/usr/local/bin/nginx_add_site` | Helper to add a new project to Nginx |
| `/usr/local/bin/server_status` | Quick server overview CLI tool |
| `/usr/local/bin/cockpit_add_origin` | CLI tool to register reverse proxy domains with Cockpit |
| `/etc/cockpit/cockpit.conf` | Cockpit web console configuration (port 9090) |
| `/etc/sudoers.d/90-<user>` | Sudo rules for the deploy user |
| `/etc/fail2ban/jail.d/node-provision.conf` | fail2ban SSH jail config |
| `/etc/sysctl.d/99-node-provision.conf` | Kernel hardening sysctl settings |
| `/etc/logrotate.d/<user>` | Log rotation rules for PM2 + Nginx logs |
| `/var/log/node_provision.log` | Full log of everything `init.sh` did |
| `~/.ssh/authorized_keys` | Installed SSH public keys |

---

## Common Tasks Reference

### Become root

```bash
# Step 1 — connect as your deploy user (direct root SSH is blocked)
ssh mojahid@your-server-ip

# Step 2 — switch to root
# sudo asks for MOJAHID'S password — NOT the root password
sudo -i

# Step 3 — when done, leave root
exit
```

> `sudo -i` asks for the **deploy user's own password** (the one set during provisioning). The root account's password is never needed or used.

### Check everything at a glance
```bash
server_status
```

### View logs
```bash
pm2 logs myapp                          # live logs for one app
pm2 logs                                # live logs for all apps
tail -f /var/log/nginx/myapp_access.log # Nginx access log for one site
nginx-logs                              # tail all Nginx logs
```

### Restart an app
```bash
pm2 restart myapp
pm2 save   # always save after changes
```

### Switch Node.js version
```bash
nvm install 22
nvm use 22
nvm alias default 22
pm2 restart all
pm2 save
```

### Add SSL to a site
```bash
sudo certbot --nginx -d myapp.com
```

### Renew SSL certificates (verify auto-renewal works)
```bash
sudo certbot renew --dry-run
```

### Open a custom firewall port
```bash
sudo ufw allow 8080/tcp
sudo ufw status
```

### Access Cockpit Web Console

#### Option A — Via SSH Tunnel (Default & Zero-Idle)
```bash
# Connect tunnel from your local computer:
ssh -L 9090:127.0.0.1:9090 mojahid@your-server-ip

# Then open in browser:
https://localhost:9090
```

#### Option B — Via Nginx Reverse Proxy (Domain Access, e.g. sv1.lunecode.com)
If you point a domain/subdomain to Cockpit via Nginx reverse proxy:
1. Register your domain in Cockpit's allowed origins:
```bash
sudo cockpit_add_origin sv1.lunecode.com
```
2. In your Nginx config, forward to `http://127.0.0.1:9090` with WebSocket support:
```nginx
location / {
    proxy_pass            http://127.0.0.1:9090;
    proxy_http_version    1.1;
    proxy_set_header      Host              $host;
    proxy_set_header      X-Real-IP         $remote_addr;
    proxy_set_header      X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header      X-Forwarded-Proto $scheme;
    proxy_set_header      Upgrade           $http_upgrade;
    proxy_set_header      Connection        "upgrade";
    proxy_read_timeout    86400s;
    proxy_buffering       off;
    gzip                  off;
}
```

### Check fail2ban bans
```bash
sudo fail2ban-client status sshd
```

### Add an SSH key after provisioning
```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub mojahid@your-server-ip
```

---

## Troubleshooting

### PM2 apps not coming back after reboot

```bash
# Most common cause — pm2 save was not run
pm2 save

# Check if the systemd service is enabled
sudo systemctl status pm2-<username>

# Re-enable if needed
sudo systemctl enable pm2-<username>
```

### Node.js or NVM command not found after login

```bash
# Reload the shell profile manually
source ~/.deploy_env

# Or just re-login
exit   # disconnect
ssh mojahid@your-server-ip   # reconnect — NVM loads automatically
```

### Nginx config test fails

```bash
sudo nginx -t        # shows the exact error and file/line number
sudo nginx -T        # shows full merged config for deeper inspection
```

### Port is already in use

```bash
sudo lsof -i :3000    # see what process is using port 3000
sudo kill <PID>       # stop it if needed
```

### SSL certificate fails (certbot error)

Usually means DNS is not pointed to the server yet.

```bash
# Skip SSL when adding the site
sudo nginx_add_site -n myapp -d myapp.com -p 3000 -s

# Point your domain A record to this server's IP, wait for propagation
# Then add SSL:
sudo certbot --nginx -d myapp.com
```

### Check the provision log

```bash
cat /var/log/node_provision.log
```

---

## Security Notes

- **Password login is enabled** — convenient but weaker than key-only. If you add your SSH public key via `-k`, consider disabling password auth later: edit `/etc/ssh/sshd_config`, set `PasswordAuthentication no`, reload sshd.
- **Root SSH login is permanently blocked** — `PermitRootLogin no`, `MaxAuthTries 4`, `PermitEmptyPasswords no`, and `X11Forwarding no` are enforced. To reach root: `ssh` as your deploy user, then `sudo -i`.
- **Firewall default deny on all ports** — UFW enforces `default deny incoming` and `default deny routed` across both IPv4 and IPv6 (`IPV6=yes`). Only explicitly approved ports (SSH, HTTP/S) are reachable.
- **Monitoring console is localhost-only** — Cockpit Web Console (9090) is bound strictly to `127.0.0.1`. Access is always via encrypted SSH port forwarding tunnel.
- **fail2ban is active** — 5 failed SSH attempts = 1 hour IP ban. Adjust in `/etc/fail2ban/jail.d/node-provision.conf`.
- **Nginx blocks secret files** — `.env`, `.git`, `.key`, `.pem`, `.sh` files are blocked at the Nginx level and return 404.
- **Kernel hardening is applied** — SYN flood, IP spoofing, IPv4/IPv6 ICMP redirects, IPv6 rogue router advertisements (RA), and symlink exploits are all mitigated via sysctl.