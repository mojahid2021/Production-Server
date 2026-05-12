#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  nginx.sh  —  Interactive Nginx Domain Setup  v4.0.0                         ║
# ║  Ubuntu 20.04 / 22.04 / 24.04 LTS                                           ║
# ╠══════════════════════════════════════════════════════════════════════════════╣
# ║                                                                              ║
# ║  WHAT THIS DOES                                                              ║
# ║  01. Preflight  — root check, OS detection, dependency check                 ║
# ║  02. Domain     — configure domain, www handling, conflict resolution        ║
# ║  03. Site Type  — Static files, Reverse Proxy, PHP-FPM                       ║
# ║  04. SSL        — acme.sh (Let's Encrypt / ZeroSSL / BuyPass), self-signed   ║
# ║  05. Performance — Gzip, static-asset caching                                ║
# ║  06. Rate Limits — per-IP request rate & connection limiting                 ║
# ║  07. Logging & Auth — custom log paths, HTTP basic authentication            ║
# ║  08. File Upload — size limits, allowed types, upload directory              ║
# ║  09. Security   — headers, bot blocking, method limiting, IP restriction     ║
# ║  10. Generate & apply Nginx config                                           ║
# ║  11. SSL provisioning (acme.sh multi-CA with auto-renewal cron)              ║
# ║  12. Test & reload Nginx                                                     ║
# ║                                                                              ║
# ╠══════════════════════════════════════════════════════════════════════════════╣
# ║                                                                              ║
# ║  USAGE                                                                       ║
# ║    sudo ./nginx.sh                    (interactive — recommended)            ║
# ║                                                                              ║
# ║  SSL PROVIDERS                                                               ║
# ║    acme.sh  Let's Encrypt → ZeroSSL → BuyPass Go SSL  (multi-CA fallback)   ║
# ║    Auto-renews every 30 days · nginx reloaded silently · config never touched║
# ║                                                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  CONFIG
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

readonly SCRIPT_VERSION="4.0.0"
readonly LOG_FILE="/var/log/nginx_provision.log"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  COLORS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [[ -t 1 ]] && tput colors &>/dev/null && (( $(tput colors) >= 8 )); then
    R=$'\033[0m'  BOLD=$'\033[1m'  DIM=$'\033[2m'
    GRN=$'\033[38;5;82m'   BLU=$'\033[38;5;33m'   CYN=$'\033[38;5;45m'
    YLW=$'\033[38;5;220m'  PRP=$'\033[38;5;135m'
    WHT=$'\033[38;5;255m'  GRY=$'\033[38;5;244m'  RED=$'\033[38;5;196m'
    TICK="${GRN}✔${R}"  CROSS="${RED}✘${R}"  WARN_IC="${YLW}⚠${R}"
    ARROW="${CYN}›${R}"  BULLET="${PRP}◆${R}"
else
    R='' BOLD='' DIM='' GRN='' BLU='' CYN='' YLW='' PRP='' WHT='' GRY='' RED=''
    TICK='[OK]' CROSS='[ERR]' WARN_IC='[WARN]' ARROW='->' BULLET='*'
fi

# Aliases — preserve compatibility with existing code in this script
GREEN="$GRN"; RESET="$R"; CYAN="$CYN"; YELLOW="$YLW"; BLUE="$BLU"

readonly HR2="════════════════════════════════════════════════════════════════════════════"
readonly HR="────────────────────────────────────────────────────────────────────────────"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  OUTPUT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

_log()    { printf '[%s] [%-5s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >> "$LOG_FILE" 2>/dev/null || true; }
info()    { echo -e "  ${ARROW}  ${GRY}$*${R}";              _log INFO  "$*"; }
success() { echo -e "  ${TICK}  $*";                         _log INFO  "$*"; }
warn()    { echo -e "  ${WARN_IC}  ${YLW}$*${R}";            _log WARN  "$*"; }
error()   { echo -e "  ${CROSS}  ${RED}$*${R}" >&2;          _log ERROR "$*"; }
die()     { echo -e "\n  ${CROSS}  ${RED}${BOLD}FATAL: $*${R}\n" >&2; _log ERROR "$*"; exit 1; }

banner() {
    clear
    echo ""
    echo -e "${BLU}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${BLU}${BOLD}║${R}${WHT}${BOLD}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  🚀  nginx.sh  —  Nginx Domain Setup Script  v${SCRIPT_VERSION}"
    printf  "  ${BLU}${BOLD}║${R}${GRY}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  Ubuntu 20.04 / 22.04 / 24.04 LTS  ·  Static · Node.js · Laravel · PHP"
    echo -e "${BLU}${BOLD}  ╠${HR2}╣${R}"
    printf  "  ${BLU}${BOLD}║${R}${GRN}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  acme.sh SSL  ·  Let's Encrypt → ZeroSSL → BuyPass Go SSL  (Multi-CA)"
    printf  "  ${BLU}${BOLD}║${R}${GRY}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  Auto-renews every 30 days · nginx reloaded silently · config never touched"
    echo -e "${BLU}${BOLD}  ╠${HR2}╣${R}"
    printf  "  ${BLU}${BOLD}║${R}${DIM}${GRY}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  github.com/mojahid2021/Production-Server"
    echo -e "${BLU}${BOLD}  ╚${HR2}╝${R}"
    echo ""
}

ask_yes_no() {
  local prompt="$1" default="${2:-n}" yn_hint
  [[ "$default" == "y" ]] && yn_hint="[Y/n]" || yn_hint="[y/N]"
  while true; do
    read -rp "$(echo -e "${YELLOW}?${RESET} ${prompt} ${yn_hint}: ")" choice
    choice="${choice:-$default}"
    case "${choice,,}" in y|yes) return 0 ;; n|no) return 1 ;; *) warn "Please enter y or n." ;; esac
  done
}

ask_input() {
  local prompt="$1" default="${2:-}" hint=""
  [[ -n "$default" ]] && hint=" (default: ${default})"
  read -rp "$(echo -e "${CYAN}→${RESET} ${prompt}${hint}: ")" val
  echo "${val:-$default}"
}

section()     { echo ""; echo -e "  ${BLU}${BOLD}┌─ $*${R}"; echo -e "  ${BLU}${DIM}│${R}"; }
section_end() { echo -e "  ${BLU}${DIM}└${HR:0:60}${R}"; echo ""; }
divider()     { echo -e "  ${BLU}${DIM}${HR:0:60}${R}"; }
sub_info()    { echo -e "    ${GRY}${*}${R}"; }

ensure_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
    chown -R www-data:www-data "$dir" 2>/dev/null || true
    chmod 755 "$dir"
    success "Directory created: ${dir}"
  fi
}

# ─── Root check ───────────────────────────────────────────────────────────────
check_root() {
  if [[ "$EUID" -ne 0 ]]; then
    die "Run as root: sudo ./nginx-setup.sh"
  fi
}

# ─── Detect OS ────────────────────────────────────────────────────────────────
detect_os() {
  if   command -v apt-get &>/dev/null; then PKG_MGR="apt";    OS_FAMILY="debian"
  elif command -v dnf     &>/dev/null; then PKG_MGR="dnf";    OS_FAMILY="rhel"
  elif command -v yum     &>/dev/null; then PKG_MGR="yum";    OS_FAMILY="rhel"
  elif command -v pacman  &>/dev/null; then PKG_MGR="pacman"; OS_FAMILY="arch"
  else die "Unsupported OS — cannot detect package manager."; fi
  info "Detected: ${PKG_MGR} (${OS_FAMILY})"
}

