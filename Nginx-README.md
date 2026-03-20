# nginx-setup.sh

> Interactive, production-ready Nginx domain setup script — Static · Node.js · Laravel · PHP · Any App  
> acme.sh Multi-CA SSL · Dual-domain (no redirect) · File Upload · Security Hardened · Zero Interruption

---

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [System Requirements](#system-requirements)
- [Dependency Check & Auto-Install](#dependency-check--auto-install)
- [Features](#features)
- [SSL Options — Full Comparison](#ssl-options--full-comparison)
- [Supported Site Types](#supported-site-types)
- [Full Workflow — Phase by Phase](#full-workflow--phase-by-phase)
- [Generated Nginx Config — What Gets Written](#generated-nginx-config--what-gets-written)
- [File Upload Permissions](#file-upload-permissions)
- [Security Hardening Rules](#security-hardening-rules)
- [Directory Structure After Setup](#directory-structure-after-setup)
- [SSL Certificate Renewal](#ssl-certificate-renewal)
- [Pros & Cons](#pros--cons)
- [Known Limitations](#known-limitations)
- [Tested Environments](#tested-environments)
- [Troubleshooting](#troubleshooting)
- [Useful Commands After Setup](#useful-commands-after-setup)
- [FAQ](#faq)
- [License](#license)

---

## Overview

`nginx-setup.sh` is a fully interactive bash script that sets up a complete, production-hardened Nginx virtual host in a single terminal session. It handles everything from OS detection and package installation to SSL certificate issuance, security hardening, file upload configuration, and auto-renewal — with no manual config editing required.

Unlike other setup scripts, it never uses certbot and never rewrites your nginx config on SSL renewal. Certificates are managed by **acme.sh** — a pure shell ACME client with no Python, no Snap, and support for multiple Certificate Authorities.

```
sudo ./nginx-setup.sh
```

That is the only command you need.

---

## Quick Start

```bash
# 1. Download
curl -fsSL https://raw.githubusercontent.com/mojahid2021/Production-Server/main/nginx.sh \
  -o nginx.sh

# 2. Make executable
chmod +x nginx.sh

# 3. Run as root
sudo ./nginx.sh
```

The script will detect your OS, check and install all dependencies automatically, then walk you through 14 interactive phases.

---

## System Requirements

| Requirement | Minimum | Notes |
|---|---|---|
| OS | Ubuntu 20.04+ / Debian 10+ / CentOS 7+ / Arch | RHEL, AlmaLinux, Rocky also supported |
| Bash | 4.0+ | macOS default bash is 3.x — install via `brew install bash` |
| RAM | 512 MB | 1 GB+ recommended for PHP-FPM sites |
| Disk | 200 MB free | For Nginx, acme.sh, and certs |
| Network | Port 80 + 443 open | Required for Let's Encrypt HTTP-01 challenge |
| User | root / sudo | Script must run as root |

---

## Dependency Check & Auto-Install

Before asking a single question, the script runs a full **dependency pre-flight check**. Every tool is checked, and missing ones are installed automatically using the detected package manager.

| Tool | Purpose | Auto-install |
|---|---|---|
| `bash` 4+ | Script runtime | No — must be pre-installed |
| `curl` or `wget` | Download acme.sh | Yes |
| `openssl` | Self-signed certs, htpasswd hashing | Yes |
| `nginx` | Web server | Yes (prompted) |
| `cron` / `crond` | acme.sh auto-renewal | Yes |
| `systemctl` or `service` | Nginx reload on renewal | N/A — detects existing init |
| `socat` | acme.sh standalone mode fallback | Yes |
| `awk` `grep` `sed` `cut` `date` | Coreutils used throughout | Yes (via coreutils pkg) |
| `mktemp` | Temporary OpenSSL config files | Yes (via util-linux) |
| `htpasswd` | Basic authentication (only if enabled) | Yes, lazily — only when needed |
| `logrotate` | Nginx log rotation | Yes |
| `ufw` / `firewall-cmd` | Firewall port awareness | No — detected and reported only |

The output of the dependency check looks like this:

```
━━━  Dependency Check  ━━━

[OK]    bash 5.2.15(1)-release — ok
[OK]    curl 7.88.1 — ok
[OK]    openssl 3.0.2 — ok
[OK]    cron — ok
[OK]    systemctl — ok
[INFO]  socat not found — installing...
[OK]    socat installed.
[OK]    coreutils (awk, grep, sed, cut, date) — ok
[OK]    mktemp — ok
[INFO]  htpasswd not present — will install automatically if basic auth is enabled.
[OK]    logrotate — ok (optional)
[OK]    ufw — ok (firewall detected)
[INFO]  Ensure ports 80 and 443 are open: sudo ufw allow 'Nginx Full'

[OK]    Dependency check complete.
```

---

## Features

### Core

- **OS auto-detection** — supports `apt` (Debian/Ubuntu), `dnf` (Fedora/RHEL 8+), `yum` (CentOS/RHEL 7), `pacman` (Arch/Manjaro)
- **Nginx auto-install** — installs and enables nginx if not present
- **Dual-domain serving** — both `domain.com` and `www.domain.com` served from the same server block with no redirect between them
- **SAN SSL** — single certificate covers both bare domain and www (Subject Alternative Name)
- **Config backup** — existing `.conf` files are timestamped and backed up before overwrite
- **Document root auto-create** — creates the directory and a placeholder `index.html` / `index.php` immediately on input
- **Site symlink** — creates `sites-enabled/domain.conf → sites-available/domain.conf`
- **nginx -t guard** — nginx is only reloaded after a passing syntax test; broken configs never go live

### SSL

- **acme.sh** — pure shell ACME client, zero Python/Snap dependencies
- **Multi-CA auto-fallback** — Let's Encrypt → ZeroSSL → BuyPass Go SSL
- **SAN certificate** — single cert for both `domain.com` and `www.domain.com`
- **Auto-renewal** — daily cron at 3 AM, renews 30 days before expiry
- **Zero-downtime renewal** — uses `--reloadcmd "systemctl reload nginx"`, not restart
- **Stable cert path** — certs live at `/etc/ssl/acmesh/domain/` and never move
- **Config never modified on renewal** — acme.sh does not touch your nginx config
- **Self-signed SAN** — generates proper multi-domain self-signed cert via OpenSSL config file
- **TLS 1.2 + 1.3 only** — TLS 1.0 and 1.1 disabled
- **OCSP stapling** — enabled with resolver fallback
- **Session tickets** — disabled for forward secrecy

### Site Types

- **Static** — `try_files $uri $uri/ =404`
- **Reverse proxy** — port-based, with optional WebSocket upgrade headers
- **PHP-FPM** — framework-aware `try_files` for Laravel, WordPress, CodeIgniter, Symfony, raw PHP

### Performance

- **Gzip compression** — level 6, all major MIME types, `gzip_vary on`
- **Static asset caching** — 1-year expiry with `Cache-Control: public, immutable`
- **HTTP/2** — enabled on all SSL server blocks

### File Upload

- Configurable `client_max_body_size` (e.g. 50M)
- Configurable upload timeout
- Allowed file extension whitelist (pipe-separated)
- Dedicated upload directory with script execution disabled
- Blocks `.php`, `.php3`–`.php9`, `.phtml`, `.pl`, `.py`, `.jsp`, `.asp`, `.sh`, `.cgi`

### Security

Ten individually configurable rules:

1. Security response headers (CSP, X-Frame-Options, X-XSS-Protection, Referrer-Policy, Permissions-Policy, COOP, COEP)
2. `server_tokens off` — hides nginx version
3. Block hidden/dot files (`.env`, `.git`, `.htaccess`, `.aws`, `.npmrc`, `.dockerenv`, `.ssh`)
4. Block sensitive file types (`.sql`, `.log`, `.bak`, `.sh`, `.conf`, `.yml`, `.yaml`, `.swp`)
5. HTTP method restriction (returns 405 on violation)
6. Bad bot blocking (16 scanner/tool signatures, returns 444)
7. URI attack pattern blocking (SQLi, path traversal, XSS, LFI, RCE)
8. xmlrpc.php blocking (PHP sites — returns 444)
9. Buffer/header size limits (prevents buffer overflow attacks)
10. IP restriction on sensitive paths (e.g. `/admin`, `/wp-admin`)

### Logging & Auth

- Custom access log + error log paths
- HTTP Basic Authentication with `htpasswd` (apr1-hashed password)

---

## SSL Options — Full Comparison

The script offers 6 SSL providers:

| # | Provider | Cert validity | Auto-renew | Multi-CA | Notes |
|---|---|---|---|---|---|
| 1 | acme.sh — Let's Encrypt | 90 days | Yes (30d) | No | Most trusted CA globally |
| 2 | acme.sh — ZeroSSL | 90 days | Yes (30d) | No | Different infrastructure from LE |
| 3 | acme.sh — BuyPass Go SSL | **180 days** | Yes (30d) | No | Fewer renewals per year |
| **4** | **acme.sh — Multi-CA** | 90–180 days | **Yes** | **Yes** | **Recommended — zero interruption** |
| 5 | Self-signed | 365 days | No | No | Dev/testing only — browser warning |
| 6 | Manual / existing cert | Your cert | No | No | Bring your own cert files |

**Why Multi-CA (option 4) is recommended:**

If Let's Encrypt is rate-limited, has an outage, or DNS hasn't propagated yet, the script silently tries ZeroSSL, then BuyPass. Whichever CA succeeds first, the cert is installed to the same stable path. Your nginx config references that stable path and never changes.

**Why not certbot:**

| | certbot | acme.sh (this script) |
|---|---|---|
| Dependencies | Python + Snap | Pure shell — zero deps |
| Modifies nginx config | Yes, on every renewal | Never |
| CAs supported | Let's Encrypt only | LE + ZeroSSL + BuyPass |
| Renewal window | 60 days before expiry | 30 days before expiry |
| On renewal | `nginx restart` (brief downtime) | `nginx reload` (zero downtime) |
| Install method | System package / Snap | `curl \| sh` — user-space |

---

## Supported Site Types

### 1. Static files

Serves HTML, CSS, JS, images directly. Uses `try_files $uri $uri/ =404`. Suitable for:

- Plain HTML sites
- Frontend builds (React, Vue, Angular output)
- Documentation sites

### 2. Reverse proxy

Proxies all requests to a local backend process. You provide the **port number** (e.g. `3000`) and the script builds `http://127.0.0.1:3000`. Suitable for:

- **Node.js** (Express, Fastify, NestJS, Next.js, Nuxt.js)
- **Python** (Django, Flask, FastAPI via gunicorn/uvicorn)
- **Ruby** (Rails via Puma)
- **Go** (any HTTP server)
- **Java** (Spring Boot)
- **Rust** (Axum, Actix)
- Any process listening on a local port

Optional WebSocket upgrade headers for Socket.io, `ws://`, HMR, etc.

### 3. PHP-FPM

Routes PHP requests to a FastCGI socket. Framework-aware `try_files` pattern. Supported frameworks:

| Framework | try_files pattern |
|---|---|
| Laravel / Lumen | `/index.php?$query_string` |
| WordPress | `/index.php?$args` |
| CodeIgniter | `/index.php?$query_string` |
| Symfony | `/index.php?$query_string` |
| Raw PHP | `/index.php?$query_string` |

---

## Full Workflow — Phase by Phase

```
Phase  1  Boot          — Banner, root check, OS detection
Phase  2  Dependencies  — Auto-check and install all required tools
Phase  3  Nginx         — Check version or install nginx
Phase  4  Domain        — Domain name input, www handling choice
Phase  5  Site type     — Static / Proxy (port) / PHP (framework + socket)
Phase  6  SSL           — Provider choice, email, HTTP redirect, HSTS
Phase  7  Performance   — Gzip, static asset cache
Phase  8  Rate limits   — req/s per IP, connection limit per IP
Phase  9  Logging       — Custom log paths, basic auth, custom error pages
Phase 10  File upload   — Max size, timeout, allowed types, upload dir, exec lock
Phase 11  Security      — Gate question → 10 individual rules
Phase 12  Summary       — Full config table, final Y/N confirmation
Phase 13  Generate      — Write nginx config, create symlink
Phase 14  SSL cert      — Install acme.sh, issue cert (Multi-CA fallback)
Phase 15  Basic auth    — Create htpasswd file (if enabled)
Phase 16  Test & reload — nginx -t → nginx reload → final summary
```

Nothing is written to disk until Phase 13. You can abort at the summary (Phase 12) with no side effects, except that the document root and upload directory are created inline during Phases 5 and 10 respectively (with immediate `[OK]` confirmation).

---

## Generated Nginx Config — What Gets Written

The script generates a single file at `/etc/nginx/sites-available/domain.com.conf`.

A typical config for a reverse proxy with all features enabled looks like this:

```nginx
# =============================================================================
# Nginx config for: mojahid.com www.mojahid.com
# Site type  : proxy
# Backend    : http://127.0.0.1:3000
# SSL        : acmesh / multi
# Generated  : Fri 17 Jan 2025
# =============================================================================

server_tokens off;

client_body_buffer_size     16k;
client_header_buffer_size    4k;
large_client_header_buffers  4 16k;
client_header_timeout        10s;
keepalive_timeout            65s;

gzip on;
gzip_vary on;
gzip_comp_level 6;
# ... (all mime types)

limit_req_zone $binary_remote_addr zone=mojahid_com_req:10m rate=10r/s;

map $http_user_agent $bad_bot {
    default 0;
    ~*masscan 1; ~*nikto 1; ~*sqlmap 1; # ... 16 total
    "" 1;
}

# HTTP → HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name mojahid.com www.mojahid.com;

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
        allow all;
    }
    location / { return 301 https://$host$request_uri; }
}

# Main server block — handles both mojahid.com and www.mojahid.com
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name mojahid.com www.mojahid.com;
    root /var/www/mojahid.com/public;

    # Certs managed by acme.sh — never modified on renewal
    ssl_certificate     /etc/ssl/acmesh/mojahid.com/fullchain.pem;
    ssl_certificate_key /etc/ssl/acmesh/mojahid.com/privkey.pem;

    ssl_protocols             TLSv1.2 TLSv1.3;
    ssl_session_tickets       off;
    ssl_stapling              on;

    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Content-Security-Policy "default-src 'self'; ..." always;
    # ... 9 security headers total

    if ($bad_bot) { return 444; }
    if ($request_uri ~* "(union.*select|...)") { return 403; }
    # ... 5 attack pattern blocks

    limit_req  zone=mojahid_com_req burst=20 nodelay;
    limit_req_status 429;

    client_max_body_size 50M;

    error_page 400 /400.html;
    error_page 404 /404.html;

    location ~* \.(jpg|jpeg|png|...)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    location ~ /\. { deny all; return 404; }
    location ~* \.(sql|log|bak|sh|...)$ { deny all; return 404; }

    location ~ ^/api/admin(/|$) {
        allow 192.168.1.10;
        allow 127.0.0.1;
        deny  all;
    }

    location ~* ^/uploads/ {
        location ~* \.(php|php[3-9]|sh|py|...)$ { deny all; return 403; }
        location ~* \.(jpg|jpeg|png|...|gz)$     { try_files $uri =404; }
        location / { return 403; }
    }

    location / {
        proxy_pass            http://127.0.0.1:3000;
        proxy_http_version    1.1;
        proxy_set_header      Host              $host;
        proxy_set_header      X-Real-IP         $remote_addr;
        proxy_set_header      X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header      X-Forwarded-Proto $scheme;
        proxy_read_timeout    90s;
        proxy_buffering       off;
    }
}
```

---

## File Upload Permissions

When file upload is enabled, the script configures:

```nginx
# Global — applies to all locations
client_max_body_size  50M;
client_body_timeout   60s;
proxy_read_timeout    60s;
proxy_send_timeout    60s;

# Upload directory — execution completely disabled
location ~* ^/uploads/ {
    # Block all script execution
    location ~* \.(php|php3|php4|php5|php7|phtml|pl|py|jsp|asp|sh|cgi)$ {
        deny all;
        return 403;
    }
    # Only whitelisted extensions are served
    location ~* \.(jpg|jpeg|png|gif|webp|pdf|doc|docx|xls|xlsx|zip|tar|gz)$ {
        try_files $uri =404;
    }
    # Everything else blocked
    location / {
        return 403;
    }
}
```

This prevents the most common upload-based attack vector: uploading a `.php` shell disguised as an image, then executing it via direct URL.

---

## Security Hardening Rules

### Security headers (when enabled)

```nginx
add_header X-Frame-Options                   "SAMEORIGIN"                       always;
add_header X-Content-Type-Options            "nosniff"                          always;
add_header X-XSS-Protection                  "1; mode=block"                    always;
add_header Referrer-Policy                   "strict-origin-when-cross-origin"  always;
add_header Permissions-Policy                "camera=(), microphone=(), geolocation=()" always;
add_header Content-Security-Policy           "default-src 'self'; ..."          always;
add_header X-Permitted-Cross-Domain-Policies "none"                             always;
add_header Cross-Origin-Opener-Policy        "same-origin"                      always;
add_header Cross-Origin-Embedder-Policy      "require-corp"                     always;
```

### Bad bot map (16 signatures)

Blocks: `masscan`, `nikto`, `sqlmap`, `nmap`, `zgrab`, `nuclei`, `dirbuster`, `dirb`, `gobuster`, `hydra`, `metasploit`, `w3af`, `acunetix`, `qualys`, `nessus`, `openvas`, `python-requests`, `go-http-client`, and empty user-agents.  
Returns HTTP `444` (connection closed without response).

### URI attack patterns blocked

- SQL injection: `union select`, `drop table`, `insert into`, `exec(`, etc.
- Path traversal: `../`, `%2e%2e%2f`, `%252e%252e`, `..%2f`
- XSS in URI: `<script`, `javascript:`, `vbscript:`, `onload=`, `onerror=`
- Local file inclusion: `etc/passwd`, `etc/shadow`, `proc/self`, `boot.ini`
- Remote code execution: `base64_decode`, `eval(`, `system(`, `passthru(`, `shell_exec(`

### Buffer overflow protection

```nginx
client_body_buffer_size     16k;
client_header_buffer_size    4k;
large_client_header_buffers  4 16k;
client_header_timeout        10s;
client_body_timeout          10s;
send_timeout                 10s;
```

---

## Directory Structure After Setup

```
/etc/nginx/
├── sites-available/
│   └── domain.com.conf          ← generated config
│   └── domain.com.conf.bak.*    ← timestamped backup (if overwrite)
├── sites-enabled/
│   └── domain.com.conf          ← symlink to sites-available
└── .htpasswd_domain_com         ← basic auth file (if enabled)

/etc/ssl/acmesh/
└── domain.com/
    ├── fullchain.pem             ← referenced by nginx
    ├── privkey.pem               ← referenced by nginx
    └── cert.pem

/etc/ssl/selfsigned/              ← only for self-signed mode
└── domain.com.crt
└── domain.com.key

/var/www/
└── domain.com/
    └── public/                   ← document root
        ├── index.html            ← placeholder (static)
        ├── index.php             ← placeholder (PHP)
        └── uploads/              ← upload dir (if enabled)

/var/www/letsencrypt/
└── .well-known/
    └── acme-challenge/           ← HTTP-01 ACME challenge webroot

/root/.acme.sh/                   ← acme.sh install directory
└── acme.sh                       ← the client script
└── domain.com_ecc/               ← raw cert storage (internal to acme.sh)

/var/log/nginx/
├── domain.com-access.log
└── domain.com-error.log
```

---

## SSL Certificate Renewal

Renewal is fully automatic. The cron entry added by the script:

```cron
0 3 * * * "/root/.acme.sh/acme.sh" --cron --home "/root/.acme.sh" > /dev/null 2>&1
```

This runs daily at 3 AM. acme.sh checks if any cert is within 30 days of expiry. If so it:

1. Issues a new certificate from the same CA
2. Copies it to `/etc/ssl/acmesh/domain.com/`
3. Runs `systemctl reload nginx` — zero downtime

**The nginx config is never touched during renewal.**

To test renewal manually:

```bash
~/.acme.sh/acme.sh --cron --home ~/.acme.sh

# Or force-renew a specific domain:
~/.acme.sh/acme.sh --renew -d domain.com --force
```

To view all certs and their expiry dates:

```bash
~/.acme.sh/acme.sh --list
```

---

## Pros & Cons

### Pros

| | Detail |
|---|---|
| Zero certbot dependency | No Python, no Snap, no system packages for SSL |
| Multi-CA fallback | If Let's Encrypt fails, ZeroSSL or BuyPass issues the cert automatically |
| Never rewrites nginx config | Renewal is purely cert-file replacement + nginx reload |
| Zero downtime renewal | `nginx reload` keeps existing connections alive |
| Dual-domain SAN | One cert, one server block, two hostnames — no redirect tax |
| Fully interactive | Every feature is a Y/N prompt — nothing is forced on you |
| Framework-aware PHP config | Laravel/WordPress/CodeIgniter each get the correct `try_files` |
| Port-based proxy | Just enter a port number — no need to construct proxy_pass manually |
| Upload exec isolation | Upload directory is locked down — no PHP execution possible |
| 10 individual security rules | Enable exactly what you need — no all-or-nothing |
| Config backup | Existing configs backed up before overwrite |
| Runs on 4 distro families | Debian/Ubuntu, RHEL/CentOS, Fedora, Arch |
| Auto-installs everything | All dependencies checked and installed upfront |
| nginx -t guard | Nginx never reloaded with a broken config |

### Cons

| | Detail |
|---|---|
| Root required | Must run as root — cannot be used in restricted environments |
| HTTP-01 challenge only | Does not support DNS-01 challenge — wildcard certs (`*.domain.com`) not covered |
| Single domain per run | One domain per execution — run again for additional domains |
| No IPv6-specific tuning | `listen [::]:443` is added but no advanced IPv6 configuration |
| CSP is permissive | Default Content-Security-Policy includes `'unsafe-inline'` — needs manual tightening for strict CSP |
| No WAF | URI pattern blocking is basic regex — not a full Web Application Firewall |
| acme.sh from get.acme.sh | Requires internet access during install — air-gapped servers need manual acme.sh install |
| No multi-server support | No built-in upstream load balancing block — single backend only |
| BuyPass 180-day certs | BuyPass has rate limits stricter than Let's Encrypt for high-volume use |

---

## Known Limitations

- **macOS is not supported** — designed for Linux servers only. macOS uses `brew` and has a different nginx layout.
- **Snap-based systems** — if your Ubuntu uses snap-installed nginx, the `sites-available` directory may be in a different location. Remove snap nginx first: `snap remove nginx`.
- **Docker containers** — `systemctl` may not be available inside containers. Use `service nginx reload` or configure your own restart mechanism.
- **CloudFlare / reverse proxy in front** — if your server is behind CloudFlare, the HTTP-01 ACME challenge may fail. Use the CloudFlare DNS API with acme.sh's `--dns dns_cf` mode (requires manual setup outside this script).
- **SELinux** — on CentOS/RHEL with SELinux enforcing, nginx may not be able to connect to backend ports. Run `setsebool -P httpd_can_network_connect 1`.
- **Firewall** — the script detects ufw/firewalld and prints the command to open ports, but does not open them automatically to avoid unintended changes.

---

## Tested Environments

| OS | Version | Package manager | Status |
|---|---|---|---|
| Ubuntu | 20.04 LTS | apt | Tested |
| Ubuntu | 22.04 LTS | apt | Tested |
| Ubuntu | 24.04 LTS | apt | Tested |
| Debian | 10 (Buster) | apt | Tested |
| Debian | 11 (Bullseye) | apt | Tested |
| Debian | 12 (Bookworm) | apt | Tested |
| CentOS | 7 | yum | Tested |
| AlmaLinux | 8 / 9 | dnf | Tested |
| Rocky Linux | 8 / 9 | dnf | Tested |
| Fedora | 38+ | dnf | Tested |
| Arch Linux | rolling | pacman | Tested |

---

## Troubleshooting

### Nginx config test fails

```bash
sudo nginx -t
# Read the error message — it tells you exactly which line is wrong.
# The config is at:
cat /etc/nginx/sites-available/domain.com.conf
```

### Let's Encrypt certificate fails

```bash
# Check DNS is pointing to this server
dig +short mojahid.com

# Check port 80 is open
curl -v http://mojahid.com/.well-known/acme-challenge/test

# Check ufw
sudo ufw allow 'Nginx Full'
sudo ufw status

# Retry manually
~/.acme.sh/acme.sh --issue --server letsencrypt \
  --webroot /var/www/letsencrypt \
  -d mojahid.com -d www.mojahid.com \
  --keylength ec-256
```

### acme.sh not found after install

```bash
# Source the env file
source ~/.acme.sh/acme.sh.env

# Or use full path
~/.acme.sh/acme.sh --version
```

### Proxy returns 502 Bad Gateway

```bash
# Check your backend is running
curl http://127.0.0.1:3000

# Check nginx error log
tail -50 /var/log/nginx/domain.com-error.log

# On SELinux systems:
setsebool -P httpd_can_network_connect 1
```

### PHP-FPM returns 502

```bash
# Check FPM is running
systemctl status php8.2-fpm

# Check the socket path matches your config
ls -la /run/php/

# Common correct socket paths:
# Ubuntu 22.04:  unix:/run/php/php8.2-fpm.sock
# Ubuntu 20.04:  unix:/run/php/php8.0-fpm.sock
# CentOS:        127.0.0.1:9000
```

### Upload returns 413 Request Entity Too Large

```bash
# Check the limit in your config
grep client_max_body_size /etc/nginx/sites-available/domain.com.conf

# Also check PHP's upload limits if using PHP-FPM:
# /etc/php/8.2/fpm/php.ini
# upload_max_filesize = 50M
# post_max_size = 50M
```

### Rate limiting is blocking legitimate traffic

```bash
# Check the current rate limit zone
grep limit_req /etc/nginx/sites-available/domain.com.conf

# Temporarily disable by commenting the line:
# limit_req  zone=...

# Or increase the burst value
```

---

## Useful Commands After Setup

```bash
# Test nginx config syntax
sudo nginx -t

# Reload nginx (zero downtime — applies config changes)
sudo systemctl reload nginx

# Restart nginx (brief interruption)
sudo systemctl restart nginx

# Check nginx status
sudo systemctl status nginx

# View live error log
tail -f /var/log/nginx/domain.com-error.log

# View live access log
tail -f /var/log/nginx/domain.com-access.log

# List all acme.sh certificates and expiry dates
~/.acme.sh/acme.sh --list

# Manually trigger renewal check
~/.acme.sh/acme.sh --cron --home ~/.acme.sh

# Force-renew a specific domain
~/.acme.sh/acme.sh --renew -d domain.com --force

# View current crontab
crontab -l

# Check nginx is listening on ports 80 and 443
ss -tlnp | grep nginx

# Test SSL certificate
openssl s_client -connect domain.com:443 -servername domain.com 2>/dev/null \
  | openssl x509 -noout -dates -subject -issuer

# Check SSL grade (requires internet)
curl -s "https://api.ssllabs.com/api/v3/analyze?host=domain.com" | python3 -m json.tool
```

---

## FAQ

**Q: Can I run the script multiple times for different domains?**  
A: Yes. Each run creates a separate `.conf` file named after the domain. Run it once per domain.

**Q: Will re-running for the same domain overwrite my config?**  
A: The existing config is backed up as `domain.com.conf.bak.YYYYMMDDHHMMSS` before overwriting.

**Q: Does the script work on a VPS with only 512 MB RAM?**  
A: Yes, for static and proxy sites. PHP-FPM sites with opcache may need 1 GB+.

**Q: Can I use a wildcard certificate (`*.domain.com`)?**  
A: Not through this script — wildcard certs require DNS-01 challenge which needs API access to your DNS provider. You can do this manually with acme.sh after setup.

**Q: Does both `domain.com` and `www.domain.com` serve the exact same content?**  
A: Yes. Both names are in the same `server_name` directive and the same `root`. There is no redirect between them. Google treats them as separate URLs — if you want canonical SEO, add a canonical link tag in your HTML.

**Q: What happens if Let's Encrypt rate-limits my domain?**  
A: With Multi-CA mode, the script automatically tries ZeroSSL, then BuyPass. Let's Encrypt rate limits are per-domain per week (5 duplicate certs max). ZeroSSL and BuyPass have independent limits.

**Q: Can I change the SSL provider later?**  
A: Yes. Remove the existing cert and re-issue with a different CA:
```bash
~/.acme.sh/acme.sh --remove -d domain.com
~/.acme.sh/acme.sh --issue --server zerossl --webroot /var/www/letsencrypt -d domain.com
```

**Q: Is this script safe to run on a production server?**  
A: The script backs up existing configs, never modifies nginx on SSL renewal, and only reloads nginx after a passing `nginx -t`. The main risk is the security headers — particularly `Cross-Origin-Embedder-Policy: require-corp` which can break sites embedding cross-origin resources. Review and adjust headers after setup if needed.

**Q: Why is `server_tokens off` a top-level directive and not inside the server block?**  
A: `server_tokens` can be set at `http`, `server`, or `location` context. Setting it at the top level applies it globally to all virtual hosts, which is the more secure default.

---

## License

MIT License — free to use, modify, and distribute.

---

*nginx-setup.sh v4 — built for production servers, not tutorials.*