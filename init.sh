#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  NODE PROVISION  v6.0.0  —  Multi-Project Edition                           ║
# ║  Ubuntu 20.04 / 22.04 / 24.04 LTS                                           ║
# ╠══════════════════════════════════════════════════════════════════════════════╣
# ║                                                                              ║
# ║  WHAT THIS DOES                                                              ║
# ║  01. Creates deploy user with password + SSH key access                      ║
# ║  02. Root access via sudo (password required)                                ║

# ║  04. Installs Git, NVM, Node.js, PM2 (bulletproof startup)                  ║
# ║  05. Nginx base setup for MULTIPLE Node.js projects                          ║
# ║  07. Monitoring: Netdata (real-time) + PM2 dashboard + status script        ║
# ║  08. fail2ban, sysctl hardening, UFW, logrotate                             ║
# ║                                                                              ║
# ║  ─────────────────────────────────────────────────────────────────────────  ║
# ║                                                                              ║
# ║                                                                              ║
# ║                                                                              ║
# ║                                                                              ║
# ║  USAGE                                                                       ║
# ║    sudo bash node_provision.sh -u <username> [OPTIONS]                       ║
# ║                                                                              ║
# ║  OPTIONS                                                                     ║
# ║    -u  USERNAME     Deploy username               (required)                 ║
# ║    -p  PASSWORD     Custom password               (auto-generated if not set)║
# ║    -k  PUBKEY       SSH public key file           (optional)                 ║
# ║    -n  NODE_VER     Node.js version e.g. 20,22    (default: 20)              ║
# ║        --no-nvm     Skip NVM + Node.js                                       ║
# ║        --no-pm2     Skip PM2                                                 ║
# ║        --no-fw      Skip UFW                                                 ║
# ║        --no-mon     Skip Netdata monitoring                                  ║
# ║        --dry-run    Simulate — zero system changes                           ║
# ║    -h               Show this help                                           ║
# ║                                                                              ║
# ║  EXAMPLE                                                                     ║
# ║    sudo bash node_provision.sh -u mojahid -n 20                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set -euo pipefail
IFS=$'\n\t'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  CONFIG
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

readonly SCRIPT_VERSION="6.0.0"
readonly LOG_FILE="/var/log/node_provision.log"
readonly NVM_VERSION="v0.40.1"
readonly NVM_URL="https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"
readonly PASS_LEN=16
readonly SUDO_TIMEOUT=15
readonly SYSCTL_CONF="/etc/sysctl.d/99-node-provision.conf"
readonly STATUS_SCRIPT="/usr/local/bin/server_status"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  COLORS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [[ -t 1 ]] && tput colors &>/dev/null && (( $(tput colors) >= 8 )); then
    R=$'\033[0m'  BOLD=$'\033[1m'  DIM=$'\033[2m'
    GRN=$'\033[38;5;82m'   BLU=$'\033[38;5;33m'   CYN=$'\033[38;5;45m'
    YLW=$'\033[38;5;220m'  ORG=$'\033[38;5;208m'  PRP=$'\033[38;5;141m'
    WHT=$'\033[38;5;255m'  GRY=$'\033[38;5;244m'  RED=$'\033[38;5;196m'
    TICK="${GRN}✔${R}"  CROSS="${RED}✘${R}"  WARN_IC="${YLW}⚠${R}"
    ARROW="${CYN}›${R}"  DRY_IC="${PRP}◈${R}"
else
    R='' BOLD='' DIM='' GRN='' BLU='' CYN='' YLW='' ORG='' PRP='' WHT='' GRY='' RED=''
    TICK='[OK]' CROSS='[ERR]' WARN_IC='[WARN]' ARROW='->' DRY_IC='[DRY]'
fi

readonly HR2="════════════════════════════════════════════════════════════════════════════"
readonly HR="────────────────────────────────────────────────────────────────────────────"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  OUTPUT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