# ─── Dependency pre-flight check & auto-install ───────────────────────────────
#
#  Checks every tool the script may need and installs missing ones upfront.
#  Nothing interactive — fully automatic with progress reporting.
#
check_dependencies() {
  section "Dependency Check"

  # ── Helper: install a package ───────────────────────────────────────────────
  pkg_install() {
    local pkg_apt="$1" pkg_dnf="${2:-$1}" pkg_pac="${3:-$1}"
    case "$PKG_MGR" in
      apt)    apt-get install -y "$pkg_apt"  2>&1 | grep -E '(Setting up|already)' || true ;;
      dnf)    dnf     install -y "$pkg_dnf"  2>&1 | grep -E '(Installed|already)'  || true ;;
      yum)    yum     install -y "$pkg_dnf"  2>&1 | grep -E '(Installed|already)'  || true ;;
      pacman) pacman  -Sy --noconfirm "$pkg_pac" 2>&1 | grep -E '(installing|up to date)' || true ;;
    esac
  }

  # ── 1. bash >= 4 ────────────────────────────────────────────────────────────
  local bash_ver="${BASH_VERSINFO[0]:-0}"
  if (( bash_ver < 4 )); then
    die "Bash 4+ required (found bash ${bash_ver}). On macOS run: brew install bash"
  fi
  success "bash ${BASH_VERSION} — ok"

  # ── 2. curl or wget (for acme.sh download) ──────────────────────────────────
  if command -v curl &>/dev/null; then
    success "curl $(curl --version 2>/dev/null | head -1 | awk '{print $2}') — ok"
  elif command -v wget &>/dev/null; then
    success "wget $(wget --version 2>/dev/null | head -1 | awk '{print $3}') — ok"
  else
    warn "Neither curl nor wget found — installing curl..."
    case "$PKG_MGR" in
      apt)    apt-get update -qq && apt-get install -y curl ;;
      dnf|yum) ${PKG_MGR} install -y curl ;;
      pacman) pacman -Sy --noconfirm curl ;;
    esac
    command -v curl &>/dev/null && success "curl installed." || die "Failed to install curl."
  fi

  # ── 3. openssl (cert generation + htpasswd hashing) ─────────────────────────
  if command -v openssl &>/dev/null; then
    success "openssl $(openssl version 2>/dev/null | awk '{print $2}') — ok"
  else
    warn "openssl not found — installing..."
    pkg_install openssl openssl openssl
    command -v openssl &>/dev/null && success "openssl installed." || die "Failed to install openssl."
  fi

  # ── 4. cron daemon (acme.sh auto-renewal) ────────────────────────────────────
  local cron_ok=false
  for cron_cmd in crontab crond cron; do
    command -v "$cron_cmd" &>/dev/null && { cron_ok=true; break; }
  done
  if $cron_ok; then
    success "cron — ok"
  else
    warn "cron not found — installing..."
    case "$PKG_MGR" in
      apt)    apt-get install -y cron && systemctl enable cron  2>/dev/null || true ;;
      dnf|yum) ${PKG_MGR} install -y cronie && systemctl enable crond 2>/dev/null || true ;;
      pacman) pacman -Sy --noconfirm cronie && systemctl enable cronie 2>/dev/null || true ;;
    esac
    command -v crontab &>/dev/null && success "cron installed." || warn "Could not install cron — auto-renewal may not work."
  fi

  # ── 5. systemctl / service (init system) ─────────────────────────────────────
  if command -v systemctl &>/dev/null; then
    success "systemctl — ok"
  elif command -v service &>/dev/null; then
    success "service (SysV init) — ok"
  else
    warn "No systemctl or service found — nginx reload may require manual intervention."
  fi

  # ── 6. socat (optional, used by acme.sh standalone mode) ─────────────────────
  if command -v socat &>/dev/null; then
    success "socat — ok (optional)"
  else
    info "socat not found — installing (used by acme.sh standalone mode)..."
    pkg_install socat socat socat
    command -v socat &>/dev/null && success "socat installed." || warn "socat not available — acme.sh will use webroot mode only."
  fi

  # ── 7. coreutils: awk, grep, sed, cut, date ──────────────────────────────────
  local core_ok=true
  for tool in awk grep sed cut date; do
    if ! command -v "$tool" &>/dev/null; then
      warn "Missing coreutil: ${tool}"
      core_ok=false
    fi
  done
  $core_ok && success "coreutils (awk, grep, sed, cut, date) — ok"

  # ── 8. util-linux: mktemp ────────────────────────────────────────────────────
  if command -v mktemp &>/dev/null; then
    success "mktemp — ok"
  else
    warn "mktemp not found — installing util-linux..."
    pkg_install util-linux util-linux util-linux
  fi

  # ── 9. apache2-utils / httpd-tools (htpasswd — only if basic auth will be used)
  #       Not required upfront; we check/install it lazily in handle_basic_auth().
  #       Just report its current status here.
  if command -v htpasswd &>/dev/null; then
    success "htpasswd — ok (basic auth ready)"
  else
    info "htpasswd not present — will install automatically if basic auth is enabled."
  fi

  # ── 10. logrotate (optional — for nginx log rotation) ────────────────────────
  if command -v logrotate &>/dev/null; then
    success "logrotate — ok (optional)"
  else
    info "logrotate not found — installing (recommended for log management)..."
    pkg_install logrotate logrotate logrotate
    command -v logrotate &>/dev/null && success "logrotate installed." || warn "logrotate not available."
  fi

  # ── 11. ufw / firewalld (optional — firewall awareness) ──────────────────────
  if command -v ufw &>/dev/null; then
    success "ufw — ok (firewall detected)"
    if ask_yes_no "Automatically open nginx ports (80/443) in UFW?" "y"; then
      ufw allow 'Nginx Full' 2>/dev/null && success "Nginx ports (80/443) opened in UFW." || warn "Failed to open nginx ports in UFW."
    else
      info "Ensure ports 80 and 443 are open: sudo ufw allow 'Nginx Full'"
    fi
  elif command -v firewall-cmd &>/dev/null; then
    success "firewalld — ok (firewall detected)"
    if ask_yes_no "Automatically open nginx ports (80/443) in firewalld?" "y"; then
      firewall-cmd --add-service=http --add-service=https --permanent 2>/dev/null && \
      firewall-cmd --reload 2>/dev/null && \
      success "Nginx ports (80/443) opened in firewalld." || warn "Failed to open nginx ports in firewalld."
    else
      info "Ensure ports open: firewall-cmd --add-service=http --add-service=https --permanent"
    fi
  else
    info "No ufw/firewalld detected — ensure ports 80 and 443 are open manually."
  fi

  echo ""
  success "Dependency check complete."
  divider
}

# ─── Install Nginx ────────────────────────────────────────────────────────────
install_nginx() {
  if command -v nginx &>/dev/null; then
    NGINX_VERSION=$(nginx -v 2>&1 | grep -o '[0-9][^ ]*')
    success "Nginx already installed — version ${NGINX_VERSION}"
    return
  fi
  warn "Nginx is NOT installed."
  ask_yes_no "Install Nginx now?" "y" || die "Nginx required. Exiting."
  info "Installing Nginx..."
  case "$PKG_MGR" in
    apt)    apt-get update -qq && apt-get install -y nginx ;;
    dnf)    dnf install -y nginx    && systemctl enable nginx ;;
    yum)    yum install -y epel-release && yum install -y nginx && systemctl enable nginx ;;
    pacman) pacman -Sy --noconfirm nginx && systemctl enable nginx ;;
  esac
  success "Nginx installed."
}

# ─── Install acme.sh ──────────────────────────────────────────────────────────
install_acmesh() {
  ACMESH_BIN="${HOME}/.acme.sh/acme.sh"
  ACMESH_DIR="${HOME}/.acme.sh"

  if [[ -f "$ACMESH_BIN" ]]; then
    local ver; ver=$("$ACMESH_BIN" --version 2>/dev/null | head -1 || echo "unknown")
    success "acme.sh already installed — ${ver}"
    return
  fi

  info "Installing acme.sh (pure-shell ACME client, zero dependencies)..."

  # Ensure curl or wget is available
  if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
    info "Installing curl..."
    case "$PKG_MGR" in
      apt)    apt-get install -y curl ;;
      dnf|yum) ${PKG_MGR} install -y curl ;;
      pacman) pacman -Sy --noconfirm curl ;;
    esac
  fi

  # Install acme.sh without running as a service — we manage the cron ourselves.
  # Download the actual acme.sh script directly (not the get.acme.sh wrapper).
  # Using the wrapper via "sh get.acme.sh --home DIR" causes "Unknown parameter: ----home"
  # because the wrapper appends "-- $@" when calling the installer, doubling the dashes.
  # acme.sh's --install routine does `cp acme.sh` (relative path) to copy itself,
  # so the downloaded file MUST be named "acme.sh" inside a dedicated temp directory.
  local _tmp_dir; _tmp_dir="$(mktemp -d)"
  local _acme_installer="${_tmp_dir}/acme.sh"
  local _acme_url="https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh"
  if command -v curl &>/dev/null; then
    curl -fsSL "$_acme_url" -o "$_acme_installer" 2>&1 \
      || { rm -rf "$_tmp_dir"; die "Failed to download acme.sh installer. Check internet connectivity."; }
  else
    wget -qO "$_acme_installer" "$_acme_url" 2>&1 \
      || { rm -rf "$_tmp_dir"; die "Failed to download acme.sh installer. Check internet connectivity."; }
  fi
  (cd "$_tmp_dir" && sh acme.sh --install --home "$ACMESH_DIR" \
    --accountemail "${ACME_EMAIL:-admin@example.com}" --no-cron 2>&1 | tail -5)
  rm -rf "$_tmp_dir"

  # Re-source so the alias is available in this session
  # shellcheck source=/dev/null
  [[ -f "${ACMESH_DIR}/acme.sh.env" ]] && source "${ACMESH_DIR}/acme.sh.env" 2>/dev/null || true

  if [[ ! -f "$ACMESH_BIN" ]]; then
    die "acme.sh installation failed. Check internet connectivity and try again."
  fi
  success "acme.sh installed: ${ACMESH_BIN}"
}

# ─── STEP 1 — Domain & www ────────────────────────────────────────────────────

# Purge everything for a domain: nginx config, SSL cert, doc root, acme.sh cert
purge_domain() {
  local d="$1"
  warn "Removing all existing configuration for: ${d}"

  # Nginx config & symlink
  local conf="/etc/nginx/sites-available/${d}.conf"
  local link="/etc/nginx/sites-enabled/${d}.conf"
  [[ -L "$link" ]] && { rm -f "$link";  success "Removed symlink: ${link}"; }
  [[ -f "$conf" ]] && { rm -f "$conf";  success "Removed config:  ${conf}"; }

  # Revoke & remove acme.sh certificate
  local acme_bin="${HOME}/.acme.sh/acme.sh"
  if [[ -f "$acme_bin" ]]; then
    "$acme_bin" --remove -d "$d" 2>/dev/null && success "acme.sh cert removed for ${d}." || true
  fi

  # Remove stable cert dir
  local cert_dir="/etc/ssl/acmesh/${d}"
  [[ -d "$cert_dir" ]] && { rm -rf "$cert_dir"; success "Removed cert dir: ${cert_dir}"; }

  # Remove self-signed certs if present
  rm -f "/etc/ssl/selfsigned/${d}.crt" "/etc/ssl/selfsigned/${d}.key" 2>/dev/null || true

  # Remove htpasswd file
  local htpf="/etc/nginx/.htpasswd_${d//./_}"
  [[ -f "$htpf" ]] && { rm -f "$htpf"; success "Removed htpasswd: ${htpf}"; }

  # Remove acme.sh renewal cron for this domain (keep other domains' cron intact)
  # The global acme.sh cron stays — it handles all domains via --cron

  # Reload nginx to drop the removed vhost
  if nginx -t 2>/dev/null; then
    systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true
    success "Nginx reloaded — ${d} vhost removed."
  fi

  echo ""
  success "Cleanup complete. Proceeding with fresh setup for ${d}."
  echo ""
}

collect_domain() {
  section "Domain"
  while true; do
    DOMAIN=$(ask_input "Enter your domain name" "")
    [[ -n "$DOMAIN" ]] && break
    warn "Domain name cannot be empty."
  done
  info "Domain: ${DOMAIN}"

  # ── Conflict check ────────────────────────────────────────────────────────
  local conf_path="/etc/nginx/sites-available/${DOMAIN}.conf"
  if [[ -f "$conf_path" ]]; then
    echo ""
    warn "An existing Nginx configuration was found for: ${DOMAIN}"
    warn "File: ${conf_path}"
    echo ""
    echo -e "  ${CYAN}Options:${RESET}"
    sub_info "1) Remove existing config, SSL cert, htpasswd — start completely fresh"
    sub_info "2) Keep existing config and abort this setup"
    echo ""
    while true; do
      read -rp "$(echo -e "${YELLOW}?${RESET} Choose [1/2]: ")" _conflict
      case "${_conflict:-}" in
        1)
          purge_domain "$DOMAIN"
          break
          ;;
        2)
          echo ""
          info "Keeping existing configuration. Exiting."
          exit 0
          ;;
        *)
          warn "Please enter 1 or 2."
          ;;
      esac
    done
  fi

  echo ""
  info "www.${DOMAIN} — choose handling:"
  sub_info "1) Serve BOTH ${DOMAIN} AND www.${DOMAIN} — same config, no redirect (recommended)"
  sub_info "2) Primary domain only"
  read -rp "$(echo -e "${YELLOW}?${RESET} Choose [1/2] (default: 1): ")" _w
  case "${_w:-1}" in
    2) ENABLE_WWW=false ;;
    *) ENABLE_WWW=true  ;;
  esac
  [[ "$ENABLE_WWW" == "true" ]] && info "SAN cert will cover both ${DOMAIN} and www.${DOMAIN}." || true
}

# ─── STEP 2 — Site type & backend ─────────────────────────────────────────────
collect_site_type() {
  section "Site Type"
  sub_info "1) Static files (HTML / CSS / JS)"
  sub_info "2) Reverse proxy  (Node.js, Python/Django, Ruby, Go, etc.)"
  sub_info "3) PHP-FPM        (Laravel, WordPress, CodeIgniter, Symfony, raw PHP)"
  echo ""
  while true; do
    read -rp "$(echo -e "${YELLOW}?${RESET} Choose [1/2/3]: ")" _st
    case "${_st:-}" in
      1) SITE_TYPE="static"; break ;;
      2) SITE_TYPE="proxy";  break ;;
      3) SITE_TYPE="php";    break ;;
      *) warn "Please enter 1, 2, or 3." ;;
    esac
  done

  PROXY_PASS=""; PROXY_PORT=""; PROXY_HOST="127.0.0.1"
  FEAT_WEBSOCKET=false; PHP_SOCK=""; PHP_FRAMEWORK=""
  ROOT_DIR=""

  case "$SITE_TYPE" in
    proxy)
      PROXY_HOST=$(ask_input "Backend host/IP" "127.0.0.1")
      while true; do
        PROXY_PORT=$(ask_input "Backend port (e.g. 3000, 8000, 8080)" "")
        [[ "$PROXY_PORT" =~ ^[0-9]+$ ]] && (( PROXY_PORT >= 1 && PROXY_PORT <= 65535 )) && break
        warn "Enter a valid port number (1–65535)."
      done
      PROXY_PASS="http://${PROXY_HOST}:${PROXY_PORT}"
      info "Proxying to: ${PROXY_PASS}"
      ask_yes_no "Enable WebSocket support? (Socket.io, ws://, etc.)" "n" && FEAT_WEBSOCKET=true
      # Public/static assets directory — optional custom path
      ROOT_DIR="/var/www/${DOMAIN}/public"
      if ask_yes_no "Set a custom public/static assets directory?" "n"; then
        ROOT_DIR=$(ask_input "Directory path" "/var/www/${DOMAIN}/public")
      fi
      ensure_dir "$ROOT_DIR"
      ;;
    php)
      sub_info "1) Laravel / Lumen  2) WordPress  3) CodeIgniter  4) Symfony  5) Raw PHP"
      read -rp "$(echo -e "${YELLOW}?${RESET} Framework [1-5] (default: 5): ")" _fw
      case "${_fw:-5}" in
        1) PHP_FRAMEWORK="laravel" ;;  2) PHP_FRAMEWORK="wordpress" ;;
        3) PHP_FRAMEWORK="codeigniter" ;; 4) PHP_FRAMEWORK="symfony" ;; *) PHP_FRAMEWORK="php" ;;
      esac
      info "Framework: ${PHP_FRAMEWORK}"
      PHP_SOCK=$(ask_input "PHP-FPM socket or address" "unix:/run/php/php8.2-fpm.sock")
      ROOT_DIR=$(ask_input "Document root (Enter = auto-create)" "/var/www/${DOMAIN}/public")
      ensure_dir "$ROOT_DIR"
      if [[ ! -f "${ROOT_DIR}/index.php" && ! -f "${ROOT_DIR}/index.html" ]]; then
        cat > "${ROOT_DIR}/index.php" <<PHP
<?php echo "<h1>🚀 ${DOMAIN} is live!</h1><p>PHP " . phpversion() . " running.</p>";
PHP
        chown www-data:www-data "${ROOT_DIR}/index.php" 2>/dev/null || true
        success "Placeholder index.php created."
      fi
      ;;
    static)
      ROOT_DIR=$(ask_input "Document root (Enter = auto-create)" "/var/www/${DOMAIN}/public")
      ensure_dir "$ROOT_DIR"
      if [[ ! -f "${ROOT_DIR}/index.html" ]]; then
        cat > "${ROOT_DIR}/index.html" <<HTML
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Welcome to ${DOMAIN}</title>
<style>body{font-family:sans-serif;text-align:center;padding:60px;background:#f4f4f4;}
h1{color:#333;}p{color:#666;}</style></head>
<body><h1>🚀 ${DOMAIN} is Live!</h1><p>Nginx is serving your domain.</p></body></html>
HTML
        chown www-data:www-data "${ROOT_DIR}/index.html" 2>/dev/null || true
        success "Placeholder index.html created."
      fi
      ;;
  esac
}

# ─── STEP 3 — SSL (acme.sh multi-CA) ─────────────────────────────────────────
collect_ssl() {
  section "SSL / HTTPS"

  FEAT_SSL=false; SSL_MODE=""; HTTP_TO_HTTPS=false; HSTS=false
  SSL_CERT_PATH=""; SSL_KEY_PATH=""; ACME_CA="letsencrypt"

  ask_yes_no "Enable SSL/HTTPS?" "y" || return 0
  FEAT_SSL=true

  echo ""
  info "SSL provider:"
  sub_info "1) acme.sh — Let's Encrypt          (free, 90-day, most trusted, auto-renewal)"
  sub_info "2) acme.sh — ZeroSSL                (free, 90-day, different infrastructure, CA fallback)"
  sub_info "3) acme.sh — BuyPass Go SSL         (free, 180-day certs — fewer renewals)"
  sub_info "4) acme.sh — Multi-CA auto-fallback (Try LE first → ZeroSSL → BuyPass automatically)"
  sub_info "5) Self-signed                      (dev/testing only — browser warning)"
  sub_info "6) Manual / existing cert           (provide your own paths)"
  echo ""
  info "Recommendation: Option 4 (Multi-CA) for maximum uptime — zero interruption."
  echo ""

  read -rp "$(echo -e "${YELLOW}?${RESET} Choose SSL provider [1-6] (default: 4): ")" _sslp
  case "${_sslp:-4}" in
    1) SSL_MODE="acmesh"; ACME_CA="letsencrypt" ;;
    2) SSL_MODE="acmesh"; ACME_CA="zerossl" ;;
    3) SSL_MODE="acmesh"; ACME_CA="buypass" ;;
    4) SSL_MODE="acmesh"; ACME_CA="multi" ;;
    5) SSL_MODE="selfsigned"; ACME_CA="" ;;
    6) SSL_MODE="manual"; ACME_CA=""
       SSL_CERT_PATH=$(ask_input "Certificate file path (.crt/.pem)" "/etc/ssl/${DOMAIN}/fullchain.pem")
       SSL_KEY_PATH=$(ask_input  "Private key file path (.key)"      "/etc/ssl/${DOMAIN}/privkey.pem") ;;
    *) SSL_MODE="acmesh"; ACME_CA="multi" ;;
  esac

  if [[ "$SSL_MODE" == "acmesh" ]]; then
    ACME_EMAIL=$(ask_input "Email address for certificate notices" "admin@${DOMAIN}")
    # Store email globally for acme.sh install step
  fi

  ask_yes_no "Redirect HTTP → HTTPS?" "y"  && HTTP_TO_HTTPS=true
  ask_yes_no "Enable HSTS header?" "y"     && HSTS=true
}