_log()  { printf '[%s] [%-5s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >> "$LOG_FILE" 2>/dev/null || true; }
ok()    { echo -e "  ${TICK}  $*";              _log INFO "$*"; }
warn()  { echo -e "  ${WARN_IC}  ${YLW}$*${R}"; _log WARN "$*"; }
info()  { echo -e "  ${ARROW}  ${GRY}$*${R}";   _log INFO "$*"; }
dry()   { echo -e "  ${DRY_IC}  ${DIM}[dry-run] $*${R}"; }
die()   { echo -e "\n  ${CROSS}  ${RED}${BOLD}FATAL: $*${R}\n" >&2; _log ERROR "$*"; exit 1; }

section()     { echo ""; echo -e "  ${BLU}${BOLD}┌─ $1 / $2${R}"; echo -e "  ${BLU}${DIM}│${R}"; }
section_end() { echo -e "  ${BLU}${DIM}└${HR:0:60}${R}"; }

run() {
    [[ "${DRY_RUN:-false}" == true ]] && { dry "$*"; return; }
    eval "$*" 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  BANNER
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

show_banner() {
    clear
    echo ""
    echo -e "${BLU}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${BLU}${BOLD}║${R}${WHT}${BOLD}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  ⚡  NODE PROVISION  v${SCRIPT_VERSION}  —  Multi-Project Edition"
    printf  "  ${BLU}${BOLD}║${R}${GRY}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  Git · PM2 · Multi-Nginx · Monitoring · Ubuntu LTS"
    echo -e "${BLU}${BOLD}  ╚${HR2}╝${R}"
    echo ""
    $DRY_RUN && echo -e "  ${PRP}${BOLD}  ◈  DRY-RUN MODE — Zero system changes.${R}\n"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  USAGE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

usage() {
    echo ""
    echo -e "  ${BOLD}Usage:${R}  sudo bash node_provision.sh -u <username> [OPTIONS]"
    echo ""
    printf  "    ${CYN}%-20s${R}  %s\n" \
        "-u  USERNAME"   "Deploy username (required)" \
        "-p  PASSWORD"   "Custom password (auto-generated if not set)" \
        "-k  PUBKEY"     "SSH public key file (optional)" \
        "-n  NODE_VER"   "Node.js version e.g. 20, 22 (default: 20)" \
        "    --no-nvm"   "Skip NVM + Node.js" \
        "    --no-pm2"   "Skip PM2" \
        "    --no-fw"    "Skip UFW" \
        "    --no-mon"   "Skip Netdata monitoring" \
        "    --dry-run"  "Simulate — no changes" \
        "-h"             "Show this help"
    echo ""
    echo -e "  ${BOLD}Example:${R}"
    echo    "    sudo bash node_provision.sh -u mojahid -n 20"
    echo ""
    exit 0
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  PARSE ARGS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

parse_args() {
    USERNAME="" CUSTOM_PASS="" SSH_PUBKEY="" NODE_VER="20"
    INSTALL_NVM=true INSTALL_PM2=true
    GEN_FW=true SETUP_MON=true DRY_RUN=false

    # Parse any flags that were passed
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u)         USERNAME="${2:?}";    shift 2 ;;
            -p)         CUSTOM_PASS="${2:?}"; shift 2 ;;
            -k)         SSH_PUBKEY="${2:?}";  shift 2 ;;
            -n)         NODE_VER="${2:?}";    shift 2 ;;
            --no-nvm)   INSTALL_NVM=false;    shift ;;
            --no-pm2)   INSTALL_PM2=false;    shift ;;
            --no-fw)    GEN_FW=false;         shift ;;
            --no-mon)   SETUP_MON=false;      shift ;;
            --dry-run)  DRY_RUN=true;         shift ;;
            -h|--help)  usage ;;
            *)          die "Unknown option: '$1'. Use -h for help." ;;
        esac
    done
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  INTERACTIVE PROMPTS
#  Called after show_banner so questions appear under the banner.
#  Only asks for values that were NOT already supplied via flags.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