# ─── STEP 4 — Performance ─────────────────────────────────────────────────────
collect_performance() {
  section "Performance"
  FEAT_GZIP=false; FEAT_CACHE=false
  ask_yes_no "Enable Gzip compression?" "y"                       && FEAT_GZIP=true  || true
  ask_yes_no "Cache static assets (images, CSS, JS, fonts)?" "y" && FEAT_CACHE=true || true
}

# ─── STEP 5 — Rate & connection limits ────────────────────────────────────────
collect_rate_limits() {
  section "Rate & Connection Limits"
  FEAT_RATE_LIMIT=false; RATE_LIMIT_RPS="10r/s"; RATE_LIMIT_BURST="20"
  FEAT_CONN_LIMIT=false; CONN_LIMIT_MAX="20"
  if ask_yes_no "Enable request rate limiting (per IP)?" "n"; then
    FEAT_RATE_LIMIT=true
    RATE_LIMIT_RPS=$(ask_input   "Max requests per second per IP" "10r/s")
    RATE_LIMIT_BURST=$(ask_input "Burst allowance"                "20")
  fi
  if ask_yes_no "Enable simultaneous connection limit (per IP)?" "n"; then
    FEAT_CONN_LIMIT=true
    CONN_LIMIT_MAX=$(ask_input "Max simultaneous connections per IP" "20")
  fi
}

# ─── STEP 6 — Logging & auth ──────────────────────────────────────────────────
collect_misc() {
  section "Logging & Auth"
  FEAT_LOGGING=false; LOG_ACCESS=""; LOG_ERROR=""
  FEAT_AUTH=false; AUTH_USER=""
  FEAT_ERROR_PAGES=false
  if ask_yes_no "Configure custom log paths?" "n"; then
    FEAT_LOGGING=true
    LOG_ACCESS=$(ask_input "Access log path" "/var/log/nginx/${DOMAIN}-access.log")
    LOG_ERROR=$(ask_input  "Error log path"  "/var/log/nginx/${DOMAIN}-error.log")
  fi
  if ask_yes_no "Enable HTTP Basic Authentication?" "n"; then
    FEAT_AUTH=true
    AUTH_USER=$(ask_input "Username" "admin")
  fi
  ask_yes_no "Configure custom error pages (400, 403, 404, 429, 50x)?" "y" && FEAT_ERROR_PAGES=true || true
}

# ─── STEP 7 — File upload ─────────────────────────────────────────────────────
collect_upload() {
  section "File Upload"
  FEAT_UPLOAD=false; UPLOAD_MAX_SIZE="10M"; UPLOAD_DIR=""
  UPLOAD_ALLOWED_TYPES="jpg|jpeg|png|gif|webp|pdf|doc|docx|xls|xlsx|zip|tar|gz"
  UPLOAD_TIMEOUT="60"; UPLOAD_DISABLE_EXEC=false

  ask_yes_no "Configure file upload permissions?" "n" || return 0
  FEAT_UPLOAD=true
  UPLOAD_MAX_SIZE=$(ask_input "Max upload size (e.g. 10M, 50M, 100M)" "10M")
  UPLOAD_TIMEOUT=$(ask_input  "Upload timeout in seconds"              "60")
  # Allowed file types — optional customisation
  if ask_yes_no "Customize allowed upload file types?" "n"; then
    info "Current default: ${UPLOAD_ALLOWED_TYPES}"
    UPLOAD_ALLOWED_TYPES=$(ask_input "Allowed extensions (pipe-separated)" "$UPLOAD_ALLOWED_TYPES")
  else
    info "Using default allowed types: ${UPLOAD_ALLOWED_TYPES}"
  fi
  # Upload directory — optional custom path
  UPLOAD_DIR="${ROOT_DIR:-/var/www/${DOMAIN}/public}/uploads"
  if ask_yes_no "Set a custom upload directory path?" "n"; then
    UPLOAD_DIR=$(ask_input "Upload directory path" "$UPLOAD_DIR")
  fi
  ensure_dir "$UPLOAD_DIR"
  ask_yes_no "Disable PHP/script execution inside upload directory? (recommended)" "y" && UPLOAD_DISABLE_EXEC=true
}

# ─── STEP 8 — Security ────────────────────────────────────────────────────────
collect_security() {
  section "Security"
  FEAT_SECURITY=false; FEAT_HIDE_VERSION=false; FEAT_BLOCK_DOTFILES=false
  FEAT_BLOCK_SENSITIVE=false; FEAT_LIMIT_METHODS=false; ALLOWED_METHODS="GET POST HEAD"
  FEAT_BLOCK_BOTS=false; FEAT_BLOCK_ATTACKS=false; FEAT_BLOCK_XMLRPC=false
  FEAT_BUFFER_LIMITS=false; FEAT_IP_RESTRICT=false; RESTRICTED_PATH=""; ALLOWED_IPS=""

  ask_yes_no "Enable security hardening?" "y" || return 0

  info "Configure each rule:"
  echo ""
  ask_yes_no "  Security headers (CSP, X-Frame, Referrer-Policy, COOP…)?" "y" && FEAT_SECURITY=true
  ask_yes_no "  Hide Nginx version (server_tokens off)?" "y"                   && FEAT_HIDE_VERSION=true
  ask_yes_no "  Block hidden/dot files (.env, .git, .htaccess, .aws…)?" "y"  && FEAT_BLOCK_DOTFILES=true
  ask_yes_no "  Block sensitive file types (.sql, .log, .bak, .sh…)?" "y"    && FEAT_BLOCK_SENSITIVE=true
  if ask_yes_no "  Restrict allowed HTTP methods?" "y"; then
    FEAT_LIMIT_METHODS=true
    sub_info "  1) GET POST HEAD                    — static/simple"
    sub_info "  2) GET POST HEAD PUT DELETE OPTIONS — REST API"
    sub_info "  3) Custom"
    read -rp "$(echo -e "${YELLOW}?${RESET}   Choose [1-3] (default: 1): ")" _mc
    case "${_mc:-1}" in
      2) ALLOWED_METHODS="GET POST HEAD PUT DELETE OPTIONS" ;;
      3) ALLOWED_METHODS=$(ask_input "   Methods (space-separated)" "GET POST HEAD") ;;
      *) ALLOWED_METHODS="GET POST HEAD" ;;
    esac
  fi
  ask_yes_no "  Block malicious bots & vulnerability scanners?" "y"           && FEAT_BLOCK_BOTS=true
  ask_yes_no "  Block URI attack patterns (SQLi, path traversal, XSS)?" "y" && FEAT_BLOCK_ATTACKS=true
  if [[ "${SITE_TYPE:-}" == "php" ]]; then
    ask_yes_no "  Block xmlrpc.php endpoint?" "y" && FEAT_BLOCK_XMLRPC=true
  fi
  ask_yes_no "  Buffer/header size limits (buffer overflow protection)?" "y" && FEAT_BUFFER_LIMITS=true
  if ask_yes_no "  Restrict a sensitive path to specific IPs?" "n"; then
    FEAT_IP_RESTRICT=true
    RESTRICTED_PATH=$(ask_input "   Path to restrict" "/admin")
    ALLOWED_IPS=$(ask_input     "   Allowed IPs (space-separated)" "127.0.0.1")
  fi
}

# ─── Summary & confirmation ───────────────────────────────────────────────────
confirm_summary() {
  section "Configuration Summary"
  echo -e "  ${BOLD}Domain         :${RESET} ${DOMAIN}"
  if [[ "$ENABLE_WWW" == "true" ]]; then
    echo -e "  ${BOLD}www            :${RESET} BOTH ${DOMAIN} and www.${DOMAIN} — same config, no redirect"
  else
    echo -e "  ${BOLD}www            :${RESET} Primary domain only"
  fi
  case "${SITE_TYPE}" in
    proxy)  echo -e "  ${BOLD}Site type      :${RESET} Reverse proxy → ${PROXY_PASS}" ;;
    php)    echo -e "  ${BOLD}Site type      :${RESET} PHP-FPM (${PHP_FRAMEWORK})" ;;
    static) echo -e "  ${BOLD}Site type      :${RESET} Static files" ;;
  esac
  echo -e "  ${BOLD}Document root  :${RESET} ${ROOT_DIR}"
  echo ""
  echo -e "  ${BOLD}── SSL ──────────────────────────────────────${RESET}"
  echo -e "  ${BOLD}SSL enabled    :${RESET} ${FEAT_SSL}"
  if [[ "$FEAT_SSL" == "true" ]]; then
    case "$SSL_MODE" in
      acmesh)
        case "$ACME_CA" in
          multi)       echo -e "  ${BOLD}SSL provider   :${RESET} acme.sh — Multi-CA auto-fallback (LE → ZeroSSL → BuyPass)" ;;
          letsencrypt) echo -e "  ${BOLD}SSL provider   :${RESET} acme.sh — Let's Encrypt" ;;
          zerossl)     echo -e "  ${BOLD}SSL provider   :${RESET} acme.sh — ZeroSSL" ;;
          buypass)     echo -e "  ${BOLD}SSL provider   :${RESET} acme.sh — BuyPass Go SSL (180-day)" ;;
        esac
        echo -e "  ${BOLD}Renewal        :${RESET} Automatic every 30 days, nginx reloaded silently"
        echo -e "  ${BOLD}Nginx config   :${RESET} NEVER modified on renewal (acme.sh does not touch it)"
        ;;
      selfsigned) echo -e "  ${BOLD}SSL provider   :${RESET} Self-signed (dev only)" ;;
      manual)     echo -e "  ${BOLD}SSL provider   :${RESET} Manual cert: ${SSL_CERT_PATH}" ;;
    esac
    echo -e "  ${BOLD}HTTP→HTTPS     :${RESET} ${HTTP_TO_HTTPS}"
    echo -e "  ${BOLD}HSTS           :${RESET} ${HSTS}"
  fi
  echo ""
  echo -e "  ${BOLD}── Performance ──────────────────────────────${RESET}"
  echo -e "  ${BOLD}Gzip           :${RESET} ${FEAT_GZIP}"
  echo -e "  ${BOLD}Static cache   :${RESET} ${FEAT_CACHE}"
  echo -e "  ${BOLD}Rate limiting  :${RESET} ${FEAT_RATE_LIMIT}${FEAT_RATE_LIMIT:+ (${RATE_LIMIT_RPS}, burst ${RATE_LIMIT_BURST})}"
  echo -e "  ${BOLD}Conn limit     :${RESET} ${FEAT_CONN_LIMIT}${FEAT_CONN_LIMIT:+ (max ${CONN_LIMIT_MAX}/IP)}"
  echo ""
  echo -e "  ${BOLD}── File upload ──────────────────────────────${RESET}"
  echo -e "  ${BOLD}Upload         :${RESET} ${FEAT_UPLOAD}"
  if [[ "$FEAT_UPLOAD" == "true" ]]; then
    echo -e "  ${BOLD}Max size       :${RESET} ${UPLOAD_MAX_SIZE}  |  Timeout: ${UPLOAD_TIMEOUT}s"
    echo -e "  ${BOLD}Allowed types  :${RESET} ${UPLOAD_ALLOWED_TYPES}"
    [[ -n "$UPLOAD_DIR" ]] && echo -e "  ${BOLD}Upload dir     :${RESET} ${UPLOAD_DIR}"
    echo -e "  ${BOLD}Disable exec   :${RESET} ${UPLOAD_DISABLE_EXEC}"
  fi
  echo ""
  echo -e "  ${BOLD}── Security ─────────────────────────────────${RESET}"
  echo -e "  ${BOLD}Sec headers    :${RESET} ${FEAT_SECURITY}  |  Hide version: ${FEAT_HIDE_VERSION}"
  echo -e "  ${BOLD}Block dotfiles :${RESET} ${FEAT_BLOCK_DOTFILES}  |  Sensitive types: ${FEAT_BLOCK_SENSITIVE}"
  echo -e "  ${BOLD}Limit methods  :${RESET} ${FEAT_LIMIT_METHODS}${FEAT_LIMIT_METHODS:+ (${ALLOWED_METHODS})}"
  echo -e "  ${BOLD}Block bots     :${RESET} ${FEAT_BLOCK_BOTS}  |  Attacks: ${FEAT_BLOCK_ATTACKS}"
  echo -e "  ${BOLD}XML-RPC block  :${RESET} ${FEAT_BLOCK_XMLRPC}  |  Buffer limits: ${FEAT_BUFFER_LIMITS}"
  echo -e "  ${BOLD}IP restriction :${RESET} ${FEAT_IP_RESTRICT}${FEAT_IP_RESTRICT:+ (${RESTRICTED_PATH} → ${ALLOWED_IPS})}"
  divider
  ask_yes_no "Proceed with this configuration?" "y" || { echo "Aborted. No changes made."; exit 0; }
}