prompt_inputs() {
    # Helper: print a prompt label
    _ask() { echo -e "  ${BLU}${BOLD}?${R}  ${WHT}$*${R}"; }
    _hint(){ echo -e "  ${GRY}   $*${R}"; }

    echo -e "  ${BLU}${DIM}${HR:0:60}${R}"
    echo -e "  ${WHT}${BOLD}  Setup Configuration${R}"
    echo -e "  ${BLU}${DIM}${HR:0:60}${R}"
    echo ""

    # ── Username ──────────────────────────────────────────────────────────────
    if [[ -z "$USERNAME" ]]; then
        while true; do
            _ask "Deploy username:"
            _hint "Lowercase letters, digits, _ or - only.  e.g.  mojahid"
            printf "  ${CYN}›${R}  " && read -r USERNAME </dev/tty
            USERNAME="${USERNAME// /}"   # strip accidental spaces

            if [[ -z "$USERNAME" ]]; then
                echo -e "  ${WARN_IC}  ${YLW}Username cannot be empty. Try again.${R}"
                continue
            fi
            if ! [[ "$USERNAME" =~ ^[a-z][a-z0-9_-]{1,30}$ ]]; then
                echo -e "  ${WARN_IC}  ${YLW}Invalid. Must start with a letter, lowercase only, max 31 chars.${R}"
                USERNAME=""
                continue
            fi
            if id "$USERNAME" &>/dev/null; then
                echo -e "  ${WARN_IC}  ${YLW}User '$USERNAME' already exists. Choose a different name.${R}"
                USERNAME=""
                continue
            fi
            echo -e "  ${TICK}  Username: ${WHT}${BOLD}$USERNAME${R}"
            break
        done
        echo ""
    fi

    # ── Password ──────────────────────────────────────────────────────────────
    if [[ -z "$CUSTOM_PASS" ]]; then
        _ask "Password  (press Enter to auto-generate a secure one):"
        _hint "Leave blank for a random ${PASS_LEN}-character password."
        printf "  ${CYN}›${R}  " && read -rs CUSTOM_PASS </dev/tty
        echo ""   # newline after hidden input

        if [[ -z "$CUSTOM_PASS" ]]; then
            echo -e "  ${TICK}  Password: ${GRY}will be auto-generated${R}"
        else
            if [[ ${#CUSTOM_PASS} -lt 8 ]]; then
                echo -e "  ${WARN_IC}  ${YLW}Password too short (min 8 chars) — auto-generating instead.${R}"
                CUSTOM_PASS=""
            else
                echo -e "  ${TICK}  Password: ${GRY}custom password set${R}"
            fi
        fi
        echo ""
    fi

    # ── Node.js version ───────────────────────────────────────────────────────
    _ask "Node.js version  (press Enter for default: ${NODE_VER}):"
    _hint "Options: 18, 20, 22, lts/*  — recommended: 20"
    printf "  ${CYN}›${R}  " && read -r _node_input </dev/tty
    if [[ -n "$_node_input" ]]; then
        NODE_VER="$_node_input"
    fi
    echo -e "  ${TICK}  Node.js version: ${WHT}${BOLD}${NODE_VER}${R}"
    echo ""

    # ── Confirm ───────────────────────────────────────────────────────────────
    echo -e "  ${BLU}${DIM}${HR:0:60}${R}"
    echo -e "  ${WHT}${BOLD}  Confirm Setup${R}"
    echo -e "  ${BLU}${DIM}${HR:0:60}${R}"
    echo ""
    printf  "  ${GRY}%-18s${R}  ${WHT}%s${R}\n" \
        "Username"    "$USERNAME" \
        "Password"    "$([ -n "$CUSTOM_PASS" ] && echo "custom (hidden)" || echo "auto-generate")" \
        "Node.js"     "v${NODE_VER}" \
        "NVM"         "$(  $INSTALL_NVM && echo yes || echo skipped)" \
        "PM2"         "$(  $INSTALL_PM2 && echo yes || echo skipped)" \
        "Firewall"    "$(  $GEN_FW      && echo yes || echo skipped)" \
        "Monitoring"  "$( $SETUP_MON   && echo yes || echo skipped)" \
        "Dry-run"     "$(  $DRY_RUN     && echo YES — no changes || echo no)"
    echo ""

    while true; do
        _ask "Proceed with provisioning?  [y/n]"
        printf "  ${CYN}›${R}  " && read -r _confirm </dev/tty
        case "${_confirm,,}" in
            y|yes) echo -e "  ${TICK}  Starting...\n"; break ;;
            n|no)  echo -e "\n  ${WARN_IC}  Aborted by user.\n"; exit 0 ;;
            *)     echo -e "  ${GRY}  Please type y or n${R}" ;;
        esac
    done
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  01 — PREFLIGHT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

preflight() {
    section "01" "Preflight Checks"

    [[ $EUID -eq 0 ]] || die "Must run as root: sudo bash $0"
    ok "Running as root."

    [[ -f /etc/os-release ]] && { source /etc/os-release; ok "OS: ${PRETTY_NAME:-Linux}"; }

    ok "Username: ${WHT}${BOLD}$USERNAME${R}"

    if [[ -n "$SSH_PUBKEY" ]]; then
        [[ -f "$SSH_PUBKEY" ]] || die "SSH key not found: $SSH_PUBKEY"
        ssh-keygen -l -f "$SSH_PUBKEY" &>/dev/null || die "Invalid SSH public key."
        ok "SSH key validated."
    fi

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  02 — OS USER
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

create_user() {
    section "02" "Creating OS User"

    if [[ -n "$CUSTOM_PASS" ]]; then
        PASSWORD="$CUSTOM_PASS"
        ok "Using custom password."
    else
        PASSWORD=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9!@#_+-' | head -c "$PASS_LEN")
        ok "Password auto-generated (${PASS_LEN} chars)."
    fi

    getent group "$USERNAME" &>/dev/null || run "groupadd '$USERNAME'"

    local cmd="useradd --gid '$USERNAME' --shell /bin/bash --comment 'Deploy: $USERNAME' --create-home --home-dir '/home/$USERNAME' '$USERNAME'"
    run "$cmd"
    ok "User '$USERNAME' created → /home/$USERNAME"

    if $DRY_RUN; then dry "Set password for $USERNAME"
    else echo "$USERNAME:$PASSWORD" | chpasswd; fi
    ok "Password set."

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  03 — SSH (PASSWORD + KEY)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_ssh() {
    section "03" "SSH — Password + Key Auth"

    if $DRY_RUN; then dry "Setup .ssh dir, install key if provided"
    else
        mkdir -p "/home/$USERNAME/.ssh"
        chmod 700 "/home/$USERNAME/.ssh"
        chown "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
    fi
    ok ".ssh directory ready (mode 700)."

    if [[ -n "$SSH_PUBKEY" ]]; then
        local auth_keys="/home/$USERNAME/.ssh/authorized_keys"
        if $DRY_RUN; then dry "Install key → $auth_keys"
        else
            cat "$SSH_PUBKEY" >> "$auth_keys"
            chmod 600 "$auth_keys"
            chown "$USERNAME:$USERNAME" "$auth_keys"
        fi
        ok "SSH public key installed."
    fi

    local sshd_conf="/etc/ssh/sshd_config"
    if [[ -f "$sshd_conf" ]]; then
        if $DRY_RUN; then
            dry "PasswordAuthentication yes — allow password login"
            dry "PermitRootLogin no     — block direct root SSH"
        else
            # Enable password auth for the deploy user
            sed -i 's/^\s*PasswordAuthentication\s\+no/PasswordAuthentication yes/' "$sshd_conf" 2>/dev/null || true
            grep -qiE '^\s*PasswordAuthentication\s+yes' "$sshd_conf" \
                || echo "PasswordAuthentication yes" >> "$sshd_conf"

            # BLOCK root SSH login entirely.
            # The correct workflow is:
            #   ssh mojahid@server  →  sudo -i  (becomes root with audit trail)
            # Direct root SSH is disabled — no audit trail, no accountability.
            sed -i 's/^\s*PermitRootLogin\s\+yes/PermitRootLogin no/' "$sshd_conf" 2>/dev/null || true
            if grep -qiE '^\s*PermitRootLogin' "$sshd_conf" 2>/dev/null; then
                sed -i 's/^\s*PermitRootLogin.*/PermitRootLogin no/' "$sshd_conf"
            else
                echo "PermitRootLogin no" >> "$sshd_conf"
            fi

            systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
        fi
        ok "sshd: PasswordAuthentication=yes, PermitRootLogin=no."
    fi

    ok "SSH: password + key login ENABLED."
    warn "Root SSH login: BLOCKED — login as user, then switch to root."
    info "  1. ssh $USERNAME@<server-ip>"
    info "  2. sudo -i               ← become root (enter YOUR OWN password, not root password)"
    info "  3. exit                  ← leave root, back to $USERNAME"

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  04 — SUDO
#
#  sudo -i / sudo su      → WITH sudo password  (root access)
#  pm2, apt        → NO sudo password
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_sudo() {
    section "04" "Sudo — Root + Targeted NOPASSWD"

    local f="/etc/sudoers.d/90-$USERNAME"

    if $DRY_RUN; then dry "Write $f (mode 440)"
    else
        cat > "$f" <<SUDOERS
# Sudoers for: $USERNAME
# Generated: $(date '+%Y-%m-%d %H:%M:%S') — node_provision.sh v${SCRIPT_VERSION}

# sudo session active for ${SUDO_TIMEOUT} minutes after password entry
Defaults:$USERNAME  timestamp_timeout=${SUDO_TIMEOUT}

# ── Full root access — REQUIRES password ─────────────────────────────
# apt install, editing system files, systemctl etc.
$USERNAME ALL=(ALL:ALL) ALL


# ── PM2 service — no password needed ─────────────────────────────────
$USERNAME ALL=(ALL) NOPASSWD: /bin/systemctl start pm2-$USERNAME
$USERNAME ALL=(ALL) NOPASSWD: /bin/systemctl stop pm2-$USERNAME
$USERNAME ALL=(ALL) NOPASSWD: /bin/systemctl restart pm2-$USERNAME
$USERNAME ALL=(ALL) NOPASSWD: /bin/systemctl status pm2-$USERNAME
$USERNAME ALL=(ALL) NOPASSWD: /bin/systemctl enable pm2-$USERNAME

# ── apt — no password needed ──────────────────────────────────────────
$USERNAME ALL=(ALL) NOPASSWD: /usr/bin/apt-get
$USERNAME ALL=(ALL) NOPASSWD: /usr/bin/apt

SUDOERS
        chmod 440 "$f"
        visudo -cf "$f" &>/dev/null || { rm -f "$f"; die "Sudoers syntax error."; }
    fi

    ok "Sudoers written."
    ok "Full root:                 sudo -i  or  sudo su -        (your own password — NOT root password)"
    ok "pm2 service:               sudo systemctl restart pm2-$USERNAME  (NO password)"
    ok "apt install:               sudo apt install <pkg>         (NO password)"

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  06 — SHELL PROFILE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_shell() {
    section "05" "Shell Profile — Aliases + NVM + PM2"

    local profile="/home/$USERNAME/.deploy_env"

    if $DRY_RUN; then dry "Write $profile"
    else
        cat > "$profile" << 'PROFILE'
# Deploy environment — node_provision.sh
umask 022

export HISTCONTROL=ignoreboth:erasedups
export HISTSIZE=2000
export HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S  "

export PS1='\[\e[38;5;82m\][\[\e[1;220m\]\u\[\e[0m\]@\[\e[38;5;45m\]\h\[\e[0m\]:\[\e[1;33m\]\w\[\e[0m\]\[\e[38;5;82m\]]\[\e[0m\]\$ '

# NVM
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"

# PM2
[[ -f "$HOME/.pm2/autocomplete.sh" ]] && source "$HOME/.pm2/autocomplete.sh"

# ── PM2 shortcuts ───────────────────────────────────────────────────
alias logs='pm2 logs'
alias pstatus='pm2 status'
alias prestart='pm2 restart all'
alias pmonit='pm2 monit'
alias psave='pm2 save'


# ── Git shortcuts ────────────────────────────────────────────────────
alias pull='git pull origin main'
alias gs='git status'
alias gl='git log --oneline -10'


# ── Server status ────────────────────────────────────────────────────
alias status='server_status'
PROFILE

        chmod 644 "$profile"
        chown "$USERNAME:$USERNAME" "$profile"

        local bashrc="/home/$USERNAME/.bashrc"
        grep -q "deploy_env" "$bashrc" 2>/dev/null \
            || printf '\n[[ -f ~/.deploy_env ]] && source ~/.deploy_env\n' >> "$bashrc"
    fi

    ok "Shell profile written. Aliases: pull, gs, gl, logs, pstatus, psave, status."

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  07 — GIT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

install_git() {
    section "06" "Git"

    if command -v git &>/dev/null; then
        ok "Git already installed: $(git --version)"
    else
        $DRY_RUN || apt-get install -y git 2>&1 | tail -3 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        ok "Git installed."
    fi

    info "Clone a project:  git clone https://github.com/you/repo.git"
    info "Private repo:     git clone https://<token>@github.com/you/repo.git"

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  08 — NVM + NODE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

install_node() {
    $INSTALL_NVM || { section "07" "NVM + Node.js"; warn "Skipped."; section_end; return; }

    section "07" "NVM + Node.js ${NODE_VER}"

    if $DRY_RUN; then dry "Install NVM $NVM_VERSION + Node $NODE_VER as $USERNAME"
    else
        su - "$USERNAME" -c "
            set -e
            export NVM_DIR=\"\$HOME/.nvm\"
            curl -fsSL '$NVM_URL' | bash
            source \"\$NVM_DIR/nvm.sh\"
            nvm install '$NODE_VER'
            nvm use '$NODE_VER'
            nvm alias default '$NODE_VER'
            echo \"Node: \$(node --version)  NPM: \$(npm --version)\"
        " 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done \
            || die "Node.js install failed."
    fi

    ok "Node.js v${NODE_VER} installed via NVM."

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  09 — PM2
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

install_pm2() {
    $INSTALL_PM2 || { section "08" "PM2"; warn "Skipped."; section_end; return; }
    $INSTALL_NVM || { section "08" "PM2"; warn "Skipped — NVM not installed."; section_end; return; }

    section "08" "PM2 — Bulletproof Startup"

    if $DRY_RUN; then
        dry "npm install -g pm2 → startup systemd → enable → save"
    else
        su - "$USERNAME" -c "
            export NVM_DIR=\"\$HOME/.nvm\"; source \"\$NVM_DIR/nvm.sh\"
            npm install -g pm2
            echo \"PM2: \$(pm2 --version)\"
        " 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || die "PM2 install failed."
        ok "PM2 installed."

        local node_bin pm2_bin
        node_bin=$(su - "$USERNAME" -c 'export NVM_DIR="$HOME/.nvm"; source "$NVM_DIR/nvm.sh"; which node' 2>/dev/null || echo "")
        pm2_bin=$(su -  "$USERNAME" -c 'export NVM_DIR="$HOME/.nvm"; source "$NVM_DIR/nvm.sh"; which pm2'  2>/dev/null || echo "")

        if [[ -n "$pm2_bin" && -n "$node_bin" ]]; then
            env PATH="$(dirname "$node_bin"):$PATH" \
                "$pm2_bin" startup systemd -u "$USERNAME" --hp "/home/$USERNAME" \
                2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
            systemctl enable "pm2-$USERNAME" 2>/dev/null \
                && ok "systemd service 'pm2-$USERNAME' enabled." \
                || warn "Enable failed — run manually after first pm2 start."
        fi

        su - "$USERNAME" -c "
            export NVM_DIR=\"\$HOME/.nvm\"; source \"\$NVM_DIR/nvm.sh\"; pm2 save
        " 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        ok "pm2 save called."
    fi

    section_end
}


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  11 — MONITORING
#
#  Three layers:
#    A. Netdata    — real-time system dashboard (CPU, RAM, disk, network)
#    B. PM2 monit  — built-in process monitor for Node.js apps
#    C. server_status script — quick CLI overview of everything
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_monitoring() {
    $SETUP_MON || { section "10" "Monitoring"; warn "Skipped (--no-mon)."; section_end; return; }

    section "10" "Monitoring — Netdata + PM2 + Status Script"

    # ── A. Netdata — real-time server dashboard ───────────────────────────────
    info "Installing Netdata (real-time monitoring dashboard)..."
    if $DRY_RUN; then
        dry "Install Netdata via kickstart script"
    else
        if ! command -v netdata &>/dev/null; then
            curl -fsSL https://get.netdata.cloud/kickstart.sh | bash -s -- \
                --non-interactive \
                --stable-channel \
                --disable-telemetry \
                2>&1 | tail -10 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || {
                warn "Netdata install failed — try manually: bash <(curl -fsSL https://get.netdata.cloud/kickstart.sh)"
            }
        else
            ok "Netdata already installed."
        fi
    fi

    # Netdata runs on port 19999 by default — restrict to localhost only
    if [[ -f /etc/netdata/netdata.conf ]]; then
        if $DRY_RUN; then dry "Restrict Netdata to localhost:19999"
        else
            # Bind only to localhost — access via SSH tunnel, not public internet
            sed -i 's/.*bind to.*/\tbind to = 127.0.0.1/' /etc/netdata/netdata.conf 2>/dev/null || true
            systemctl restart netdata 2>/dev/null || true
        fi
        ok "Netdata: bound to 127.0.0.1:19999 (localhost only)."
        info "Access dashboard via SSH tunnel:"
        info "  ssh -L 19999:localhost:19999 $USERNAME@<server-ip>"
        info "  Then open: http://localhost:19999"
    fi

    # ── B. PM2 log rotation module ────────────────────────────────────────────
    if $INSTALL_PM2 && ! $DRY_RUN; then
        su - "$USERNAME" -c "
            export NVM_DIR=\"\$HOME/.nvm\"; source \"\$NVM_DIR/nvm.sh\"
            pm2 install pm2-logrotate 2>/dev/null || true
            pm2 set pm2-logrotate:max_size 50M 2>/dev/null || true
            pm2 set pm2-logrotate:retain 10   2>/dev/null || true
            pm2 set pm2-logrotate:compress true 2>/dev/null || true
        " 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        ok "PM2 log rotation module installed (50MB max, 10 files, compressed)."
    fi

    # ── C. server_status — quick CLI overview script ──────────────────────────
    if $DRY_RUN; then dry "Write $STATUS_SCRIPT"
    else
        # Capture username for use inside heredoc
        local deploy_user="$USERNAME"
        cat > "$STATUS_SCRIPT" <<STATUSSCRIPT
#!/usr/bin/env bash
# server_status — Quick overview of all running projects
# Run this anytime: server_status

if [[ -t 1 ]]; then
    R=\$'\033[0m' BOLD=\$'\033[1m' GRN=\$'\033[38;5;82m' BLU=\$'\033[38;5;33m'
    YLW=\$'\033[38;5;220m' WHT=\$'\033[38;5;255m' GRY=\$'\033[38;5;244m'
    CYN=\$'\033[38;5;45m' RED=\$'\033[38;5;196m'
else
    R='' BOLD='' GRN='' BLU='' YLW='' WHT='' GRY='' CYN='' RED=''
fi

HR="────────────────────────────────────────────────────────────────────────────"

echo ""
echo -e "\${BLU}\${BOLD}  Server Status — \$(hostname) — \$(date '+%Y-%m-%d %H:%M:%S')\${R}"
echo -e "  \${GRY}\${HR}\${R}"

# ── System Resources ──────────────────────────────────────────────────────────
echo ""
echo -e "  \${BOLD}\${WHT}System Resources\${R}"

# CPU load
cpu_load=\$(uptime | awk -F'load average:' '{print \$2}' | awk '{print \$1}' | tr -d ',')
echo -e "  \${GRY}CPU Load (1m):\${R}  \${WHT}\${cpu_load}\${R}"

# Memory
mem_total=\$(free -m | awk '/^Mem:/{print \$2}')
mem_used=\$(free  -m | awk '/^Mem:/{print \$3}')
mem_pct=\$(( mem_used * 100 / mem_total ))
if   (( mem_pct >= 90 )); then mem_color=\$RED
elif (( mem_pct >= 70 )); then mem_color=\$YLW
else                           mem_color=\$GRN; fi
echo -e "  \${GRY}Memory:\${R}        \${mem_color}\${mem_used}MB / \${mem_total}MB (\${mem_pct}%)\${R}"

# Disk
disk_pct=\$(df -h / | awk 'NR==2{print \$5}' | tr -d '%')
disk_used=\$(df -h / | awk 'NR==2{print \$3}')
disk_total=\$(df -h / | awk 'NR==2{print \$2}')
if   (( disk_pct >= 90 )); then disk_color=\$RED
elif (( disk_pct >= 70 )); then disk_color=\$YLW
else                            disk_color=\$GRN; fi
echo -e "  \${GRY}Disk (/):\${R}      \${disk_color}\${disk_used} / \${disk_total} (\${disk_pct}%)\${R}"

# Uptime
echo -e "  \${GRY}Uptime:\${R}        \${WHT}\$(uptime -p)\${R}"

# ── PM2 Apps ──────────────────────────────────────────────────────────────────
echo ""
echo -e "  \${BOLD}\${WHT}Node.js Apps (PM2)\${R}"
if command -v su &>/dev/null && id "${deploy_user}" &>/dev/null; then
    su - "${deploy_user}" -s /bin/bash -c \
        'export NVM_DIR="\$HOME/.nvm"; source "\$NVM_DIR/nvm.sh" 2>/dev/null; pm2 list 2>/dev/null' \
        2>/dev/null || echo -e "  \${GRY}  pm2 not available or no apps running\${R}"
else
    echo -e "  \${GRY}  Deploy user not found\${R}"
fi

# ── Firewall ──────────────────────────────────────────────────────────────────
echo ""
echo -e "  \${BOLD}\${WHT}Firewall (UFW)\${R}"
if command -v ufw &>/dev/null; then
    ufw_status=\$(ufw status 2>/dev/null | head -1)
    echo -e "  \${GRY}\${ufw_status}\${R}"
fi

# ── Netdata ───────────────────────────────────────────────────────────────────
echo ""
echo -e "  \${BOLD}\${WHT}Real-Time Dashboard (Netdata)\${R}"
if command -v netdata &>/dev/null; then
    echo -e "  \${GRN}✔\${R}  Running — access via SSH tunnel:"
    echo -e "  \${GRY}     ssh -L 19999:localhost:19999 ${deploy_user}@<server-ip>\${R}"
    echo -e "  \${GRY}     Then open: http://localhost:19999\${R}"
else
    echo -e "  \${GRY}  Netdata not installed\${R}"
fi

echo ""
echo -e "  \${GRY}\${HR}\${R}"
echo -e "  \${GRY}PM2 live:   pm2 monit   │   Logs: pm2 logs   │   Nginx: nginx-logs\${R}"
echo ""
STATUSSCRIPT

        chmod +x "$STATUS_SCRIPT"

        # Allow the deploy user to run it too
        ln -sf "$STATUS_SCRIPT" "/home/$USERNAME/server_status" 2>/dev/null || true
    fi

    ok "server_status script installed → $STATUS_SCRIPT"
    ok "Run from anywhere:  server_status"

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  12 — KERNEL HARDENING
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

harden_kernel() {
    section "11" "Kernel Hardening (sysctl)"

    if $DRY_RUN; then dry "Write $SYSCTL_CONF && sysctl -p"
    else
        cat > "$SYSCTL_CONF" <<SYSCTL
# Kernel hardening — node_provision.sh v${SCRIPT_VERSION}

# IP spoofing protection
net.ipv4.conf.all.rp_filter              = 1
net.ipv4.conf.default.rp_filter          = 1

# SYN flood protection
net.ipv4.tcp_syncookies                  = 1
net.ipv4.tcp_max_syn_backlog             = 2048

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects       = 0
net.ipv4.conf.default.accept_redirects   = 0
net.ipv4.conf.all.send_redirects         = 0

# Log suspicious packets
net.ipv4.conf.all.log_martians           = 1
net.ipv4.icmp_echo_ignore_broadcasts     = 1

# Hardlink/symlink protection
fs.protected_hardlinks                   = 1
fs.protected_symlinks                    = 1

# Node.js performance tuning
fs.file-max                              = 100000
net.core.somaxconn                       = 65535
net.ipv4.tcp_max_tw_buckets              = 1440000
SYSCTL
        chmod 644 "$SYSCTL_CONF"
        sysctl -p "$SYSCTL_CONF" 2>/dev/null | tail -3 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
    fi

    ok "Kernel: SYN flood, IP spoof, ICMP, file descriptor limits for Node.js."

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  13 — FAIL2BAN
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_fail2ban() {
    section "12" "fail2ban — Brute Force Protection"

    if ! command -v fail2ban-server &>/dev/null; then
        warn "fail2ban not installed: apt-get install -y fail2ban"
        section_end; return
    fi

    if $DRY_RUN; then dry "Write fail2ban jail config"
    else
        cat > "/etc/fail2ban/jail.d/node-provision.conf" <<F2B
[sshd]
enabled  = true
port     = ssh
logpath  = /var/log/auth.log
maxretry = 5
findtime = 600
bantime  = 3600
ignoreip = 127.0.0.1/8 ::1
F2B
        chmod 644 "/etc/fail2ban/jail.d/node-provision.conf"
        systemctl restart fail2ban 2>/dev/null || true
    fi

    ok "fail2ban: ban after 5 failed SSH attempts (1 hour)."

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  14 — UFW
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_firewall() {
    $GEN_FW || { section "13" "UFW"; warn "Skipped."; section_end; return; }

    section "13" "UFW Firewall"

    if ! command -v ufw &>/dev/null; then
        warn "UFW not installed: apt-get install -y ufw"; section_end; return
    fi

    run "ufw default deny incoming"
    run "ufw default allow outgoing"
    run "ufw allow 22/tcp   comment 'SSH'"
    run "ufw allow 19999/tcp comment 'Netdata — accessible via SSH tunnel only'"

    $DRY_RUN || ufw --force enable 2>/dev/null || true

    ok "UFW active: SSH(22) open. Allow other ports as needed."
    info "Open more ports as needed:  sudo ufw allow <port>/tcp"

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  15 — LOGROTATE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_logrotate() {
    section "14" "Log Rotation"

    if $DRY_RUN; then dry "Write /etc/logrotate.d/$USERNAME"
    else
        cat > "/etc/logrotate.d/$USERNAME" <<LOGROTATE
/home/$USERNAME/.pm2/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 $USERNAME $USERNAME
    sharedscripts
    postrotate
        su - $USERNAME -s /bin/bash -c \
            'export NVM_DIR="\$HOME/.nvm"; source "\$NVM_DIR/nvm.sh"; pm2 reloadLogs' \
            2>/dev/null || true
    endscript
}
LOGROTATE
        chmod 644 "/etc/logrotate.d/$USERNAME"
    fi

    ok "Logrotate: PM2 logs 14-day retention, daily rotation, compressed."

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  16 — SUMMARY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

print_summary() {
    echo ""
    echo -e "${BLU}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${BLU}${BOLD}║${R}${WHT}${BOLD}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  ✦  Provisioning Complete — $USERNAME"
    echo -e "${BLU}${BOLD}  ╠${HR2}╣${R}"

    _row() { printf "  ${BLU}${BOLD}║${R}  ${GRY}%-24s${R}  ${WHT}%-48s${R}  ${BLU}${BOLD}║${R}\n" "$1" "$2"; }
    _sep() { echo -e "  ${BLU}${BOLD}╠${HR2}╣${R}"; }

    _row "User"           "$USERNAME"
    _row "Home"           "/home/$USERNAME"
    _row "Node.js"        "v${NODE_VER} via NVM ${NVM_VERSION}"
    _row "PM2"            "pm2-$USERNAME (systemd, auto-start on reboot)"
    _row "SSH"            "password + key (both work)"
    _row "Root Access"    "ssh as user → sudo -i  (no direct root SSH)"
    _row "Monitoring"     "server_status  |  pm2 monit  |  Netdata :19999"

    if ! $DRY_RUN; then
        _sep
        printf "  ${BLU}${BOLD}║${R}  ${YLW}${BOLD}%-24s${R}  ${ORG}${BOLD}%-48s${R}  ${BLU}${BOLD}║${R}\n" \
            "⚠  Password" "$PASSWORD"
        printf "  ${BLU}${BOLD}║${R}  ${GRY}%-24s${R}  %-48s  ${BLU}${BOLD}║${R}\n" \
            "" "Save this — not shown again."
    fi

    _sep
    printf  "  ${BLU}${BOLD}║${R}${WHT}${BOLD}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  🚀  Deploy a Node.js Project (repeat for each project)"
    _sep

    local node_steps=(
        "1. ssh $USERNAME@<server-ip>"
        "2. git clone https://github.com/you/repo.git ~/projects/myapp"
        "3. cd ~/projects/myapp && npm install"
        "4. nano .env   ← add your secrets"
        "5. pm2 start app.js --name myapp -- --port 3000"
        "6. pm2 save    ← REQUIRED — survives server reboot"
    )
    for s in "${node_steps[@]}"; do
        printf "  ${BLU}${BOLD}║${R}  ${GRN}·${R}  ${WHT}%-70s${R}  ${BLU}${BOLD}║${R}\n" "$s"
    done

    _sep
    printf  "  ${BLU}${BOLD}║${R}${WHT}${BOLD}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  📡  Monitoring"
    _sep

    local mon_steps=(
        "server_status              → quick overview of everything"
        "pm2 monit                  → live Node.js process monitor"
        "pm2 logs                   → live app logs"
        "Netdata dashboard:"
        "  ssh -L 19999:localhost:19999 $USERNAME@<server-ip>"
        "  Open browser: http://localhost:19999"
        "  Shows: CPU, RAM, disk, network, per-process metrics in real-time"
    )
    for s in "${mon_steps[@]}"; do
        printf "  ${BLU}${BOLD}║${R}  ${CYN}›${R}  ${WHT}%-70s${R}  ${BLU}${BOLD}║${R}\n" "$s"
    done

    _sep
    printf  "  ${BLU}${BOLD}║${R}${WHT}${BOLD}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  📖  Second Project — Just Repeat"
    _sep

    local multi_steps=(
        "pm2 start app.js --name blog -- --port 4000"
        "pm2 save"
        "  → blog.com now points to your second app"
        "  → totally independent from the first project"
    )
    for s in "${multi_steps[@]}"; do
        printf "  ${BLU}${BOLD}║${R}  ${GRN}·${R}  ${WHT}%-70s${R}  ${BLU}${BOLD}║${R}\n" "$s"
    done

    echo -e "${BLU}${BOLD}  ╚${HR2}╝${R}"
    echo ""

    $DRY_RUN && echo -e "  ${PRP}${BOLD}  ◈  DRY-RUN — Zero changes made.${R}\n"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  MAIN
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE" && chmod 640 "$LOG_FILE" 2>/dev/null || true

    parse_args "$@"
    show_banner
    prompt_inputs   # ask for username, password, Node version if not passed as flags

    _log INFO "=== node_provision.sh v${SCRIPT_VERSION} started. User=$USERNAME ==="

    preflight           # 01
    create_user         # 02
    setup_ssh           # 03 — password + key; root SSH blocked
    setup_sudo          # 04 — full root + targeted NOPASSWD
    setup_shell         # 06 — aliases, NVM, PM2
    install_git         # 07
    install_node        # 08
    install_pm2         # 09 — bulletproof
    setup_monitoring    # 11 — Netdata + PM2 logrotate + server_status
    harden_kernel       # 12
    setup_fail2ban      # 13
    setup_firewall      # 14
    setup_logrotate     # 15
    print_summary       # 16

    _log INFO "=== Provisioning complete. User=$USERNAME ==="
}

main "$@"