# ─── Generate nginx config ────────────────────────────────────────────────────
generate_config() {
  section "Generating Nginx Configuration"
  local sites_avail="/etc/nginx/sites-available"
  local sites_en="/etc/nginx/sites-enabled"
  CONF_FILE="${sites_avail}/${DOMAIN}.conf"
  mkdir -p "$sites_avail" "$sites_en"

  if [[ -f "$CONF_FILE" ]]; then
    local bak
    bak="${CONF_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$CONF_FILE" "$bak"
    warn "Existing config backed up → ${bak}"
  fi

  local server_name="${DOMAIN}"
  [[ "$ENABLE_WWW" == "true" ]] && server_name="${DOMAIN} www.${DOMAIN}"

  # Cert paths — set based on SSL mode chosen
  local ssl_crt="" ssl_key=""
  case "${SSL_MODE:-}" in
    acmesh)
      ssl_crt="/etc/ssl/acmesh/${DOMAIN}/fullchain.pem"
      ssl_key="/etc/ssl/acmesh/${DOMAIN}/privkey.pem"
      ;;
    selfsigned)
      ssl_crt="/etc/ssl/selfsigned/${DOMAIN}.crt"
      ssl_key="/etc/ssl/selfsigned/${DOMAIN}.key"
      ;;
    manual)
      ssl_crt="$SSL_CERT_PATH"
      ssl_key="$SSL_KEY_PATH"
      ;;
  esac

  {
    echo "# ============================================================================="
    echo "# Nginx config for: ${server_name}"
    echo "# Site type : ${SITE_TYPE}${PHP_FRAMEWORK:+ (${PHP_FRAMEWORK})}"
    [[ "$SITE_TYPE" == "proxy" ]] && echo "# Backend   : ${PROXY_PASS}"
    echo "# SSL       : ${SSL_MODE:-none}${ACME_CA:+ / ${ACME_CA}}"
    echo "# Generated : $(date)"
    echo "# NOTE      : Cert paths are never modified by acme.sh renewal — safe."
    echo "# ============================================================================="
    echo ""

    # ── Top-level directives ─────────────────────────────────────────────────
    [[ "$FEAT_HIDE_VERSION" == "true" ]] && { echo "server_tokens off;"; echo ""; }

    [[ "$FEAT_BUFFER_LIMITS" == "true" ]] && cat <<'BUF'
client_body_buffer_size     16k;
client_header_buffer_size    4k;
large_client_header_buffers  4 16k;
client_header_timeout        10s;
client_body_timeout          10s;
keepalive_timeout            65s;
send_timeout                 10s;

BUF

    [[ "$FEAT_GZIP" == "true" ]] && cat <<'GZIP'
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_buffers 16 8k;
gzip_http_version 1.1;
gzip_min_length 256;
gzip_types
  application/atom+xml application/geo+json application/javascript
  application/x-javascript application/json application/ld+json
  application/manifest+json application/rdf+xml application/rss+xml
  application/xhtml+xml application/xml font/eot font/otf font/ttf
  image/svg+xml text/css text/javascript text/plain text/xml;

GZIP

    [[ "$FEAT_RATE_LIMIT" == "true" ]] && \
      echo "limit_req_zone \$binary_remote_addr zone=${DOMAIN//./_}_req:10m rate=${RATE_LIMIT_RPS};"$'\n'

    [[ "$FEAT_CONN_LIMIT" == "true" ]] && \
      echo "limit_conn_zone \$binary_remote_addr zone=${DOMAIN//./_}_conn:10m;"$'\n'

    [[ "$FEAT_BLOCK_BOTS" == "true" ]] && cat <<'BOTM'
map $http_user_agent $bad_bot {
    default           0;
    ~*masscan         1; ~*nikto          1; ~*sqlmap         1;
    ~*nmap            1; ~*zgrab          1; ~*nuclei         1;
    ~*dirbuster       1; ~*dirb           1; ~*gobuster       1;
    ~*hydra           1; ~*metasploit     1; ~*w3af           1;
    ~*acunetix        1; ~*qualys         1; ~*nessus         1;
    ~*openvas         1; ~*python-requests 1; ~*go-http-client 1;
    ""                1;
}

BOTM

    # HTTP → HTTPS redirect block
    if [[ "$FEAT_SSL" == "true" && "$HTTP_TO_HTTPS" == "true" ]]; then
      cat <<REDIR
server {
    listen 80;
    listen [::]:80;
    server_name ${server_name};

    # ACME challenge — required for acme.sh HTTP-01 renewals
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
        try_files \$uri =404;
        allow all;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

REDIR
    fi

    # Main server block
    echo "server {"
    if [[ "$FEAT_SSL" == "true" ]]; then
      echo "    listen 443 ssl http2;"
      echo "    listen [::]:443 ssl http2;"
    else
      echo "    listen 80;"
      echo "    listen [::]:80;"
    fi
    echo ""
    echo "    server_name ${server_name};"
    echo "    root  ${ROOT_DIR};"
    if [[ "$SITE_TYPE" == "php" ]]; then
      echo "    index index.php index.html index.htm;"
    else
      echo "    index index.html index.htm;"
    fi
    echo ""
    if [[ "$FEAT_LOGGING" == "true" ]]; then
      echo "    access_log ${LOG_ACCESS};"
      echo "    error_log  ${LOG_ERROR} warn;"
    else
      echo "    access_log /var/log/nginx/${DOMAIN}-access.log;"
      echo "    error_log  /var/log/nginx/${DOMAIN}-error.log warn;"
    fi
    echo ""

    # SSL cert block
    if [[ "$FEAT_SSL" == "true" ]]; then
      echo "    # ── SSL ──────────────────────────────────────────────────────────────────"
      echo "    # Certs managed by acme.sh — DO NOT edit these paths"
      echo "    # Renewal runs silently every 30 days and reloads nginx automatically"
      echo "    ssl_certificate     ${ssl_crt};"
      echo "    ssl_certificate_key ${ssl_key};"
      cat <<'SSLP'
    ssl_protocols             TLSv1.2 TLSv1.3;
    ssl_ciphers               ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache         shared:SSL:10m;
    ssl_session_timeout       1d;
    ssl_session_tickets       off;
    ssl_stapling              on;
    ssl_stapling_verify       on;
    # ── OCSP stapling with trusted certificate chain ────────────────────────
    ssl_trusted_certificate   /etc/ssl/certs/ca-certificates.crt;
    # ── DNS Resolver — Cloudflare priority (privacy-first, fast) ────────────
    resolver                  1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout          5s;

SSLP
    fi

    # HSTS
    [[ "$FEAT_SSL" == "true" && "$HSTS" == "true" ]] && \
      echo "    add_header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\" always;"

    # Security headers
    [[ "$FEAT_SECURITY" == "true" ]] && cat <<'SECHDR'

    add_header X-Frame-Options                   "SAMEORIGIN"                            always;
    add_header X-Content-Type-Options            "nosniff"                               always;
    add_header X-XSS-Protection                  "1; mode=block"                         always;
    add_header Referrer-Policy                   "strict-origin-when-cross-origin"       always;
    add_header Permissions-Policy                "camera=(), microphone=(), geolocation=()" always;
    add_header Content-Security-Policy           "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:;" always;
    add_header X-Permitted-Cross-Domain-Policies "none"                                  always;
    add_header Cross-Origin-Opener-Policy        "same-origin"                           always;
    add_header Cross-Origin-Embedder-Policy      "require-corp"                          always;
SECHDR

    # Bad bots
    [[ "$FEAT_BLOCK_BOTS" == "true" ]] && printf '\n    if ($bad_bot) { return 444; }\n'

    [[ "$FEAT_RATE_LIMIT" == "true" ]] && {
      printf '\n    limit_req  zone=%s_req burst=%s nodelay;\n' "${DOMAIN//./_}" "$RATE_LIMIT_BURST"
      printf '    limit_req_status 429;\n'
    }
    [[ "$FEAT_CONN_LIMIT" == "true" ]] && {
      printf '    limit_conn %s_conn %s;\n' "${DOMAIN//./_}" "$CONN_LIMIT_MAX"
      printf '    limit_conn_status 429;\n'
    }

    if [[ "$FEAT_LIMIT_METHODS" == "true" ]]; then
      local mc; mc=$(echo "$ALLOWED_METHODS" | tr ' ' '|')
      printf '\n    if ($request_method !~ ^(%s)$) { return 405; }\n' "$mc"
    fi

    [[ "$FEAT_UPLOAD" == "true" ]] && cat <<UPLSZ

    client_max_body_size  ${UPLOAD_MAX_SIZE};
    client_body_timeout   ${UPLOAD_TIMEOUT}s;
    proxy_read_timeout    ${UPLOAD_TIMEOUT}s;
    proxy_send_timeout    ${UPLOAD_TIMEOUT}s;
UPLSZ

    [[ "$FEAT_AUTH" == "true" ]] && cat <<AUTH

    auth_basic           "Restricted Area";
    auth_basic_user_file /etc/nginx/.htpasswd_${DOMAIN//./_};
AUTH

    [[ "$FEAT_ERROR_PAGES" == "true" ]] && cat <<'ERRP'

    error_page 400 /400.html; error_page 403 /403.html;
    error_page 404 /404.html; error_page 429 /429.html;
    error_page 500 502 503 504 /50x.html;
    location ~ ^/(400|403|404|429|50x)\.html$ { root /var/www/html; internal; }
ERRP

    [[ "$FEAT_CACHE" == "true" ]] && cat <<'CACHE'

    location ~* \.(jpg|jpeg|png|gif|ico|svg|webp|woff|woff2|ttf|eot|otf|css|js)$ {
        expires 1y; add_header Cache-Control "public, immutable"; access_log off;
    }
CACHE

    # Security location blocks
    [[ "$FEAT_BLOCK_DOTFILES" == "true" ]] && cat <<'DOTF'

    location ~ /\. { deny all; access_log off; log_not_found off; return 404; }
    location ~* /\.(env|git|gitignore|htaccess|htpasswd|npmrc|aws|dockerenv|ssh)$ { deny all; return 404; }
DOTF

    [[ "$FEAT_BLOCK_SENSITIVE" == "true" ]] && cat <<'SENS'

    location ~* \.(sql|log|bak|backup|old|orig|conf|config|ini|yml|yaml|sh|bash|py|rb|pl|swp)$ {
        deny all; access_log off; log_not_found off; return 404;
    }
    location ~* /(phpinfo|php-info|test|debug|info|adminer|phpmyadmin)\.php$ { deny all; return 404; }
SENS

    [[ "$FEAT_BLOCK_XMLRPC" == "true" ]] && \
      printf '\n    location = /xmlrpc.php { deny all; access_log off; log_not_found off; return 444; }\n'

    if [[ "$FEAT_IP_RESTRICT" == "true" ]]; then
      echo ""
      echo "    location ~ ^${RESTRICTED_PATH}(/|\$) {"
      for _ip in $ALLOWED_IPS; do echo "        allow ${_ip};"; done
      echo "        deny  all;"
      echo "    }"
    fi

    # Upload exec lock
    if [[ "$FEAT_UPLOAD" == "true" && -n "$UPLOAD_DIR" && "$UPLOAD_DISABLE_EXEC" == "true" ]]; then
      local uloc="${UPLOAD_DIR#${ROOT_DIR}}"
      [[ -z "$uloc" ]] && uloc="/uploads"
      echo ""
      echo "    location ^~ ${uloc}/ {"
      echo "        location ~* \.(php|php[3-9]|phtml|pl|py|jsp|asp|sh|cgi)\$ { deny all; return 403; }"
      [[ -n "$UPLOAD_ALLOWED_TYPES" ]] && {
        echo "        location ~* \.(${UPLOAD_ALLOWED_TYPES})\$ { try_files \$uri =404; }"
        echo "        deny all;"
      }
      echo "    }"
    fi

    # Main location block
    echo ""
    case "$SITE_TYPE" in
      proxy)
        cat <<PROXY
    location / {
        proxy_pass            ${PROXY_PASS};
        proxy_http_version    1.1;
        proxy_set_header      Host              \$host;
        proxy_set_header      X-Real-IP         \$remote_addr;
        proxy_set_header      X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header      X-Forwarded-Proto \$scheme;
        proxy_read_timeout    90s;
        proxy_connect_timeout 10s;
        proxy_buffering       off;
        if (\$request_uri ~* "(union.*select|select.*from|insert.*into|drop.*table|exec\()") { return 403; }
        if (\$request_uri ~* "(\.\.\/|%2e%2e%2f|%252e%252e|\.\.%2f)") { return 403; }
        if (\$request_uri ~* "(<script|javascript:|vbscript:|onload=|onerror=|onclick=)") { return 403; }
        if (\$request_uri ~* "(etc/passwd|etc/shadow|proc/self|boot\.ini)") { return 403; }
        if (\$request_uri ~* "(base64_decode|eval\(|system\(|passthru\(|shell_exec\()") { return 403; }
PROXY
        [[ "$FEAT_WEBSOCKET" == "true" ]] && {
          echo "        proxy_set_header   Upgrade    \$http_upgrade;"
          echo "        proxy_set_header   Connection \"upgrade\";"
        }
        echo "    }"
        ;;
      php)
        case "$PHP_FRAMEWORK" in
          laravel|codeigniter|symfony|php)
            printf '    location / { try_files $uri $uri/ /index.php?$query_string; }\n' ;;
          wordpress)
            printf '    location / { try_files $uri $uri/ /index.php?$args; }\n' ;;
        esac
        cat <<PHPF

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        include                 snippets/fastcgi-php.conf;
        fastcgi_pass            ${PHP_SOCK};
        fastcgi_param           SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include                 fastcgi_params;
        fastcgi_read_timeout    60s;
        fastcgi_buffer_size     16k;
        fastcgi_buffers         4 16k;
    }
    location ~ /\.ht { deny all; }
PHPF
        ;;
      static)
        printf '    location / { try_files $uri $uri/ =404; }\n' ;;
    esac

    echo "}"
  } > "$CONF_FILE"

  success "Config written → ${CONF_FILE}"
}

# ─── Enable site ──────────────────────────────────────────────────────────────
enable_site() {
  local link="/etc/nginx/sites-enabled/${DOMAIN}.conf"
  [[ -L "$link" ]] && rm "$link"
  ln -s "/etc/nginx/sites-available/${DOMAIN}.conf" "$link"
  success "Site enabled → ${link}"
}

# ─── acme.sh cert issuance with multi-CA fallback ─────────────────────────────
issue_acmesh_cert() {
  local ca_server="$1"      # ACME server URL or alias
  local ca_name="$2"        # Human-readable name
  local domains="-d ${DOMAIN}"
  [[ "$ENABLE_WWW" == "true" ]] && domains+=" -d www.${DOMAIN}"

  local cert_dir="/etc/ssl/acmesh/${DOMAIN}"
  mkdir -p "$cert_dir"
  chmod 700 "$cert_dir"  # Restrict access to root only

  info "Trying ${ca_name}..."

  # Issue certificate — capture exit code safely without triggering set -e
  local _issue_rc=0
  "$ACMESH_BIN" --issue \
    --server "$ca_server" \
    --webroot "/var/www/letsencrypt" \
    $domains \
    --keylength ec-256 \
    --force 2>&1 | tail -8 || _issue_rc=$?

  if [[ "$_issue_rc" -eq 0 ]] || "$ACMESH_BIN" --list 2>/dev/null | grep -q "^${DOMAIN}"; then
    # Install/copy certs to a stable path that nginx references
    "$ACMESH_BIN" --install-cert \
      -d "${DOMAIN}" \
      --cert-file      "${cert_dir}/cert.pem" \
      --key-file       "${cert_dir}/privkey.pem" \
      --fullchain-file "${cert_dir}/fullchain.pem" \
      --reloadcmd      "systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true" 2>&1 | tail -3
    
    # ── Fix certificate file permissions ────────────────────────────────────
    [[ -f "${cert_dir}/privkey.pem" ]] && chmod 600 "${cert_dir}/privkey.pem"  # Private key: read for root only
    [[ -f "${cert_dir}/cert.pem" ]] && chmod 644 "${cert_dir}/cert.pem"        # Public cert: readable to all
    [[ -f "${cert_dir}/fullchain.pem" ]] && chmod 644 "${cert_dir}/fullchain.pem"  # Full chain: readable to all
    
    # ── Validate certificate is functional ──────────────────────────────────────
    if ! openssl x509 -in "${cert_dir}/fullchain.pem" -noout 2>/dev/null; then
      warn "Certificate file exists but validation failed for: ${DOMAIN}"
      return 1
    fi
    
    # ── Verify certificate chain is complete ────────────────────────────────
    local _chain_count; _chain_count=$(grep -c "BEGIN CERTIFICATE" "${cert_dir}/fullchain.pem" 2>/dev/null || echo 0)
    if [[ "$_chain_count" -lt 2 ]]; then
      warn "Certificate chain incomplete (${_chain_count} cert(s) found, expected ≥2)"
    fi
    
    # ── Display certificate details for verification ────────────────────────
    local _issuer; _issuer=$(openssl x509 -in "${cert_dir}/fullchain.pem" -noout -issuer 2>/dev/null | sed 's/issuer=//')
    local _notbefore; _notbefore=$(openssl x509 -in "${cert_dir}/fullchain.pem" -noout -dates 2>/dev/null | grep notBefore | cut -d= -f2)
    local _notafter; _notafter=$(openssl x509 -in "${cert_dir}/fullchain.pem" -noout -dates 2>/dev/null | grep notAfter | cut -d= -f2)
    local _san; _san=$(openssl x509 -in "${cert_dir}/fullchain.pem" -noout -text 2>/dev/null | grep -A 1 "Subject Alternative Name" | tail -1 | sed 's/^[[:space:]]*//;s/,/, /g' || echo "N/A")
    
    success "${ca_name} certificate issued and installed."
    info "Issuer:     ${_issuer}"
    info "Valid from: ${_notbefore}"
    info "Valid to:   ${_notafter}"
    info "Domains:    ${_san}"
    success "Auto-renewal: every 30 days, nginx reloads automatically."
    return 0
  fi
  
  error "Failed to issue certificate from ${ca_name}. Check your DNS configuration and port 80 access."
  return 1
}


handle_ssl_setup() {
  [[ "$FEAT_SSL" != "true" ]] && return
  section "SSL Certificate Setup"

  case "$SSL_MODE" in
    # ── acme.sh ───────────────────────────────────────────────────────────────
    acmesh)
      # Prepare webroot for HTTP-01 challenge
      ensure_dir "/var/www/letsencrypt/.well-known/acme-challenge"
      
      # ── Set proper permissions for acme challenge directory ──────────────────
      chmod 755 /var/www/letsencrypt/.well-known/acme-challenge
      chmod 755 /var/www/letsencrypt/.well-known
      chmod 755 /var/www/letsencrypt

      # Install acme.sh if needed
      [[ -n "${ACME_EMAIL:-}" ]] || ACME_EMAIL=$(ask_input "Email for certificate notices" "admin@${DOMAIN}")
      install_acmesh

      local cert_dir="/etc/ssl/acmesh/${DOMAIN}"
      mkdir -p "$cert_dir"

      # ── Pre-load nginx so it serves port 80 for the HTTP-01 ACME challenge ──
      # The generated nginx config references SSL cert files that don't exist yet.
      # Create temporary dummy self-signed certs so nginx can pass the config test
      # and reload before the real cert is issued.
      if [[ ! -f "${cert_dir}/fullchain.pem" || ! -f "${cert_dir}/privkey.pem" ]]; then
        info "Creating temporary self-signed certificate for initial nginx load..."
        openssl req -x509 -nodes -days 1 \
          -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
          -keyout "${cert_dir}/privkey.pem" \
          -out    "${cert_dir}/fullchain.pem" \
          -subj   "/CN=${DOMAIN}" 2>/dev/null
        cp "${cert_dir}/fullchain.pem" "${cert_dir}/cert.pem"
        # ── Set proper permissions on self-signed certs ────────────────────────
        chmod 600 "${cert_dir}/privkey.pem"    # Private key: read for root only
        chmod 644 "${cert_dir}/cert.pem"       # Public cert: readable to all
        chmod 644 "${cert_dir}/fullchain.pem"  # Full chain: readable to all
      fi

      # When HTTP_TO_HTTPS=false the generated config has no port-80 block, so
      # the ACME webroot challenge won't be reachable.  Add a minimal vhost for it.
      local _acme_tmp_conf=""
      if [[ "$HTTP_TO_HTTPS" != "true" ]]; then
        _acme_tmp_conf="/etc/nginx/sites-enabled/_acme_challenge_${DOMAIN//./_}.conf"
        local _sv="${DOMAIN}"; [[ "$ENABLE_WWW" == "true" ]] && _sv+=" www.${DOMAIN}"
        cat > "$_acme_tmp_conf" <<TMPVH
server {
    listen 80;
    listen [::]:80;
    server_name ${_sv};
    root /var/www/letsencrypt;
    location /.well-known/acme-challenge/ { try_files \$uri =404; }
    location / { return 404; }
}
TMPVH
      fi

      # Reload nginx so the ACME challenge path is served on port 80
      if nginx -t 2>/dev/null; then
        systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true
        info "Nginx reloaded — port 80 now serves ACME challenge."
      else
        warn "Nginx config test failed before cert issuance — HTTP-01 challenge may fail."
      fi

      case "$ACME_CA" in
        letsencrypt)
          issue_acmesh_cert "letsencrypt" "Let's Encrypt" || \
            warn "Let's Encrypt failed. Try: ${ACMESH_BIN} --issue --server letsencrypt -d ${DOMAIN}"
          ;;
        zerossl)
          issue_acmesh_cert "zerossl" "ZeroSSL" || \
            warn "ZeroSSL failed."
          ;;
        buypass)
          issue_acmesh_cert "https://api.buypass.com/acme/directory" "BuyPass Go SSL" || \
            warn "BuyPass failed."
          ;;
        multi)
          info "Multi-CA mode: trying Let's Encrypt first..."
          if ! issue_acmesh_cert "letsencrypt" "Let's Encrypt"; then
            warn "Let's Encrypt failed — trying ZeroSSL..."
            if ! issue_acmesh_cert "zerossl" "ZeroSSL"; then
              warn "ZeroSSL failed — trying BuyPass Go SSL..."
              issue_acmesh_cert "https://api.buypass.com/acme/directory" "BuyPass Go SSL" || \
                die "All CA attempts failed. Check DNS records and port 80 access."
            fi
          fi
          ;;
      esac

      # Remove temporary HTTP-only challenge vhost now that cert is issued
      [[ -n "${_acme_tmp_conf:-}" ]] && rm -f "$_acme_tmp_conf"

      # Add a daily cron for acme.sh renewal checks
      if ! crontab -l 2>/dev/null | grep -q "acme.sh --cron"; then
        (crontab -l 2>/dev/null; \
          echo "0 3 * * * \"${ACMESH_BIN}\" --cron --home \"${ACMESH_DIR}\" > /dev/null 2>&1") | crontab -
        success "Renewal cron set: daily 3 AM — runs silently, reloads nginx on success."
      fi
      ;;

    # ── Self-signed ───────────────────────────────────────────────────────────
    selfsigned)
      mkdir -p /etc/ssl/selfsigned
      info "Generating self-signed certificate for ${DOMAIN}..."
      
      if [[ "$ENABLE_WWW" == "true" ]]; then
        local tmp_cnf; tmp_cnf=$(mktemp /tmp/ossl-XXXXXX.cnf)
        cat > "$tmp_cnf" <<CNF
[req]
default_bits=2048
prompt=no
default_md=sha256
distinguished_name=dn
x509_extensions=v3_req
[dn]
C=US
ST=State
L=City
O=Development
CN=${DOMAIN}
[v3_req]
basicConstraints=CA:FALSE
keyUsage=nonRepudiation, digitalSignature, keyEncipherment
subjectAltName=@alt
[alt]
DNS.1=${DOMAIN}
DNS.2=www.${DOMAIN}
CNF
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
          -keyout "/etc/ssl/selfsigned/${DOMAIN}.key" \
          -out    "/etc/ssl/selfsigned/${DOMAIN}.crt" \
          -config "$tmp_cnf" 2>/dev/null || {
          warn "Failed to generate self-signed certificate"
          rm -f "$tmp_cnf"
          return 1
        }
        rm -f "$tmp_cnf"
        
        # ── Validate generated certificate ─────────────────────────────────────
        if openssl x509 -in "/etc/ssl/selfsigned/${DOMAIN}.crt" -noout 2>/dev/null; then
          chmod 600 "/etc/ssl/selfsigned/${DOMAIN}.key"
          chmod 644 "/etc/ssl/selfsigned/${DOMAIN}.crt"
          local _san_list; _san_list=$(openssl x509 -in "/etc/ssl/selfsigned/${DOMAIN}.crt" -noout -text 2>/dev/null | grep -A 1 "Subject Alternative Name" | tail -1 | sed 's/^[[:space:]]*//;s/,/, /g')
          local _notafter; _notafter=$(openssl x509 -in "/etc/ssl/selfsigned/${DOMAIN}.crt" -noout -dates 2>/dev/null | grep notAfter | cut -d= -f2)
          success "Self-signed SAN cert: ${DOMAIN} + www.${DOMAIN}"
          info "Domains:   ${_san_list}"
          info "Expires:   ${_notafter}"
          info "Note:      ⚠️  Browser warning expected (self-signed only for dev/testing)"
        else
          error "Certificate validation failed"
          return 1
        fi
      else
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
          -keyout "/etc/ssl/selfsigned/${DOMAIN}.key" \
          -out    "/etc/ssl/selfsigned/${DOMAIN}.crt" \
          -subj   "/C=US/ST=State/L=City/O=Development/CN=${DOMAIN}" 2>/dev/null || {
          warn "Failed to generate self-signed certificate"
          return 1
        }
        
        # ── Validate generated certificate ─────────────────────────────────────
        if openssl x509 -in "/etc/ssl/selfsigned/${DOMAIN}.crt" -noout 2>/dev/null; then
          chmod 600 "/etc/ssl/selfsigned/${DOMAIN}.key"
          chmod 644 "/etc/ssl/selfsigned/${DOMAIN}.crt"
          local _notafter; _notafter=$(openssl x509 -in "/etc/ssl/selfsigned/${DOMAIN}.crt" -noout -dates 2>/dev/null | grep notAfter | cut -d= -f2)
          success "Self-signed certificate generated"
          info "Domain:    ${DOMAIN}"
          info "Expires:   ${_notafter}"
          info "Note:      ⚠️  Browser warning expected (self-signed only for dev/testing)"
        else
          error "Certificate validation failed"
          return 1
        fi
      fi
      ;;

    # ── Manual ────────────────────────────────────────────────────────────────
    manual)
      info "Validating manual SSL certificates..."
      
      # ── Validate certificate file exists and is valid ────────────────────
      if [[ ! -f "$SSL_CERT_PATH" ]]; then
        error "Certificate file not found: ${SSL_CERT_PATH}"
        return 1
      fi
      
      if ! openssl x509 -in "$SSL_CERT_PATH" -noout 2>/dev/null; then
        error "Certificate validation failed: ${SSL_CERT_PATH}"
        return 1
      fi
      
      # ── Validate private key exists and is valid ────────────────────────
      if [[ ! -f "$SSL_KEY_PATH" ]]; then
        error "Private key file not found: ${SSL_KEY_PATH}"
        return 1
      fi
      
      if ! openssl pkey -in "$SSL_KEY_PATH" -noout 2>/dev/null; then
        error "Private key validation failed: ${SSL_KEY_PATH}"
        return 1
      fi
      
      # ── Verify certificate chain completeness ──────────────────────────
      if grep -q "BEGIN CERTIFICATE" "$SSL_CERT_PATH"; then
        local _chain_count; _chain_count=$(grep -c "BEGIN CERTIFICATE" "$SSL_CERT_PATH")
        if [[ "$_chain_count" -eq 1 ]]; then
          warn "Certificate appears to be standalone (only leaf cert). For full chain, concatenate: leaf + intermediate + root"
        fi
      fi
      
      # ── Display certificate details ────────────────────────────────────
      local _subject; _subject=$(openssl x509 -in "$SSL_CERT_PATH" -noout -subject 2>/dev/null | sed 's/subject=//')
      local _issuer; _issuer=$(openssl x509 -in "$SSL_CERT_PATH" -noout -issuer 2>/dev/null | sed 's/issuer=//')
      local _notafter; _notafter=$(openssl x509 -in "$SSL_CERT_PATH" -noout -dates 2>/dev/null | grep notAfter | cut -d= -f2)
      
      success "Manual certificates validated successfully"
      info "Subject:   ${_subject}"
      info "Issuer:    ${_issuer}"
      info "Expires:   ${_notafter}"
      
      # ── Check expiration warning ────────────────────────────────────────
      local _expire_epoch; _expire_epoch=$(openssl x509 -in "$SSL_CERT_PATH" -noout -dates 2>/dev/null | grep notAfter | cut -d= -f2 | date -f - +%s 2>/dev/null || echo 0)
      local _now_epoch; _now_epoch=$(date +%s)
      local _days_left; _days_left=$(( (_expire_epoch - _now_epoch) / 86400 ))
      
      if [[ "$_days_left" -lt 30 ]]; then
        warn "Certificate expires in ${_days_left} days — renewal recommended"
      elif [[ "$_days_left" -lt 0 ]]; then
        error "Certificate has EXPIRED (${_days_left} days ago)"
        return 1
      fi
      ;;
  esac
}

# ─── Basic auth ───────────────────────────────────────────────────────────────
handle_basic_auth() {
  [[ "$FEAT_AUTH" != "true" ]] && return
  section "Basic Authentication"
  local htpf="/etc/nginx/.htpasswd_${DOMAIN//./_}"
  command -v htpasswd &>/dev/null || case "$PKG_MGR" in
    apt)     apt-get install -y apache2-utils ;;
    dnf|yum) ${PKG_MGR} install -y httpd-tools ;;
    pacman)  pacman -Sy --noconfirm apache ;;
  esac
  stty -echo
  read -rp "$(echo -e "${YELLOW}?${RESET} Password for '${AUTH_USER}': ")" _ap
  stty echo; echo ""
  echo "${AUTH_USER}:$(openssl passwd -apr1 "$_ap")" > "$htpf"
  chmod 640 "$htpf"
  success "htpasswd created: ${htpf}"
}

# ─── Test & reload ────────────────────────────────────────────────────────────
test_and_reload() {
  section "Testing & Reloading Nginx"
  nginx -t 2>&1 || { error "Config test FAILED."; warn "Fix: ${CONF_FILE}"; exit 1; }
  success "Config test passed."
  systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || \
    warn "Could not reload — run: sudo systemctl reload nginx"
  success "Nginx reloaded."
}

# ─── Final summary ────────────────────────────────────────────────────────────
final_summary() {
  divider
  echo -e "${GREEN}${BOLD}"
  echo "  ✅  Setup complete!"
  echo -e "${RESET}"
  local proto="http"; [[ "$FEAT_SSL" == "true" ]] && proto="https"
  echo -e "  ${BOLD}Live URL       :${RESET} ${proto}://${DOMAIN}"
  [[ "$ENABLE_WWW" == "true" ]] && \
    echo -e "                   ${proto}://www.${DOMAIN}  ${CYAN}(same server — no redirect)${RESET}"
  [[ "$SITE_TYPE" == "proxy" ]] && echo -e "  ${BOLD}Proxying to    :${RESET} ${PROXY_PASS}"
  echo -e "  ${BOLD}Config         :${RESET} /etc/nginx/sites-available/${DOMAIN}.conf"
  echo -e "  ${BOLD}Document root  :${RESET} ${ROOT_DIR}"
  [[ -n "${UPLOAD_DIR:-}" ]] && echo -e "  ${BOLD}Upload dir     :${RESET} ${UPLOAD_DIR}  (max ${UPLOAD_MAX_SIZE})"
  if [[ "${SSL_MODE:-}" == "acmesh" ]]; then
    echo -e "  ${BOLD}SSL certs      :${RESET} /etc/ssl/acmesh/${DOMAIN}/"
    echo -e "  ${BOLD}Renewal        :${RESET} Automatic (acme.sh cron, 3 AM daily)"
    echo -e "  ${BOLD}On renewal     :${RESET} systemctl reload nginx — zero downtime"
  fi
  echo ""
  echo -e "  ${CYAN}Commands:${RESET}"
  echo -e "  sudo nginx -t"
  echo -e "  sudo systemctl reload nginx"
  echo -e "  ${ACMESH_BIN:-~/.acme.sh/acme.sh} --cron          # test renewal manually"
  echo -e "  ${ACMESH_BIN:-~/.acme.sh/acme.sh} --list          # view all certs & expiry"
  echo -e "  tail -f /var/log/nginx/${DOMAIN}-error.log"
  divider
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  banner
  check_root
  detect_os
  check_dependencies
  install_nginx
  collect_domain
  collect_site_type
  collect_ssl
  collect_performance
  collect_rate_limits
  collect_misc
  collect_upload
  collect_security
  confirm_summary
  generate_config
  enable_site
  handle_ssl_setup
  handle_basic_auth
  test_and_reload
  final_summary
}

main "$@"