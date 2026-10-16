#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  init.sh  —  Node.js Production Server Provisioning  v8.0.0                 ║
# ║  Ubuntu 20.04 / 22.04 / 24.04 LTS                                           ║
# ╠══════════════════════════════════════════════════════════════════════════════╣
# ║                                                                              ║
# ║  WHAT THIS DOES                                                              ║
# ║  01. Preflight — root check, OS detection, SSH key validation                ║
# ║  02. Creates deploy user with password + SSH key access                      ║
# ║  03. SSH — password + key login; direct root SSH blocked                     ║
# ║  04. Sudo — full root + targeted NOPASSWD (pm2, apt)                        ║
# ║  05. Shell profile — aliases, NVM, PM2 auto-complete                        ║
# ║  06. Git — install and configure                                             ║
# ║  07. NVM + Node.js installation                                              ║
# ║  08. PM2 — process manager + bulletproof systemd startup                    ║
# ║  09. Monitoring — Cockpit Web Console (Host Management & Logs)             ║
# ║      + PM2 Admin Bridge & GUI Extension (Node.js Process Control)            ║
# ║      + status script + compact journald (Zero-Idle-RAM)                      ║
# ║  10. Kernel hardening (sysctl)                                               ║
# ║  11. fail2ban — brute force SSH protection                                   ║
# ║  12. UFW firewall                                                            ║
# ║  13. Log rotation (PM2 logs)                                                 ║
# ║                                                                              ║
# ╠══════════════════════════════════════════════════════════════════════════════╣
# ║                                                                              ║
# ║  USAGE                                                                       ║
# ║    sudo ./init.sh                         (interactive — recommended)        ║
# ║    sudo ./init.sh -u <username> [OPTIONS]                                    ║
# ║                                                                              ║
# ║  OPTIONS                                                                     ║
# ║    -u  USERNAME     Deploy username               (required)                 ║
# ║    -p  PASSWORD     Custom password               (auto-generated if omitted)║
# ║    -k  PUBKEY       SSH public key file           (optional)                 ║
# ║    -n  NODE_VER     Node.js version e.g. 20, 22  (default: 20)              ║
# ║        --no-nvm     Skip NVM + Node.js                                       ║
# ║        --no-pm2     Skip PM2                                                 ║
# ║        --no-fw      Skip UFW                                                 ║
# ║        --no-mon     Skip Cockpit Web Console & PM2 GUI monitoring            ║
# ║    -h  --help       Show this help and exit                                  ║
# ║                                                                              ║
# ║  EXAMPLES                                                                    ║
# ║    sudo ./init.sh                         ← fully interactive                ║
# ║    sudo ./init.sh -u mojahid -n 20        ← skip username/node prompts      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set -euo pipefail
IFS=$'\n\t'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  CONFIG
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

readonly SCRIPT_VERSION="8.0.0"
readonly LOG_FILE="/var/log/node_provision.log"
readonly NVM_VERSION="v0.40.1"
readonly NVM_URL="https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"
readonly PASS_LEN=16
readonly SUDO_TIMEOUT=15
readonly SYSCTL_CONF="/etc/sysctl.d/99-node-provision.conf"
readonly STATUS_SCRIPT="/usr/local/bin/server_status"
# Prompt behaviour: when true the script will ask for these passwords up-front.
readonly REQUIRE_USER_PW=true
readonly REQUIRE_ROOT_PW=true
OPEN_NGINX_PORTS=false
OPEN_EMAIL_PORTS=false
CUSTOM_PORTS=""
USER_PW=""    # captured (hidden) deploy-user password for informational/confirmation use
ROOT_PW=""    # captured (hidden) root password for informational/confirmation use

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  COLORS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [[ -t 1 ]] && tput colors &>/dev/null && (( $(tput colors) >= 8 )); then
    R=$'\033[0m'  BOLD=$'\033[1m'  DIM=$'\033[2m'  ITAL=$'\033[3m'
    GRN=$'\033[38;5;82m'   BLU=$'\033[38;5;33m'   CYN=$'\033[38;5;45m'
    YLW=$'\033[38;5;220m'  ORG=$'\033[38;5;208m'  PRP=$'\033[38;5;135m'
    WHT=$'\033[38;5;255m'  GRY=$'\033[38;5;244m'  RED=$'\033[38;5;196m'
    TICK="${GRN}✔${R}"  CROSS="${RED}✘${R}"  WARN_IC="${YLW}⚠${R}"
    ARROW="${CYN}›${R}"  BULLET="${PRP}◆${R}"
else
    R='' BOLD='' DIM='' ITAL='' GRN='' BLU='' CYN='' YLW='' ORG='' PRP='' WHT='' GRY='' RED=''
    TICK='[OK]' CROSS='[ERR]' WARN_IC='[WARN]' ARROW='->' BULLET='*'
fi

readonly HR2="════════════════════════════════════════════════════════════════════════════"
readonly HR="────────────────────────────────────────────────────────────────────────────"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  OUTPUT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

_log()  { printf '[%s] [%-5s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >> "$LOG_FILE" 2>/dev/null || true; }
ok()    { echo -e "  ${TICK}  $*";                _log INFO "$*"; }
warn()  { echo -e "  ${WARN_IC}  ${YLW}$*${R}";   _log WARN "$*"; }
info()  { echo -e "  ${ARROW}  ${GRY}$*${R}";     _log INFO "$*"; }
die()   { echo -e "\n  ${CROSS}  ${RED}${BOLD}FATAL: $*${R}\n" >&2; _log ERROR "$*"; exit 1; }

section()     {
    echo ""
    echo -e "  ${PRP}${BOLD}┌─[ ${CYN}Step $1 of 13${PRP} ]──${WHT} $2 ${PRP}${R}"
    echo -e "  ${PRP}${DIM}│${R}"
}
section_end() { echo -e "  ${PRP}${DIM}└${HR:0:60}${R}"; echo ""; }

run() {
    eval "$*" 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  BANNER
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

show_banner() {
    clear 2>/dev/null || true
    echo ""
    echo -e "${PRP}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${PRP}${BOLD}║${R}  ${CYN}${BOLD}%-72s${R}  ${PRP}${BOLD}║${R}\n" \
            "init.sh  --  Node.js Production Server Provisioner  v${SCRIPT_VERSION}"
    printf  "  ${PRP}${BOLD}║${R}  ${GRY}%-72s${R}  ${PRP}${BOLD}║${R}\n" \
            "Ubuntu 20.04 / 22.04 / 24.04 LTS  ·  Git · NVM · Node.js · PM2 · Cockpit"
    echo -e "${PRP}${BOLD}  ╠${HR2}╣${R}"
    printf  "  ${PRP}${BOLD}║${R}  ${GRN}%-14s${R}  ${GRY}%-56s${R}  ${PRP}${BOLD}║${R}\n" \
            "Interactive" "sudo ./init.sh"
    printf  "  ${PRP}${BOLD}║${R}  ${GRN}%-14s${R}  ${GRY}%-56s${R}  ${PRP}${BOLD}║${R}\n" \
            "With flags" "sudo ./init.sh -u <user> -n 20"
    echo -e "${PRP}${BOLD}  ╠${HR2}╣${R}"
    printf  "  ${PRP}${BOLD}║${R}  ${DIM}${GRY}%-72s${R}  ${PRP}${BOLD}║${R}\n" \
            "github.com/mojahid2021/Production-Server"
    echo -e "${PRP}${BOLD}  ╚${HR2}╝${R}"
    echo ""
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  USAGE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

usage() {
    echo ""
    echo -e "${PRP}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${PRP}${BOLD}║${R}  ${CYN}${BOLD}%-72s${R}  ${PRP}${BOLD}║${R}\n" \
            "init.sh  --  Node.js Production Server Provisioner  v${SCRIPT_VERSION}"
    printf  "  ${PRP}${BOLD}║${R}  ${DIM}${GRY}%-72s${R}  ${PRP}${BOLD}║${R}\n" \
            "github.com/mojahid2021/Production-Server"
    echo -e "${PRP}${BOLD}  ╚${HR2}╝${R}"
    echo ""
    echo -e "  ${BOLD}${WHT}Usage${R}"
    echo -e "  ${PRP}${DIM}${HR:0:60}${R}"
    echo -e "    ${CYN}sudo ./init.sh${R}                          ${GRY}# fully interactive (recommended)${R}"
    echo -e "    ${CYN}sudo ./init.sh${R} ${WHT}-u <username> [OPTIONS]${R}  ${GRY}# pass values directly${R}"
    echo ""
    echo -e "  ${BOLD}${WHT}Options${R}"
    echo -e "  ${PRP}${DIM}${HR:0:60}${R}"
    printf  "    ${CYN}%-22s${R}  ${WHT}%s${R}\n" \
        "-u  USERNAME"   "Deploy username                       (required)" \
        "-p  PASSWORD"   "Custom password                       (auto-generated if omitted)" \
        "-k  PUBKEY"     "Path to SSH public key file           (optional)" \
        "-n  NODE_VER"   "Node.js version: 18, 20, 22, lts/*   (default: 20)" \
        "    --swap-size" "Swap size: 2G, 1G, 4G, 0/none to skip (default: auto-detected)" \
        "    --swap-threshold" "RAM % when swap activates, e.g. 90 (default: 90%)" \
        "    --swappiness" "Direct kernel swappiness 0-100      (default: 10)" \
        "    --no-nvm"   "Skip NVM + Node.js installation" \
        "    --no-pm2"   "Skip PM2 installation" \
        "    --no-fw"    "Skip UFW firewall configuration" \
        "    --no-mon"   "Skip Cockpit Web Console installation" \
        "-h  --help"     "Show this help and exit"
    echo ""
    echo -e "  ${BOLD}${WHT}Examples${R}"
    echo -e "  ${PRP}${DIM}${HR:0:60}${R}"
    echo -e "    ${GRN}sudo ./init.sh${R}                          ${GRY}# interactive wizard${R}"
    echo -e "    ${GRN}sudo ./init.sh -u mojahid -n 20${R}         ${GRY}# set user + Node version${R}"
    echo -e "    ${GRN}sudo ./init.sh -u deploy --swap-size 2G --swap-threshold 90${R}"
    echo -e "    ${GRN}sudo ./init.sh -u deploy -k ~/.ssh/id_rsa.pub${R}  ${GRY}# with SSH key${R}"
    echo ""
    exit 0
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  PARSE ARGS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

parse_args() {
    USERNAME="" CUSTOM_PASS="" SSH_PUBKEY="" NODE_VER="20"
    INSTALL_NVM=true INSTALL_PM2=true
    GEN_FW=true SETUP_MON=true
    SWAP_SIZE="" SWAP_RAM_THRESHOLD="" SWAPPINESS=""
    IS_EXISTING_USER=false PASSWORD=""

    # Parse any flags that were passed
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u)               USERNAME="${2:?}";    shift 2 ;;
            -p)               CUSTOM_PASS="${2:?}"; shift 2 ;;
            -k)               SSH_PUBKEY="${2:?}";  shift 2 ;;
            -n)               NODE_VER="${2:?}";    shift 2 ;;
            --swap-size)      SWAP_SIZE="${2:?}";   shift 2 ;;
            --swap-threshold) SWAP_RAM_THRESHOLD="${2:?}"; shift 2 ;;
            --swappiness)     SWAPPINESS="${2:?}"; shift 2 ;;
            --no-nvm)         INSTALL_NVM=false;    shift ;;
            --no-pm2)         INSTALL_PM2=false;    shift ;;
            --no-fw)          GEN_FW=false;         shift ;;
            --no-mon)         SETUP_MON=false;      shift ;;
            -h|--help)        usage ;;
            *)                die "Unknown option: '$1'. Use -h for help." ;;
        esac
    done

    if [[ -n "$USERNAME" ]] && id "$USERNAME" &>/dev/null; then
        IS_EXISTING_USER=true
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  INTERACTIVE PROMPTS
#  Called after show_banner so questions appear under the banner.
#  Only asks for values that were NOT already supplied via flags.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

get_input() {
    # Usage: get_input [-s]
    # Reads a line into REPLY. If -s passed, reads silently (no echo).
    local silent=false
    if [[ "${1:-}" == "-s" ]]; then silent=true; fi

    if [[ -e /dev/tty && -r /dev/tty ]]; then
        if $silent; then read -rs REPLY </dev/tty; else read -r REPLY </dev/tty; fi
    else
        if $silent; then read -rs REPLY; else read -r REPLY; fi
    fi
}

prompt_inputs() {
    # ── Internal helpers ──────────────────────────────────────────────────────
    # Total visible width of step borders (matches the ╔╗ box width of 76)
    local _STEP_W=74
    # Print a step header box with dynamic right-padding
    _step() {
        local num="$1" total="$2" title="$3"
        local prefix="─ Step ${num}/${total}  ──  ${title} "
        local pad_len=$(( _STEP_W - ${#prefix} ))
        [[ $pad_len -lt 2 ]] && pad_len=2
        local pad; pad=$(printf '─%.0s' $(seq 1 $pad_len))
        echo ""
        echo -e "  ${PRP}${BOLD}┌${prefix}${pad}${R}"
        echo -e "  ${PRP}${BOLD}│${R}"
    }
    # Print a labelled hint line under a step
    _hint() { echo -e "  ${PRP}${BOLD}│${R}  ${GRY}$*${R}"; }
    # Close the step box — same width as _step header
    _step_end() { echo -e "  ${PRP}${BOLD}└$(printf '─%.0s' $(seq 1 "${_STEP_W}"))${R}"; echo ""; }
    # Print an inline prompt arrow
    _prompt() { printf "  ${PRP}${BOLD}│${R}  ${CYN}${BOLD}❯${R}  "; }
    # Print a success line
    _ok()   { echo -e "  ${PRP}${BOLD}│${R}  ${TICK}  $*"; }
    # Print a warning line inside a step
    _warn() { echo -e "  ${PRP}${BOLD}│${R}  ${WARN_IC}  ${YLW}$*${R}"; }

    # ── Header ────────────────────────────────────────────────────────────────
    echo ""
    echo -e "${PRP}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${PRP}${BOLD}║${R}  ${WHT}${BOLD}%-72s${R}  ${PRP}${BOLD}║${R}\n" \
            "Interactive Setup Wizard"
    printf  "  ${PRP}${BOLD}║${R}  ${GRY}%-72s${R}  ${PRP}${BOLD}║${R}\n" \
            "Answer each prompt below.  Press Enter to accept any default value."
    echo -e "${PRP}${BOLD}  ╚${HR2}╝${R}"

    # ══════════════════════════════════════════════════════════════════════════
    # STEP 1 — Username
    # ══════════════════════════════════════════════════════════════════════════
    if [[ -z "$USERNAME" ]]; then
        _step 1 5 "Deploy Username"
        _hint "The Linux user that will own and run your Node.js projects."
        _hint "Rules: lowercase letters, digits, _ or -  ·  max 31 chars  ·  start with a letter"
        _hint "Example:  mojahid   deploy   webadmin"
        echo -e "  ${PRP}${BOLD}│${R}"
        while true; do
            _prompt && get_input && USERNAME="$REPLY"
            USERNAME="${USERNAME// /}"   # strip accidental spaces

            if [[ -z "$USERNAME" ]]; then
                _warn "Username cannot be empty. Please try again."
                continue
            fi
            if ! [[ "$USERNAME" =~ ^[a-z][a-z0-9_-]{1,30}$ ]]; then
                _warn "Invalid username — must start with a lowercase letter, max 31 chars."
                USERNAME=""
                continue
            fi
            if id "$USERNAME" &>/dev/null; then
                _hint "User '${USERNAME}' already exists on this system."
                _hint "Existing account will be updated and reconfigured (home directory preserved)."
                _ok "Existing user recognized:  ${WHT}${BOLD}${USERNAME}${R}"
                IS_EXISTING_USER=true
                break
            fi
            _ok "Username set:  ${WHT}${BOLD}${USERNAME}${R}"
            break
        done
        _step_end
    else
        echo ""
        echo -e "  ${TICK}  ${GRY}Username provided via flag:${R}  ${WHT}${BOLD}${USERNAME}${R}"
        echo ""
    fi

    # ══════════════════════════════════════════════════════════════════════════
    # STEP 2 — Password
    # ══════════════════════════════════════════════════════════════════════════
    if [[ -z "$CUSTOM_PASS" ]]; then
        _step 2 5 "Deploy User Password"
        if $IS_EXISTING_USER; then
            _hint "User '${USERNAME}' already exists. Press Enter to KEEP current password,"
            _hint "or type a new custom password (min 8 chars) to change it:"
            echo -e "  ${PRP}${BOLD}│${R}"
            _prompt && get_input -s && CUSTOM_PASS="$REPLY"
            echo ""
            if [[ -z "$CUSTOM_PASS" ]]; then
                CUSTOM_PASS="__KEEP__"
                _ok "Current user password will be preserved."
            elif [[ ${#CUSTOM_PASS} -lt 8 ]]; then
                _warn "Password too short (min 8 chars) — preserving current password."
                CUSTOM_PASS="__KEEP__"
            else
                _ok "New custom password accepted  ${GRY}(length: ${#CUSTOM_PASS} chars)${R}"
            fi
        else
            _hint "Type a custom password, or press Enter to auto-generate a secure one."
            _hint "Minimum 8 characters if you choose your own.  Input is hidden."
            echo -e "  ${PRP}${BOLD}│${R}"
            _prompt && get_input -s && CUSTOM_PASS="$REPLY"
            echo ""   # newline after hidden input

            if [[ -z "$CUSTOM_PASS" ]]; then
                _ok "Password will be auto-generated  ${GRY}(${PASS_LEN} chars, mixed case + symbols)${R}"
            elif [[ ${#CUSTOM_PASS} -lt 8 ]]; then
                _warn "Password too short (min 8 chars) — will auto-generate a secure one instead."
                CUSTOM_PASS=""
            else
                _ok "Custom password accepted  ${GRY}(length: ${#CUSTOM_PASS} chars — not shown again)${R}"
            fi
        fi
        _step_end
    else
        echo -e "  ${TICK}  ${GRY}Password provided via flag.${R}"
        echo ""
    fi

    # ══════════════════════════════════════════════════════════════════════════
    # STEP 3 — Node.js version
    # ══════════════════════════════════════════════════════════════════════════
    _step 3 5 "Node.js Version"
    _hint "Which Node.js version to install via NVM."
    _hint "Options: 18  20  22  lts/*     Recommended: 20"
    _hint "Press Enter to accept the default: ${WHT}${NODE_VER}${GRY}"
    echo -e "  ${PRP}${BOLD}│${R}"
    _prompt && get_input && _node_input="$REPLY"
    if [[ -n "$_node_input" ]]; then
        NODE_VER="$_node_input"
    fi
    _ok "Node.js version:  ${WHT}${BOLD}v${NODE_VER}${R}"
    _step_end

    # ══════════════════════════════════════════════════════════════════════════
    # STEP 4 — Additional Firewall Ports
    # ══════════════════════════════════════════════════════════════════════════
    _step 4 5 "Additional Firewall Ports"
    _hint "By default, only SSH port is open. Choose additional services to allow."
    _hint "Options: nginx (80/443), email (SMTP/IMAP/POP3), custom ports, or combinations."
    _hint "Examples: 'nginx', 'email', 'custom', 'both', 'all', or press Enter for SSH only."
    echo -e "  ${PRP}${BOLD}│${R}"
    _prompt && get_input && _ports_input="$REPLY"
    case "${_ports_input,,}" in
        nginx|n) OPEN_NGINX_PORTS=true; _ok "Nginx ports (80/443) will be opened." ;;
        email|e) OPEN_EMAIL_PORTS=true; _ok "Email ports (25,465,587,143,993,110,995) will be opened." ;;
        custom|c) 
            printf "  ${PRP}${BOLD}│${R}  ${CYN}${BOLD}❯${R}  ${WHT}Custom ports${R}  ${GRY}(comma-separated, e.g., 3000/tcp,8080/udp):${R}  "
            get_input && CUSTOM_PORTS="$REPLY"
            if [[ -n "$CUSTOM_PORTS" ]]; then
                _ok "Custom ports will be opened: $CUSTOM_PORTS"
            else
                _warn "No custom ports specified."
            fi
            ;;
        both|b) OPEN_NGINX_PORTS=true; OPEN_EMAIL_PORTS=true; _ok "Nginx and Email ports will be opened." ;;
        all|a) OPEN_NGINX_PORTS=true; OPEN_EMAIL_PORTS=true; 
            printf "  ${PRP}${BOLD}│${R}  ${CYN}${BOLD}❯${R}  ${WHT}Additional custom ports${R}  ${GRY}(optional, comma-separated):${R}  "
            get_input && CUSTOM_PORTS="$REPLY"
            _ok "All standard ports + custom will be opened." ;;
        *) _ok "No additional ports — only SSH will be open." ;;
    esac
    _step_end

    # ══════════════════════════════════════════════════════════════════════════
    # STEP 5 — Memory Cushion & Swap Configuration
    # ══════════════════════════════════════════════════════════════════════════
    local mem_total_kb mem_total_mb mem_total_gb
    mem_total_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
    mem_total_mb=$(( mem_total_kb / 1024 ))
    if (( mem_total_mb > 0 )); then
        mem_total_gb=$(awk "BEGIN {printf \"%.1f\", $mem_total_mb / 1024}" 2>/dev/null || echo "$(( mem_total_mb / 1024 ))")
    else
        mem_total_gb="0.0"
    fi

    local swap_total_kb swap_used_kb swap_total_mb swap_used_mb
    swap_total_kb=$(grep SwapTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
    swap_used_kb=$(awk '/SwapTotal/{t=$2} /SwapFree/{f=$2} END{print (t-f)}' /proc/meminfo 2>/dev/null || echo 0)
    swap_total_mb=$(( swap_total_kb / 1024 ))
    swap_used_mb=$(( swap_used_kb / 1024 ))

    # Existing active swap files/partitions
    local existing_swap_summary
    if (( swap_total_mb > 0 )); then
        existing_swap_summary=$(awk 'NR>1 {printf "%s (%d MB)", $1, $3/1024}' /proc/swaps 2>/dev/null || echo "${swap_total_mb} MB")
    else
        existing_swap_summary="None (0 MB configured)"
    fi

    # Intelligent recommendation based on physical RAM
    local suggested_swap suggested_reason
    if (( mem_total_mb <= 1100 )); then
        suggested_swap="2G"
        suggested_reason="<=1GB RAM host: 2GB swap prevents catastrophic Out-Of-Memory crashes during npm build / spikes."
    elif (( mem_total_mb <= 2100 )); then
        suggested_swap="2G"
        suggested_reason="2GB RAM host: 2GB swap provides a 1:1 memory cushion for smooth multitasking."
    elif (( mem_total_mb <= 4200 )); then
        suggested_swap="2G"
        suggested_reason="4GB RAM host: 2GB swap prevents sudden memory spikes without consuming excess disk."
    else
        if (( swap_total_mb >= 2000 )); then
            suggested_swap="keep"
            suggested_reason=">=4GB RAM host with active swap: Keeping existing swap is recommended."
        else
            suggested_swap="4G"
            suggested_reason=">=4GB RAM host: 4GB swap provides high concurrency buffer headroom."
        fi
    fi

    if [[ -z "$SWAP_SIZE" ]]; then
        _step 5 5 "Memory Cushion & Swap Allocation"
        _hint "Physical RAM:   ${WHT}${mem_total_mb} MB (${mem_total_gb} GB)${GRY}"
        if (( swap_total_mb > 0 )); then
            _hint "Existing Swap:  ${WHT}${existing_swap_summary}${GRY} — ${swap_used_mb} MB currently in use"
        else
            _hint "Existing Swap:  ${YLW}${existing_swap_summary}${GRY}"
        fi
        _hint "Suggestion:     ${GRN}${suggested_swap}${GRY} (${suggested_reason})"
        _hint "Options:        e.g., '2G', '1G', '4G', 'keep' (keep existing), or '0' (disable swap)"
        _hint "Press Enter to accept suggestion: ${WHT}${suggested_swap}${GRY}"
        echo -e "  ${PRP}${BOLD}│${R}"
        _prompt && get_input && _swap_input="$REPLY"
        _swap_input="${_swap_input// /}"
        if [[ -n "$_swap_input" ]]; then
            SWAP_SIZE="$_swap_input"
        else
            SWAP_SIZE="$suggested_swap"
        fi
        _ok "Swap allocation: ${WHT}${BOLD}${SWAP_SIZE}${R}"
    else
        echo ""
        echo -e "  ${TICK}  ${GRY}Swap size provided via flag:${R}  ${WHT}${BOLD}${SWAP_SIZE}${R}"
    fi

    # Swap Activation Trigger / RAM threshold
    if [[ -z "$SWAP_RAM_THRESHOLD" && -z "$SWAPPINESS" ]]; then
        if [[ "$SWAP_SIZE" != "0" && "$SWAP_SIZE" != "none" ]]; then
            echo -e "  ${PRP}${BOLD}│${R}"
            _hint "Physical RAM Trigger (Kernel Swappiness):"
            _hint "Choose at what % of physical RAM usage swap becomes active:"
            _hint "  • 90%  [Recommended] (swappiness=10) — Maximize fast RAM; swap only when RAM reaches 90%"
            _hint "  • 95%  [Aggressive]  (swappiness=5)  — Maximum RAM utilization; swap purely as emergency OOM fallback"
            _hint "  • 80%  [Conservative](swappiness=20) — Begin gentle paging earlier for memory-constrained instances"
            _hint "Press Enter to accept recommended: ${WHT}90%${GRY} (vm.swappiness=10)"
            echo -e "  ${PRP}${BOLD}│${R}"
            _prompt && get_input && _thresh_input="$REPLY"
            _thresh_input="${_thresh_input// /}"
            _thresh_input="${_thresh_input//%/}"
            if [[ -n "$_thresh_input" ]] && [[ "$_thresh_input" =~ ^[0-9]+$ ]] && (( _thresh_input >= 1 && _thresh_input <= 99 )); then
                SWAP_RAM_THRESHOLD="$_thresh_input"
                SWAPPINESS=$(( 100 - SWAP_RAM_THRESHOLD ))
            else
                SWAP_RAM_THRESHOLD=90
                SWAPPINESS=10
            fi
            _ok "Swap trigger:    ${WHT}${BOLD}Activates at ${SWAP_RAM_THRESHOLD}% RAM usage${R} ${GRY}(vm.swappiness=${SWAPPINESS})${R}"
        else
            SWAP_RAM_THRESHOLD="N/A"
            SWAPPINESS=10
        fi
        _step_end
    else
        # Resolved via flags
        if [[ -n "$SWAPPINESS" ]]; then
            SWAP_RAM_THRESHOLD=$(( 100 - SWAPPINESS ))
        elif [[ -n "$SWAP_RAM_THRESHOLD" ]]; then
            SWAPPINESS=$(( 100 - SWAP_RAM_THRESHOLD ))
        else
            SWAP_RAM_THRESHOLD=90
            SWAPPINESS=10
        fi
        echo -e "  ${TICK}  ${GRY}Swap trigger:${R}  ${WHT}Activates at ${SWAP_RAM_THRESHOLD}% RAM (swappiness=${SWAPPINESS})${R}"
    fi

    # ══════════════════════════════════════════════════════════════════════════
    # CONFIRMATION SUMMARY
    # ══════════════════════════════════════════════════════════════════════════
    echo ""
    echo -e "${PRP}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${PRP}${BOLD}║${R}  ${WHT}${BOLD}%-72s${R}  ${PRP}${BOLD}║${R}\n" \
            "Configuration Summary -- Please Review"
    echo -e "${PRP}${BOLD}  ╠${HR2}╣${R}"
    _conf_row() {
        printf "  ${PRP}${BOLD}║${R}  ${GRY}%-18s${R}  ${WHT}${BOLD}%-52s${R}  ${PRP}${BOLD}║${R}\n" "$1" "$2"
    }
    _conf_row "Username"     "${USERNAME}$( $IS_EXISTING_USER && echo " (existing -- update)" || echo "" )"
    if [[ "$CUSTOM_PASS" == "__KEEP__" ]]; then
        _conf_row "Password"     "keep existing"
    else
        _conf_row "Password"     "$([ -n "$CUSTOM_PASS" ] && echo "custom (hidden)" || echo "will be auto-generated")"
    fi
    _conf_row "Node.js"      "v${NODE_VER}  (via NVM ${NVM_VERSION})"
    _conf_row "NVM"          "$(  $INSTALL_NVM && echo "install" || echo "skip (--no-nvm)")"
    _conf_row "PM2"          "$(  $INSTALL_PM2 && echo "install" || echo "skip (--no-pm2)")"
    _conf_row "Swap Cushion" "$SWAP_SIZE"
    _conf_row "Swap Trigger" "Activates at ${SWAP_RAM_THRESHOLD}% RAM (swappiness=${SWAPPINESS})"
    _conf_row "UFW"          "$(  $GEN_FW      && echo "configure" || echo "skip (--no-fw)")"
    _conf_row "Firewall"     "SSH + $( [[ "$OPEN_NGINX_PORTS" == true ]] && echo "Nginx " ; [[ "$OPEN_EMAIL_PORTS" == true ]] && echo "Email " ; [[ -n "$CUSTOM_PORTS" ]] && echo "Custom " ; echo "")"
    _conf_row "Monitoring"   "$( $SETUP_MON   && echo "Cockpit, Node.js PM2 GUI, Journald (0 MB idle)" || echo "skip (--no-mon)")"
    echo -e "${PRP}${BOLD}  ╚${HR2}╝${R}"
    echo ""

    while true; do
        printf "  ${CYN}${BOLD}❯${R}  ${WHT}Proceed with provisioning?${R}  ${GRY}[${R}${GRN}y${R}${GRY}/n, Enter = yes]${R}  "
        get_input && _confirm="$REPLY"
        case "${_confirm,,}" in
            y|yes) echo -e "\n  ${TICK}  ${GRN}Starting provisioning…${R}\n"; break ;;
            n|no)  echo -e "\n  ${WARN_IC}  ${YLW}Aborted by user. No changes were made.${R}\n"; exit 0 ;;
            "")    echo -e "\n  ${TICK}  ${GRN}Starting provisioning…${R}\n"; break ;;  # Enter = yes
            *)     echo -e "  ${GRY}  Please type ${WHT}y${GRY} to proceed or ${WHT}n${GRY} to cancel.${R}" ;;
        esac
    done

    # Optional: capture passwords for later stages (informational only)
    if [[ "${REQUIRE_USER_PW}" == true ]]; then
        echo -e "  ${GRY}${HR:0:60}${R}"
        echo -e "  ${GRY}  Optional: capture passwords now for confirmation prompts later.${R}"
        echo -e "  ${GRY}  Press Enter to skip any of these — they are not required.${R}"
        echo -e "  ${GRY}${HR:0:60}${R}"
        echo ""
        printf "  ${CYN}${BOLD}❯${R}  ${WHT}Deploy-user password${R}  ${GRY}(hidden, Enter to skip):${R}  "
        get_input -s && USER_PW="$REPLY"
        echo ""
        if [[ -n "$USER_PW" ]]; then
            echo -e "  ${TICK}  Deploy-user password captured."
        else
            echo -e "  ${GRY}  Skipped — will auto-generate or prompt if needed.${R}"
        fi
        echo ""
    fi

    if [[ "${REQUIRE_ROOT_PW}" == true ]]; then
        printf "  ${CYN}${BOLD}❯${R}  ${WHT}Root / sudo password${R}  ${GRY}(hidden, Enter to skip):${R}  "
        get_input -s && ROOT_PW="$REPLY"
        echo ""
        if [[ -n "$ROOT_PW" ]]; then
            echo -e "  ${TICK}  Root password captured."
        else
            echo -e "  ${GRY}  Skipped — you may be prompted later if needed.${R}"
        fi
        echo ""
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  01 — PREFLIGHT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

preflight() {
    section "01" "Preflight Checks"

    [[ $EUID -eq 0 ]] || die "Must run as root: sudo ./init.sh"
    ok "Running as root."

    [[ -f /etc/os-release ]] && { source /etc/os-release; ok "OS: ${PRETTY_NAME:-Linux}"; }

    ok "Username: ${WHT}${BOLD}$USERNAME${R}"

    if [[ -n "$SSH_PUBKEY" ]]; then
        [[ -f "$SSH_PUBKEY" ]] || die "SSH key not found: $SSH_PUBKEY"
        ssh-keygen -l -f "$SSH_PUBKEY" &>/dev/null || die "Invalid SSH public key."
        ok "SSH key validated."
    fi

    check_dependencies

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  DEPENDENCY CHECK + AUTO-INSTALL
#  Checks every tool this script requires and installs missing ones up-front.
#  Called from preflight() before any other work is performed.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

check_dependencies() {
    info "Checking required tools and libraries..."

    # ── Detect package manager ───────────────────────────────────────────────
    local PKG_MGR=""
    if   command -v apt-get &>/dev/null; then PKG_MGR="apt"
    elif command -v dnf     &>/dev/null; then PKG_MGR="dnf"
    elif command -v yum     &>/dev/null; then PKG_MGR="yum"
    elif command -v pacman  &>/dev/null; then PKG_MGR="pacman"
    else die "No supported package manager found (apt/dnf/yum/pacman). Cannot auto-install dependencies."
    fi
    info "Package manager: ${PKG_MGR}"

    # ── Helper: install a package ────────────────────────────────────────────
    _pkg_install() {
        local pkg_apt="$1" pkg_dnf="${2:-$1}" pkg_pac="${3:-$1}"
        case "$PKG_MGR" in
            apt)    DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg_apt"  \
                        2>&1 | grep -E '(Setting up|already installed)' || true ;;
            dnf)    dnf     install -y "$pkg_dnf"  2>&1 | grep -E '(Installed|already)' || true ;;
            yum)    yum     install -y "$pkg_dnf"  2>&1 | grep -E '(Installed|already)' || true ;;
            pacman) pacman  -Sy --noconfirm "$pkg_pac" 2>&1 | grep -E '(installing|up to date)' || true ;;
        esac
    }

    # Run apt-get update once if using apt and packages are likely stale
    if [[ "$PKG_MGR" == "apt" ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null || true
    fi

    # ── 1. bash >= 4 (associative arrays, [[ ]], etc.) ───────────────────────
    local bash_ver="${BASH_VERSINFO[0]:-0}"
    if (( bash_ver < 4 )); then
        die "Bash 4+ required (found bash ${bash_ver}). Install a newer bash first."
    fi
    ok "bash ${BASH_VERSION} — ok"

    # ── 2. curl or wget (NVM download) ───────────────────────────────────────
    if command -v curl &>/dev/null; then
        ok "curl $(curl --version 2>/dev/null | head -1 | awk '{print $2}') — ok"
    elif command -v wget &>/dev/null; then
        ok "wget $(wget --version 2>/dev/null | head -1 | awk '{print $3}') — ok"
    else
        warn "Neither curl nor wget found — installing curl..."
        _pkg_install curl curl curl
        command -v curl &>/dev/null && ok "curl installed." \
            || die "Failed to install curl. Install it manually and re-run."
    fi

    # ── 3. openssl (password hashing, certificate generation) ────────────────
    if command -v openssl &>/dev/null; then
        ok "openssl $(openssl version 2>/dev/null | awk '{print $2}') — ok"
    else
        warn "openssl not found — installing..."
        _pkg_install openssl openssl openssl
        command -v openssl &>/dev/null && ok "openssl installed." \
            || die "Failed to install openssl. Install it manually and re-run."
    fi

    # ── 4. tar (archive extraction utility) ───────────────────────────────────
    if command -v tar &>/dev/null; then
        ok "tar — ok"
    else
        warn "tar not found — installing..."
        _pkg_install tar tar tar
        command -v tar &>/dev/null && ok "tar installed." \
            || die "Failed to install tar. Install it manually and re-run."
    fi

    # ── 5. unzip (general utility) ───────────────────────────────────────────
    if command -v unzip &>/dev/null; then
        ok "unzip — ok"
    else
        warn "unzip not found — installing..."
        _pkg_install unzip unzip unzip
        command -v unzip &>/dev/null && ok "unzip installed." \
            || warn "unzip not available."
    fi

    # ── 6. systemctl / service (service management throughout the script) ─────
    if command -v systemctl &>/dev/null; then
        ok "systemctl — ok"
    elif command -v service &>/dev/null; then
        ok "service (SysV init) — ok"
    else
        warn "No systemctl or service found — service management steps may require manual intervention."
    fi

    # ── 7. cron / crontab (log rotation schedules, acme.sh renewal) ──────────
    local cron_ok=false
    for _cmd in crontab crond cron; do
        command -v "$_cmd" &>/dev/null && { cron_ok=true; break; }
    done
    if $cron_ok; then
        ok "cron — ok"
    else
        warn "cron not found — installing..."
        case "$PKG_MGR" in
            apt)    apt-get install -y cron && systemctl enable cron  2>/dev/null || true ;;
            dnf|yum) ${PKG_MGR} install -y cronie && systemctl enable crond 2>/dev/null || true ;;
            pacman) pacman -Sy --noconfirm cronie && systemctl enable cronie 2>/dev/null || true ;;
        esac
        command -v crontab &>/dev/null && ok "cron installed." \
            || warn "Could not install cron — some scheduled tasks may not run automatically."
    fi

    # ── 8. coreutils: awk, grep, sed, cut, date, tee, sort ───────────────────
    local core_ok=true
    for _tool in awk grep sed cut date tee sort; do
        if ! command -v "$_tool" &>/dev/null; then
            warn "Missing coreutil: ${_tool}"
            core_ok=false
        fi
    done
    if $core_ok; then
        ok "coreutils (awk, grep, sed, cut, date, tee, sort) — ok"
    else
        warn "Some coreutils missing — installing..."
        _pkg_install coreutils coreutils coreutils
    fi

    # ── 9. mktemp (used for temp files throughout the script) ────────────────
    if command -v mktemp &>/dev/null; then
        ok "mktemp — ok"
    else
        warn "mktemp not found — installing util-linux..."
        _pkg_install util-linux util-linux util-linux
        command -v mktemp &>/dev/null && ok "mktemp installed." \
            || warn "mktemp not available — some temp-file operations may fail."
    fi

    # ── 10. jq (JSON parsing — used in monitoring config) ────────────────────
    if command -v jq &>/dev/null; then
        ok "jq $(jq --version 2>/dev/null) — ok"
    else
        info "jq not found — installing (used for JSON config processing)..."
        _pkg_install jq jq jq
        command -v jq &>/dev/null && ok "jq installed." \
            || warn "jq not available — JSON config steps will use fallback methods."
    fi

    # ── 11. logrotate (PM2 log rotation — step 13) ───────────────────────────
    if command -v logrotate &>/dev/null; then
        ok "logrotate — ok"
    else
        info "logrotate not found — installing (required for log rotation)..."
        _pkg_install logrotate logrotate logrotate
        command -v logrotate &>/dev/null && ok "logrotate installed." \
            || warn "logrotate not available — log rotation will rely on PM2 module only."
    fi

    # ── 12. fail2ban (SSH brute-force protection — step 11) ──────────────────
    if command -v fail2ban-server &>/dev/null; then
        ok "fail2ban — ok"
    else
        info "fail2ban not found — installing (SSH brute-force protection)..."
        _pkg_install fail2ban fail2ban fail2ban
        command -v fail2ban-server &>/dev/null && ok "fail2ban installed." \
            || warn "fail2ban not available — SSH brute-force protection will be skipped."
    fi

    # ── 13. ufw (firewall — step 12) ─────────────────────────────────────────
    if command -v ufw &>/dev/null; then
        ok "ufw — ok (firewall ready)"
    else
        info "ufw not found — installing (firewall management)..."
        _pkg_install ufw ufw ufw
        command -v ufw &>/dev/null && ok "ufw installed." \
            || warn "ufw not available — firewall step will be skipped."
    fi

    # ── 14. Cockpit & Monitoring Prerequisites ───────────────────────────────
    if $SETUP_MON; then
        info "Checking monitoring prerequisites (Cockpit Web Console)..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y \
            apt-transport-https ca-certificates curl gnupg tar 2>/dev/null | \
            grep -E '(Setting up|already installed)' || true
        ok "Monitoring prerequisites satisfied."
    else
        info "Monitoring prerequisites — skipped (--no-mon)"
    fi

    ok "Dependency check complete — all required tools are available."
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  02 — OS USER
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

create_user() {
    section "02" "Configuring OS User"

    if id "$USERNAME" &>/dev/null; then
        ok "User '$USERNAME' already exists — preserving account and existing files."
        if [[ -n "$CUSTOM_PASS" && "$CUSTOM_PASS" != "__KEEP__" ]]; then
            PASSWORD="$CUSTOM_PASS"
            local hashed
            hashed=$(openssl passwd -6 "$PASSWORD") || die "Failed to hash password (openssl error)."
            usermod -p "$hashed" "$USERNAME"
            ok "Password updated for '$USERNAME'."
        else
            ok "Existing password for '$USERNAME' retained."
        fi
        usermod -s /bin/bash "$USERNAME" 2>/dev/null || true
        mkdir -p "/home/$USERNAME"
        chown "$USERNAME:$USERNAME" "/home/$USERNAME"
        chmod 755 "/home/$USERNAME"
    else
        if [[ -n "$CUSTOM_PASS" && "$CUSTOM_PASS" != "__KEEP__" ]]; then
            PASSWORD="$CUSTOM_PASS"
            ok "Using custom password."
        else
            PASSWORD=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9!@#_+-' | head -c "$PASS_LEN")
            ok "Password auto-generated (${PASS_LEN} chars)."
        fi

        getent group "$USERNAME" &>/dev/null || run "groupadd '$USERNAME'"

        local cmd="useradd --gid '$USERNAME' --shell /bin/bash --comment 'Deploy $USERNAME' --create-home --home-dir '/home/$USERNAME' '$USERNAME'"
        run "$cmd"
        ok "User '$USERNAME' created → /home/$USERNAME"

        local hashed
        hashed=$(openssl passwd -6 "$PASSWORD") || die "Failed to hash password (openssl error)."
        [[ -n "$hashed" ]] || die "Password hash is empty — check openssl installation."
        usermod -p "$hashed" "$USERNAME"
        ok "Password set."
    fi

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  03 — SSH (PASSWORD + KEY)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_ssh() {
    section "03" "SSH — Password + Key Auth"

    mkdir -p "/home/$USERNAME/.ssh"
    chmod 700 "/home/$USERNAME/.ssh"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
    ok ".ssh directory ready (mode 700)."

    if [[ -n "$SSH_PUBKEY" ]]; then
        local auth_keys="/home/$USERNAME/.ssh/authorized_keys"
        cat "$SSH_PUBKEY" >> "$auth_keys"
        chmod 600 "$auth_keys"
        chown "$USERNAME:$USERNAME" "$auth_keys"
        ok "SSH public key installed."
    fi

    local sshd_conf="/etc/ssh/sshd_config"
    if [[ -f "$sshd_conf" ]]; then
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

        # Additional SSH hardening: drop brute-force attempts and block empty passwords
        for param in "MaxAuthTries 4" "PermitEmptyPasswords no" "X11Forwarding no"; do
            local key="${param%% *}"
            if grep -qiE "^\s*${key}" "$sshd_conf" 2>/dev/null; then
                sed -i "s/^\s*${key}.*/${param}/" "$sshd_conf"
            else
                echo "${param}" >> "$sshd_conf"
            fi
        done

        systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
        ok "sshd: PasswordAuthentication=yes, PermitRootLogin=no, MaxAuthTries=4, X11Forwarding=no."
    fi

    ok "SSH: password + key login ENABLED."
    warn "Root SSH login: BLOCKED — login as user, then switch to root."
    info "  1. ssh $USERNAME@<server-ip>"
    info "  2. sudo -i               ← become root (enter ROOT password)"
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

    cat > "$f" <<SUDOERS
# Sudoers for: $USERNAME
# Generated: $(date '+%Y-%m-%d %H:%M:%S') — init.sh v${SCRIPT_VERSION}

# sudo session active for ${SUDO_TIMEOUT} minutes after password entry
Defaults:$USERNAME  timestamp_timeout=${SUDO_TIMEOUT}

# Require root's password (not the invoking user's) for sudo authentication
Defaults:$USERNAME  rootpw

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

    ok "Sudoers written."
    ok "Full root:                 sudo -i  or  sudo su -        (root password required)"
    ok "pm2 service:               sudo systemctl restart pm2-$USERNAME  (NO password)"
    ok "apt install:               sudo apt install <pkg>         (NO password)"

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  05 — SHELL PROFILE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_shell() {
    section "05" "Shell Profile — Aliases + NVM + PM2"

    local profile="/home/$USERNAME/.deploy_env"

    cat > "$profile" << 'PROFILE'
# Deploy environment — init.sh
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

# Make pm2-start-logs available globally
[[ -f "$HOME/.pm2/pm2-start-logs.sh" ]] && export PATH="$HOME/.pm2:$PATH"

# ── PM2 logging functions ────────────────────────────────────────
# Detailed log viewing with timestamps and filtering
pm2_logs_live() {
    pm2 logs 2>/dev/null || echo "PM2 not running or no apps started"
}

pm2_logs_app() {
    local app="${1:-}"
    if [[ -z "$app" ]]; then
        echo "Usage: pm2_logs_app <app-name>"
        echo "Available apps:"
        pm2 list | grep "│" | grep -v "id│name" || echo "  (no apps running)"
        return
    fi
    pm2 logs "$app" --lines 100
}

pm2_logs_errors() {
    local app="${1:-}"
    if [[ -z "$app" ]]; then
        echo "Recent errors from all apps:"
        grep -r "ERROR\|Error\|error" ~/.pm2/logs/*.log 2>/dev/null | tail -50 || echo "  (no errors found)"
    else
        echo "Recent errors from $app:"
        grep "ERROR\|Error\|error" ~/.pm2/logs/"${app}"*.log 2>/dev/null | tail -50 || echo "  (no errors found)"
    fi
}

pm2_log_size() {
    echo "PM2 Log File Sizes:"
    du -sh ~/.pm2/logs/* 2>/dev/null | sort -h || echo "  (no logs found)"
    echo ""
    echo "Total PM2 logs directory:"
    du -sh ~/.pm2/logs/ 2>/dev/null || echo "  (empty)"
}

pm2_clear_logs() {
    local app="${1:-all}"
    if [[ "$app" == "all" ]]; then
        rm -f ~/.pm2/logs/*.log ~/.pm2/logs/*.gz
        echo "✓ All PM2 logs cleared"
        pm2 flush
    else
        rm -f ~/.pm2/logs/"${app}"*.log ~/.pm2/logs/"${app}"*.gz
        echo "✓ Logs cleared for: $app"
    fi
}

# ── PM2 AUTO-LOGGING wrapper ─────────────────────────────────────
# Start app with automatic detailed logging
pm2_start_auto() {
    if [[ $# -eq 0 ]]; then
        echo "🚀 PM2 Auto-Logging Starter"
        echo ""
        echo "Usage: pm2_start_auto <app.js> [options]"
        echo ""
        echo "Examples:"
        echo "  pm2_start_auto app.js                          # Auto: app-out/error.log"
        echo "  pm2_start_auto app.js --name myapp             # Auto: myapp-out/error.log"
        echo "  pm2_start_auto app.js --name api -- --port 3000"
        echo ""
        echo "Logs saved to: ~/.pm2/logs/<app-name>-{out,error}.log"
        echo "View logs:"
        echo "  plog_app <app-name>"
        echo "  plog_errors <app-name>"
        return
    fi
    
    local script="$1"
    shift
    
    # Extract app name from args or script
    local app_name
    for i in "$@"; do
        if [[ "$prev" == "--name" ]]; then
            app_name="$i"
            break
        fi
        prev="$i"
    done
    
    app_name="${app_name:-$(basename "$script" | sed 's/\.[^.]*$//')}"
    local logs_dir="$HOME/.pm2/logs"
    mkdir -p "$logs_dir"
    
    # Start with automatic logging
    pm2 start "$script" \
        --name "$app_name" \
        --output "$logs_dir/${app_name}-out.log" \
        --error "$logs_dir/${app_name}-error.log" \
        --log-date-format 'YYYY-MM-DD HH:mm:ss Z' \
        "$@" 2>&1
    
    echo ""
    echo "✓ Started: $app_name"
    echo "  Logs: ~/.pm2/logs/${app_name}-{out,error}.log"
    echo ""
}

# ── System Journald & PM2 log helpers ─────────────────────────────
# Fast native log inspection without external log shipper overhead
jlogs_system() {
    local limit="${1:-50}"
    journalctl -n "$limit" --no-pager
}

jlogs_errors() {
    local limit="${1:-50}"
    journalctl -p err..emerg -n "$limit" -xb --no-pager
}

jlogs_nginx() {
    local limit="${1:-50}"
    journalctl -u nginx -n "$limit" --no-pager
}

jlogs_pm2() {
    local limit="${1:-50}"
    journalctl -u "pm2-${USER}" -n "$limit" --no-pager 2>/dev/null || pm2 logs --lines "$limit"
}

cockpit_info() {
    if [[ -f /etc/production-server.conf ]]; then source /etc/production-server.conf; fi
    local u="${DEPLOY_USER:-$USER}"
    echo ""
    echo "=== Cockpit Web Console (Host & Node.js PM2) ==="
    echo "Access from your local computer terminal:"
    echo "    ssh -L 9090:127.0.0.1:9090 ${u}@<server-ip>"
    echo "Then open in your browser: https://localhost:9090"
    echo ""
}

# ── Log & Monitoring shortcuts ────────────────────────────────────
alias sys_logs='jlogs_system'                 # View system journal logs
alias sys_errors='jlogs_errors'               # View system errors only
alias nginx_logs='jlogs_nginx'                # View Nginx access & error logs
alias pm2_jlogs='jlogs_pm2'                   # View PM2 systemd journal logs
alias cockpit_status='cockpit_info'           # Show Cockpit access info
alias tunnel='mon_tunnel'                     # Show SSH tunnel command for Cockpit
alias pstatus='pm2 status'
alias prestart='pm2 restart all'
alias pmonit='pm2 monit'
alias psave='pm2 save'
alias plog_size='pm2_log_size'
alias plog_errors='pm2_logs_errors'
alias plog_app='pm2_logs_app'
alias plog_clear='pm2_clear_logs'
alias pstart='pm2_start_auto'


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

    ok "Shell profile written. Aliases: pull, gs, gl, logs, pstatus, psave, status."

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  06 — GIT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

install_git() {
    section "06" "Git"

    if command -v git &>/dev/null; then
        ok "Git already installed: $(git --version)"
    else
        apt-get install -y git 2>&1 | tail -3 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        ok "Git installed."
    fi

    info "Clone a project:  git clone https://github.com/you/repo.git"
    info "Private repo:     git clone https://<token>@github.com/you/repo.git"

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  07 — NVM + NODE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

install_node() {
    $INSTALL_NVM || { section "07" "NVM + Node.js"; warn "Skipped."; section_end; return; }

    section "07" "NVM + Node.js ${NODE_VER}"

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

    ok "Node.js v${NODE_VER} installed via NVM."

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  08 — PM2
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

install_pm2() {
    $INSTALL_PM2 || { section "08" "PM2"; warn "Skipped."; section_end; return; }
    $INSTALL_NVM || { section "08" "PM2"; warn "Skipped — NVM not installed."; section_end; return; }

    section "08" "PM2 — Bulletproof Startup"

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

    section_end
}


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  09 — MONITORING (Cockpit Web Console + Node.js PM2 GUI — 0 MB Idle RAM)
#
#  Pure Zero-Idle-RAM Architecture:
#    A. Decommission Legacy & Redundant — purges Prometheus, Grafana, Loki, ClickHouse, node_exporter, VictoriaMetrics
#    B. Compact journald          — caps disk storage to 150MB, RAM buffer to 30MB
#    C. Cockpit Web Console       — web-based system management & logs (port 9090, 0 MB idle)
#    D. PM2 Admin Bridge & GUI    — native Cockpit extension for PM2 Node.js apps (0 MB idle)
#    E. Health checks & CLI       — server_status CLI overview & mon_tunnel
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_monitoring() {
    $SETUP_MON || { section "09" "Monitoring"; warn "Skipped (--no-mon)."; section_end; return; }

    section "09" "Monitoring — Cockpit Web Console + Node.js PM2 GUI (0 MB Idle RAM)"

    # ── A. Decommission Legacy & Redundant Monitoring Services ────────────────
    local legacy_services=("grafana-server" "prometheus" "loki" "promtail" "clickhouse-server" "node_exporter" "victoriametrics")
    local legacy_found=false
    for svc in "${legacy_services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null || systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            info "Stopping legacy/redundant monitoring service: $svc..."
            systemctl disable --now "$svc" 2>/dev/null || true
            legacy_found=true
        fi
    done
    # Remove obsolete systemd units, binaries, and cron scripts
    rm -f /etc/systemd/system/prometheus.service /etc/systemd/system/loki.service /etc/systemd/system/promtail.service /etc/systemd/system/node_exporter.service /etc/systemd/system/victoriametrics.service
    rm -f /usr/local/bin/node_exporter /usr/local/bin/victoria-metrics /tmp/victoria-metrics.tar.gz
    rm -f /etc/cron.d/pm2-clickhouse /usr/local/bin/pm2-logs-to-clickhouse.sh
    # Reclaim disk space from legacy databases if present
    rm -rf /var/lib/prometheus /var/lib/loki /etc/prometheus /etc/loki /etc/promtail /etc/grafana /var/lib/victoria-metrics /etc/victoriametrics 2>/dev/null || true
    if id victoriametrics &>/dev/null; then userdel victoriametrics 2>/dev/null || true; fi
    if $legacy_found; then
        systemctl daemon-reload
        ok "Legacy & redundant services decommissioned (reclaimed ~1.6GB+ RAM)."
    fi

    # ── B. Compact systemd-journald — cap RAM buffer & disk storage ──────────
    info "Configuring compact systemd-journald (150MB disk cap, 30MB RAM buffer)..."
    mkdir -p /etc/systemd/journald.conf.d
    cat > /etc/systemd/journald.conf.d/00-compact.conf <<'JOURNALDCONF'
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=150M
SystemMaxFileSize=25M
RuntimeMaxUse=30M
MaxRetentionSec=1month
JOURNALDCONF
    systemctl restart systemd-journald 2>/dev/null || true
    ok "systemd-journald tuned: compressed, 150MB disk limit, 30MB RAM cap."

    # ── C. Cockpit — Web-based System Management & Real-time Monitoring ───────
    info "Installing Cockpit web console (ultra-lean profile: core system & logs only)..."
    DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        cockpit cockpit-system 2>&1 | \
        tail -5 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true

    # Disable heavy auxiliary daemons if previously pulled (packagekitd, udisks2)
    for aux in packagekit udisks2; do
        if systemctl is-active --quiet "$aux" 2>/dev/null || systemctl is-enabled --quiet "$aux" 2>/dev/null; then
            systemctl disable --now "$aux" 2>/dev/null || true
        fi
    done

    mkdir -p /etc/cockpit
    local _server_fqdn; _server_fqdn=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "")
    local _fqdn_origins=""
    if [[ -n "$_server_fqdn" && "$_server_fqdn" != "localhost" ]]; then
        _fqdn_origins="https://${_server_fqdn} wss://${_server_fqdn}"
    fi

    cat > /etc/cockpit/cockpit.conf <<COCKPITCONF
[WebService]
Origins = https://localhost:9090 http://localhost:9090 https://127.0.0.1:9090 http://127.0.0.1:9090 https://sv1.lunecode.com wss://sv1.lunecode.com https://*.lunecode.com wss://*.lunecode.com ${_fqdn_origins} https://* wss://* http://* ws://*
ProtocolHeader = X-Forwarded-Proto
ForwardedForHeader = X-Forwarded-For
AllowUnencrypted = true
COCKPITCONF

    # Helper script to dynamically add reverse proxy domains to Cockpit
    cat > /usr/local/bin/cockpit_add_origin <<'ORIGIN_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 1 ]]; then
    echo "Usage: sudo cockpit_add_origin <domain>"
    echo "Example: sudo cockpit_add_origin sv1.lunecode.com"
    exit 1
fi
_DOM="$1"
mkdir -p /etc/cockpit
if [[ ! -f /etc/cockpit/cockpit.conf ]]; then
    cat > /etc/cockpit/cockpit.conf <<EOF
[WebService]
Origins = https://localhost:9090 http://localhost:9090 https://127.0.0.1:9090 http://127.0.0.1:9090 https://${_DOM} wss://${_DOM} https://* wss://*
ProtocolHeader = X-Forwarded-Proto
ForwardedForHeader = X-Forwarded-For
AllowUnencrypted = true
EOF
else
    if grep -q "^Origins" /etc/cockpit/cockpit.conf; then
        if ! grep -q "${_DOM}" /etc/cockpit/cockpit.conf; then
            sed -i "/^Origins/ s|$| https://${_DOM} wss://${_DOM}|" /etc/cockpit/cockpit.conf
        fi
    else
        sed -i "/\[WebService\]/a Origins = https://localhost:9090 https://${_DOM} wss://${_DOM} https://* wss://*" /etc/cockpit/cockpit.conf
    fi
    if ! grep -q "^ProtocolHeader" /etc/cockpit/cockpit.conf; then
        sed -i "/\[WebService\]/a ProtocolHeader = X-Forwarded-Proto" /etc/cockpit/cockpit.conf
    fi
    if ! grep -q "^AllowUnencrypted" /etc/cockpit/cockpit.conf; then
        sed -i "/\[WebService\]/a AllowUnencrypted = true" /etc/cockpit/cockpit.conf
    fi
fi
systemctl restart cockpit.socket 2>/dev/null || true
echo "✔ Added ${_DOM} to /etc/cockpit/cockpit.conf and restarted cockpit.socket."
ORIGIN_SCRIPT
    chmod 755 /usr/local/bin/cockpit_add_origin 2>/dev/null || true

    # Bind Cockpit socket strictly to localhost (127.0.0.1:9090)
    mkdir -p /etc/systemd/system/cockpit.socket.d
    cat > /etc/systemd/system/cockpit.socket.d/listen.conf <<'COCKPITSOCK'
[Socket]
ListenStream=
ListenStream=127.0.0.1:9090
COCKPITSOCK

    systemctl daemon-reload
    systemctl enable --now cockpit.socket 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
    ok "Cockpit web console enabled on 127.0.0.1:9090 (0 MB idle RAM via socket activation)."

    # ── D. PM2 Bridge & Native Cockpit Extension (Node.js & PM2 GUI) ─────────
    info "Installing Cockpit Node.js (PM2) GUI extension..."

    # 1. System-wide CLI bridge between Cockpit and PM2
    cat > /usr/local/bin/pm2-admin <<'PM2ADMIN'
#!/usr/bin/env bash
# /usr/local/bin/pm2-admin — System-wide bridge for Cockpit & CLI PM2 operations
set -eo pipefail

if [[ -f /etc/production-server.conf ]]; then
    source /etc/production-server.conf
fi
DEPLOY_USER="${DEPLOY_USER:-$(id -un 1000 2>/dev/null || echo root)}"

run_pm2() {
    su - "$DEPLOY_USER" -s /bin/bash -c "export NVM_DIR=\"\$HOME/.nvm\"; [ -s \"\$NVM_DIR/nvm.sh\" ] && source \"\$NVM_DIR/nvm.sh\"; pm2 $*"
}

case "${1:-}" in
    json|list-json)
        run_pm2 jlist 2>/dev/null || echo "[]"
        ;;
    restart)
        run_pm2 restart "${2:-all}"
        ;;
    stop)
        run_pm2 stop "${2:-all}"
        ;;
    start)
        run_pm2 start "${2:-all}"
        ;;
    save)
        run_pm2 save
        ;;
    logs)
        app="${2:-all}"
        lines="${3:-100}"
        run_pm2 logs "$app" --lines "$lines" --nostream
        ;;
    *)
        run_pm2 "$@"
        ;;
esac
PM2ADMIN
    chmod 755 /usr/local/bin/pm2-admin

    # 2. Register Cockpit package
    mkdir -p /usr/share/cockpit/node-pm2

    cat > /usr/share/cockpit/node-pm2/manifest.json <<'COCKPITMANIFEST'
{
  "version": 0,
  "tools": {
    "node-pm2": {
      "label": "Node.js (PM2)",
      "path": "index.html",
      "order": 15
    }
  }
}
COCKPITMANIFEST

    # 3. Cockpit Node.js PM2 HTML/JS Dashboard
    cat > /usr/share/cockpit/node-pm2/index.html <<'COCKPITHMTL'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Node.js (PM2) - Cockpit</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <script src="../base1/cockpit.js"></script>
  <style>
    :root {
      --bg-color: #0f1216;
      --card-bg: #1b1e24;
      --card-border: #2c323b;
      --text-main: #f0f3f6;
      --text-muted: #8b949e;
      --primary: #388bfd;
      --primary-hover: #1f6feb;
      --success: #238636;
      --success-text: #3fb950;
      --danger: #da3633;
      --danger-text: #f85149;
      --font-mono: ui-monospace, SFMono-Regular, SF Mono, Menlo, Consolas, monospace;
    }
    body {
      background-color: var(--bg-color);
      color: var(--text-main);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
      margin: 0;
      padding: 24px;
    }
    .header-bar {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 24px;
      flex-wrap: wrap;
      gap: 12px;
    }
    .header-bar h1 {
      margin: 0;
      font-size: 22px;
      font-weight: 600;
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .header-bar .subtitle {
      color: var(--text-muted);
      font-size: 13px;
      margin-top: 4px;
    }
    .header-actions {
      display: flex;
      gap: 8px;
      align-items: center;
    }
    .btn {
      background: var(--card-bg);
      color: var(--text-main);
      border: 1px solid var(--card-border);
      padding: 7px 14px;
      border-radius: 6px;
      font-size: 13px;
      font-weight: 500;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      transition: all 0.15s ease;
    }
    .btn:hover {
      background: #282e38;
      border-color: #444c56;
    }
    .btn-primary {
      background: var(--primary);
      border-color: var(--primary-hover);
      color: #fff;
    }
    .btn-primary:hover {
      background: var(--primary-hover);
    }
    .btn-danger {
      background: rgba(218, 54, 51, 0.15);
      border-color: var(--danger);
      color: var(--danger-text);
    }
    .btn-danger:hover {
      background: var(--danger);
      color: #fff;
    }
    .btn-sm {
      padding: 4px 8px;
      font-size: 12px;
    }
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 16px;
      margin-bottom: 24px;
    }
    .stat-card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 8px;
      padding: 16px;
    }
    .stat-title {
      font-size: 12px;
      color: var(--text-muted);
      text-transform: uppercase;
      letter-spacing: 0.5px;
      font-weight: 600;
      margin-bottom: 8px;
    }
    .stat-val {
      font-size: 24px;
      font-weight: 700;
      color: var(--text-main);
    }
    .table-container {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 8px;
      overflow: hidden;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      text-align: left;
      font-size: 13px;
    }
    th {
      background: rgba(255, 255, 255, 0.03);
      padding: 12px 16px;
      color: var(--text-muted);
      font-weight: 600;
      border-bottom: 1px solid var(--card-border);
    }
    td {
      padding: 14px 16px;
      border-bottom: 1px solid var(--card-border);
      vertical-align: middle;
    }
    tr:last-child td {
      border-bottom: none;
    }
    tr:hover td {
      background: rgba(255, 255, 255, 0.02);
    }
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 3px 8px;
      border-radius: 12px;
      font-size: 12px;
      font-weight: 600;
    }
    .badge-online {
      background: rgba(35, 134, 54, 0.2);
      color: var(--success-text);
      border: 1px solid rgba(35, 134, 54, 0.4);
    }
    .badge-stopped {
      background: rgba(139, 148, 158, 0.15);
      color: var(--text-muted);
      border: 1px solid rgba(139, 148, 158, 0.3);
    }
    .badge-errored {
      background: rgba(218, 54, 51, 0.2);
      color: var(--danger-text);
      border: 1px solid rgba(218, 54, 51, 0.4);
    }
    .dot {
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background: currentColor;
    }
    .app-name {
      font-weight: 600;
      font-size: 14px;
      color: #fff;
    }
    .app-id {
      color: var(--text-muted);
      font-size: 12px;
      margin-left: 6px;
    }
    .log-modal {
      display: none;
      position: fixed;
      inset: 0;
      background: rgba(0, 0, 0, 0.75);
      backdrop-filter: blur(2px);
      z-index: 1000;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .log-box {
      background: #090b0e;
      border: 1px solid var(--card-border);
      border-radius: 10px;
      width: 100%;
      max-width: 900px;
      max-height: 85vh;
      display: flex;
      flex-direction: column;
      box-shadow: 0 16px 36px rgba(0, 0, 0, 0.6);
    }
    .log-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 12px 18px;
      border-bottom: 1px solid var(--card-border);
    }
    .log-content {
      padding: 16px;
      overflow-y: auto;
      font-family: var(--font-mono);
      font-size: 12px;
      line-height: 1.5;
      color: #c9d1d9;
      white-space: pre-wrap;
      word-break: break-all;
      flex: 1;
    }
    .toast {
      position: fixed;
      bottom: 24px;
      right: 24px;
      background: #1b1e24;
      border: 1px solid var(--primary);
      color: #fff;
      padding: 10px 18px;
      border-radius: 6px;
      font-size: 13px;
      display: none;
      box-shadow: 0 8px 24px rgba(0,0,0,0.5);
      z-index: 2000;
    }
    .empty-state {
      padding: 48px 20px;
      text-align: center;
      color: var(--text-muted);
    }
  </style>
</head>
<body>
  <div class="header-bar">
    <div>
      <h1>⚡ Node.js Applications (PM2)</h1>
      <div class="subtitle">Live status, resource metrics, service control & logs (0 MB Idle RAM)</div>
    </div>
    <div class="header-actions">
      <label style="font-size:12px; color:var(--text-muted); display:inline-flex; align-items:center; gap:6px; cursor:pointer;">
        <input type="checkbox" id="auto-refresh-toggle" checked> Auto-refresh (3s)
      </label>
      <button class="btn" onclick="savePm2List()">💾 Save State</button>
      <button class="btn" onclick="restartAllApps()">🔄 Restart All</button>
      <button class="btn btn-primary" onclick="loadPm2Data()">↻ Refresh</button>
    </div>
  </div>

  <div class="stats-grid">
    <div class="stat-card">
      <div class="stat-title">Active Applications</div>
      <div class="stat-val" id="stat-apps">-</div>
    </div>
    <div class="stat-card">
      <div class="stat-title">Total Node Memory</div>
      <div class="stat-val" id="stat-memory">-</div>
    </div>
    <div class="stat-card">
      <div class="stat-title">Total CPU Usage</div>
      <div class="stat-val" id="stat-cpu">-</div>
    </div>
    <div class="stat-card">
      <div class="stat-title">Total Restarts</div>
      <div class="stat-val" id="stat-restarts">-</div>
    </div>
  </div>

  <div class="table-container">
    <table>
      <thead>
        <tr>
          <th>App Name</th>
          <th>Status</th>
          <th>PID</th>
          <th>Memory</th>
          <th>CPU</th>
          <th>Uptime</th>
          <th>Restarts</th>
          <th style="text-align:right;">Actions</th>
        </tr>
      </thead>
      <tbody id="apps-tbody">
        <tr><td colspan="8" class="empty-state">Loading application status...</td></tr>
      </tbody>
    </table>
  </div>

  <!-- Log Viewer Modal -->
  <div class="log-modal" id="log-modal">
    <div class="log-box">
      <div class="log-header">
        <strong id="log-title">Application Logs</strong>
        <div style="display:flex; gap:8px;">
          <button class="btn btn-sm" onclick="fetchLogs(currentApp)">Refresh Logs</button>
          <button class="btn btn-sm" onclick="closeLogModal()">Close</button>
        </div>
      </div>
      <div class="log-content" id="log-body">Loading logs...</div>
    </div>
  </div>

  <div class="toast" id="toast-msg"></div>

  <script>
    let currentApp = null;
    let refreshTimer = null;

    function showToast(msg) {
      const t = document.getElementById('toast-msg');
      t.innerText = msg;
      t.style.display = 'block';
      setTimeout(() => { t.style.display = 'none'; }, 3000);
    }

    function formatUptime(ms) {
      if (!ms) return '0s';
      const sec = Math.floor((Date.now() - ms) / 1000);
      if (sec < 60) return sec + 's';
      const min = Math.floor(sec / 60);
      if (min < 60) return min + 'm';
      const hrs = Math.floor(min / 60);
      if (hrs < 24) return hrs + 'h ' + (min % 60) + 'm';
      const days = Math.floor(hrs / 24);
      return days + 'd ' + (hrs % 24) + 'h';
    }

    function loadPm2Data() {
      if (typeof cockpit === 'undefined') return;

      cockpit.spawn(["/usr/local/bin/pm2-admin", "json"])
        .then(data => {
          try {
            const apps = JSON.parse(data || '[]');
            renderApps(apps);
          } catch(e) {
            renderEmptyState("Unable to parse PM2 output: " + e.message);
          }
        })
        .catch(err => {
          renderEmptyState("Error querying PM2: " + (err.message || err));
        });
    }

    function renderApps(apps) {
      const tbody = document.getElementById('apps-tbody');
      if (!apps || apps.length === 0) {
        tbody.innerHTML = '<tr><td colspan="8" class="empty-state">No Node.js apps currently running in PM2.<br><span style="font-size:12px; color:var(--text-muted)">Start an app on the server with: pm2 start app.js --name myapp</span></td></tr>';
        document.getElementById('stat-apps').innerText = '0';
        document.getElementById('stat-memory').innerText = '0 MB';
        document.getElementById('stat-cpu').innerText = '0.0 %';
        document.getElementById('stat-restarts').innerText = '0';
        return;
      }

      let totalMem = 0;
      let totalCpu = 0;
      let onlineCount = 0;
      let totalRestarts = 0;

      let html = '';
      apps.forEach(app => {
        const status = app.pm2_env ? app.pm2_env.status : 'stopped';
        const memBytes = (app.monit && app.monit.memory) || 0;
        const memMb = (memBytes / 1024 / 1024).toFixed(1);
        const cpu = (app.monit && app.monit.cpu) || 0;
        const restarts = (app.pm2_env && app.pm2_env.restart_time) || 0;
        const uptime = (app.pm2_env && app.pm2_env.pm_uptime) ? formatUptime(app.pm2_env.pm_uptime) : '-';

        totalMem += parseFloat(memMb);
        totalCpu += parseFloat(cpu);
        totalRestarts += restarts;
        if (status === 'online') onlineCount++;

        let badgeClass = 'badge-stopped';
        if (status === 'online') badgeClass = 'badge-online';
        if (status === 'errored') badgeClass = 'badge-errored';

        html += `
          <tr>
            <td>
              <span class="app-name">${app.name}</span>
              <span class="app-id">#${app.pm_id}</span>
            </td>
            <td><span class="badge ${badgeClass}"><span class="dot"></span>${status}</span></td>
            <td style="font-family:var(--font-mono)">${app.pid || '-'}</td>
            <td><strong>${memMb}</strong> MB</td>
            <td>${cpu} %</td>
            <td>${uptime}</td>
            <td style="${restarts > 5 ? 'color:var(--danger-text); font-weight:bold;' : ''}">${restarts}</td>
            <td style="text-align:right;">
              <button class="btn btn-sm" onclick="appAction('restart', '${app.name}')" title="Restart App">🔄</button>
              ${status === 'online'
                ? `<button class="btn btn-sm btn-danger" onclick="appAction('stop', '${app.name}')" title="Stop App">⏹</button>`
                : `<button class="btn btn-sm btn-primary" onclick="appAction('start', '${app.name}')" title="Start App">▶</button>`
              }
              <button class="btn btn-sm" onclick="openLogModal('${app.name}')" title="View Logs">📋 Logs</button>
            </td>
          </tr>
        `;
      });

      tbody.innerHTML = html;
      document.getElementById('stat-apps').innerText = `${onlineCount} / ${apps.length} Online`;
      document.getElementById('stat-memory').innerText = totalMem.toFixed(1) + ' MB';
      document.getElementById('stat-cpu').innerText = totalCpu.toFixed(1) + ' %';
      document.getElementById('stat-restarts').innerText = totalRestarts;
    }

    function renderEmptyState(msg) {
      document.getElementById('apps-tbody').innerHTML = `<tr><td colspan="8" class="empty-state">${msg}</td></tr>`;
    }

    function appAction(action, appName) {
      showToast(`${action.toUpperCase()} ${appName}...`);
      if (typeof cockpit !== 'undefined') {
        cockpit.spawn(["/usr/local/bin/pm2-admin", action, appName])
          .then(() => {
            showToast(`${appName} ${action}ed successfully.`);
            setTimeout(loadPm2Data, 800);
          })
          .catch(err => {
            showToast(`Failed to ${action} ${appName}: ` + (err.message || err));
          });
      }
    }

    function restartAllApps() {
      if (!confirm("Are you sure you want to restart ALL Node.js PM2 apps?")) return;
      showToast("Restarting all apps...");
      if (typeof cockpit !== 'undefined') {
        cockpit.spawn(["/usr/local/bin/pm2-admin", "restart", "all"])
          .then(() => {
            showToast("All apps restarted.");
            setTimeout(loadPm2Data, 1000);
          })
          .catch(err => showToast("Error: " + err));
      }
    }

    function savePm2List() {
      showToast("Saving PM2 process list...");
      if (typeof cockpit !== 'undefined') {
        cockpit.spawn(["/usr/local/bin/pm2-admin", "save"])
          .then(() => showToast("PM2 state saved successfully (persists on reboot)."))
          .catch(err => showToast("Error saving PM2 state: " + err));
      }
    }

    function openLogModal(appName) {
      currentApp = appName;
      document.getElementById('log-title').innerText = `Logs for: ${appName} (last 100 lines)`;
      document.getElementById('log-body').innerText = "Fetching logs...";
      document.getElementById('log-modal').style.display = 'flex';
      fetchLogs(appName);
    }

    function fetchLogs(appName) {
      if (typeof cockpit !== 'undefined') {
        cockpit.spawn(["/usr/local/bin/pm2-admin", "logs", appName, "100"])
          .then(out => {
            document.getElementById('log-body').innerText = out || 'No logs recorded yet.';
            const b = document.getElementById('log-body');
            b.scrollTop = b.scrollHeight;
          })
          .catch(err => {
            document.getElementById('log-body').innerText = "Error loading logs: " + (err.message || err);
          });
      }
    }

    function closeLogModal() {
      document.getElementById('log-modal').style.display = 'none';
      currentApp = null;
    }

    document.getElementById('auto-refresh-toggle').addEventListener('change', (e) => {
      if (e.target.checked) {
        refreshTimer = setInterval(loadPm2Data, 3000);
      } else {
        clearInterval(refreshTimer);
      }
    });

    loadPm2Data();
    refreshTimer = setInterval(loadPm2Data, 3000);
  </script>
</body>
</html>
COCKPITHMTL

    ok "Cockpit 'Node.js (PM2)' extension package installed (/usr/share/cockpit/node-pm2)."

    # 4. SSH Tunnel Helper Script
    cat > /usr/local/bin/mon_tunnel <<'MONTUNNEL'
#!/usr/bin/env bash
if [[ -f /etc/production-server.conf ]]; then source /etc/production-server.conf; fi
u="${DEPLOY_USER:-$(id -un)}"
echo ""
echo "=== Access Cockpit Web Console from your Computer ==="
echo "Run this command in a terminal on your personal computer/laptop:"
echo ""
echo "    ssh -L 9090:127.0.0.1:9090 ${u}@<server-ip>"
echo ""
echo "Then open your browser to: https://localhost:9090"
echo "Login with username '${u}' (or root) and your password."
echo ""
MONTUNNEL
    chmod 755 /usr/local/bin/mon_tunnel
    ok "SSH tunnel helper installed → /usr/local/bin/mon_tunnel (or alias 'tunnel')"

    # ── E. PM2 auto-logging & system logrotate ────────────────────────────────
    if $INSTALL_PM2; then
        # 1. Clean up pm2-logrotate and pm2-prometheus-exporter (saves ~55MB RAM)
        su - "$USERNAME" -c "
            export NVM_DIR=\"\$HOME/.nvm\"; source \"\$NVM_DIR/nvm.sh\"
            pm2 uninstall pm2-logrotate 2>/dev/null || true
            pm2 uninstall pm2-prometheus-exporter 2>/dev/null || true
            pm2 save 2>/dev/null || true
        " 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true

        # 2. Global PM2 default config file for auto-logging
        local pm2_home="/home/${USERNAME}/.pm2"
        mkdir -p "$pm2_home"
        
        cat > "$pm2_home/conf.js" <<'PM2CONF'
// PM2 Global Configuration
module.exports = {
  apps: [],
  default_options: {
    output: null,
    error: null,
    log: null,
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    autorestart: true,
    max_restarts: 10,
    min_uptime: '10s',
    max_memory_restart: '500M',
    merge_logs: false,
    ignore_watch: ['node_modules', '.git', 'logs', 'dist']
  }
};
PM2CONF
        chown "$USERNAME:$USERNAME" "$pm2_home/conf.js"
        ok "PM2 global config created."

        # 3. Create auto-logging wrapper helper script
        cat > "$pm2_home/pm2-start-logs.sh" <<'PM2STARTSCRIPT'
#!/bin/bash
# pm2-start-logs.sh — PM2 app start with AUTOMATIC detailed logging
set -euo pipefail

get_app_name() {
    local script="$1"
    shift
    for i in "$@"; do
        if [[ "${prev:-}" == "--name" ]]; then
            echo "$i"
            return 0
        fi
        prev="$i"
    done
    basename "$script" | sed 's/\.[^.]*$//'
}

setup_nvm() {
    if [[ ! -f "$HOME/.nvm/nvm.sh" ]]; then
        echo "Error: NVM not found. Please install via init.sh first."
        return 1
    fi
    export NVM_DIR="$HOME/.nvm"
    source "$NVM_DIR/nvm.sh"
    return 0
}

if [[ $# -eq 0 ]]; then
    echo "Usage: pm2-start-logs <app.js> [pm2-options]"
    echo "Example: pm2-start-logs app.js --name myapp -- --port 3000"
    exit 1
fi

setup_nvm || exit 1

script="$1"
shift
app_name=$(get_app_name "$script" "$@")
logs_dir="$HOME/.pm2/logs"

mkdir -p "$logs_dir"

pm2 start "$script" \
    --name "$app_name" \
    --output "$logs_dir/${app_name}-out.log" \
    --error "$logs_dir/${app_name}-error.log" \
    --log-date-format 'YYYY-MM-DD HH:mm:ss Z' \
    "$@" 2>&1

echo ""
echo "✓ App started: $app_name"
echo "  Output logs: $logs_dir/${app_name}-out.log"
echo "  Error logs:  $logs_dir/${app_name}-error.log"
PM2STARTSCRIPT
        chmod +x "$pm2_home/pm2-start-logs.sh"
        chown "$USERNAME:$USERNAME" "$pm2_home/pm2-start-logs.sh"
        ok "PM2 auto-logging wrapper script created."

        # 4. Create enhanced ecosystem.config.js template
        cat > "$pm2_home/ecosystem.template.js" <<'ECOSYSTEMTEMPLATE'
module.exports = {
  apps: [
    {
      name: 'api-server',
      script: 'app.js',
      cwd: '/home/username/projects/api',
      output: '/home/username/.pm2/logs/api-server-out.log',
      error: '/home/username/.pm2/logs/api-server-error.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      instances: 1,
      exec_mode: 'cluster',
      env: {
        NODE_ENV: 'production',
        PORT: 3000
      },
      watch: false,
      max_memory_restart: '500M'
    }
  ]
};
ECOSYSTEMTEMPLATE
        chown "$USERNAME:$USERNAME" "$pm2_home/ecosystem.template.js"
        ok "PM2 ecosystem.config.js template created → ~/.pm2/ecosystem.template.js"
    fi

    # ── F. Health Check — Verify Cockpit socket is active ─────────────────────
    info "Performing monitoring stack health checks..."
    if systemctl is-active --quiet cockpit.socket 2>/dev/null; then
        ok "✓ Cockpit socket active (127.0.0.1:9090, 0 MB idle memory)"
    else
        warn "✗ Cockpit socket inactive — start with: systemctl start cockpit.socket"
    fi

    # ── G. server_status — quick CLI overview script ──────────────────────────
    local deploy_user="$USERNAME"
    cat > "$STATUS_SCRIPT" <<STATUSSCRIPT
#!/usr/bin/env bash
# server_status — Quick overview of all running projects & services
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

cpu_load=\$(uptime | awk -F'load average:' '{print \$2}' | awk '{print \$1}' | tr -d ',')
echo -e "  \${GRY}CPU Load (1m):\${R}  \${WHT}\${cpu_load}\${R}"

mem_total=\$(free -m | awk '/^Mem:/{print \$2}')
mem_used=\$(free  -m | awk '/^Mem:/{print \$3}')
if [[ -n "\${mem_total}" && "\${mem_total}" -gt 0 ]] 2>/dev/null; then
    mem_pct=\$(( mem_used * 100 / mem_total ))
else
    mem_pct=0
fi
if   (( mem_pct >= 90 )); then mem_color=\$RED
elif (( mem_pct >= 70 )); then mem_color=\$YLW
else                           mem_color=\$GRN; fi
echo -e "  \${GRY}Memory:\${R}        \${mem_color}\${mem_used}MB / \${mem_total}MB (\${mem_pct}%)\${R}"

swap_total=\$(free -m | awk '/^Swap:/{print \$2}')
swap_used=\$(free  -m | awk '/^Swap:/{print \$3}')
swappiness=\$(cat /proc/sys/vm/swappiness 2>/dev/null || echo 10)
ram_trigger=\$(( 100 - swappiness ))
if [[ -n "\${swap_total}" && "\${swap_total}" -gt 0 ]] 2>/dev/null; then
    swap_pct=\$(( swap_used * 100 / swap_total ))
    if   (( swap_pct >= 80 )); then swap_color=\$RED
    elif (( swap_pct >= 40 )); then swap_color=\$YLW
    else                            swap_color=\$GRN; fi
    echo -e "  \${GRY}Swap:\${R}          \${swap_color}\${swap_used}MB / \${swap_total}MB (\${swap_pct}%)\${R} \${GRY}[triggers at \${ram_trigger}% RAM, swappiness=\${swappiness}]\${R}"
else
    echo -e "  \${GRY}Swap:\${R}          \${GRY}None configured\${R}"
fi

disk_pct=\$(df -h / | awk 'NR==2{print \$5}' | tr -d '%')
disk_used=\$(df -h / | awk 'NR==2{print \$3}')
disk_total=\$(df -h / | awk 'NR==2{print \$2}')
if   (( disk_pct >= 90 )); then disk_color=\$RED
elif (( disk_pct >= 70 )); then disk_color=\$YLW
else                            disk_color=\$GRN; fi
echo -e "  \${GRY}Disk (/):\${R}      \${disk_color}\${disk_used} / \${disk_total} (\${disk_pct}%)\${R}"
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

# ── Management & Monitoring Stack ─────────────────────────────────────────────
echo ""
echo -e "  \${BOLD}\${WHT}Host Management & Monitoring Stack\${R}"
if systemctl is-active --quiet cockpit.socket 2>/dev/null; then
    echo -e "  \${GRN}✔\${R}  Cockpit Web Console active (Host, Logs & PM2 GUI → 127.0.0.1:9090)"
    echo -e "  \${GRY}     SSH Tunnel: ssh -L 9090:127.0.0.1:9090 ${deploy_user}@<server-ip>\${R}"
    echo -e "  \${GRY}     Web URL:    https://localhost:9090 (0 MB idle RAM)\${R}"
else
    echo -e "  \${GRY}  Cockpit socket not active (sudo systemctl enable --now cockpit.socket)\${R}"
fi

# ── Docker ────────────────────────────────────────────────────────────────────
if command -v docker &>/dev/null; then
    echo ""
    echo -e "  \${BOLD}\${WHT}Docker\${R}"
    if systemctl is-active --quiet docker 2>/dev/null; then
        echo -e "  \${GRN}✔\${R}  Docker daemon running"
        running=\$(docker ps --format '{{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null)
        if [[ -n "\${running}" ]]; then
            echo -e "  \${GRY}  CONTAINER                STATUS              IMAGE\${R}"
            echo "\${running}" | while IFS=\$'\t' read -r name status image; do
                printf "  \${GRY}  %-24s %-20s %s\${R}\n" "\${name}" "\${status}" "\${image}"
            done
        else
            echo -e "  \${GRY}  No running containers\${R}"
        fi
    else
        echo -e "  \${GRY}  Docker daemon not running (sudo systemctl start docker)\${R}"
    fi
fi

echo ""
echo -e "  \${GRY}\${HR}\${R}"
echo -e "  \${GRY}Web Console (Host, Logs & PM2): http://localhost:9090 (Cockpit via SSH tunnel)\${R}"
echo ""
STATUSSCRIPT

    chmod +x "$STATUS_SCRIPT"
    ln -sf "$STATUS_SCRIPT" "/home/$USERNAME/server_status" 2>/dev/null || true

    ok "server_status script installed → $STATUS_SCRIPT"
    ok "Run from anywhere:  server_status"

    section_end
}

harden_kernel() {
    section "10" "Kernel Hardening (sysctl)"

    cat > "$SYSCTL_CONF" <<SYSCTL
# Kernel hardening — init.sh v${SCRIPT_VERSION}

# IP spoofing protection
net.ipv4.conf.all.rp_filter              = 1
net.ipv4.conf.default.rp_filter          = 1

# SYN flood protection
net.ipv4.tcp_syncookies                  = 1
net.ipv4.tcp_max_syn_backlog             = 2048

# Disable ICMP redirects (IPv4 & IPv6)
net.ipv4.conf.all.accept_redirects       = 0
net.ipv4.conf.default.accept_redirects   = 0
net.ipv4.conf.all.send_redirects         = 0
net.ipv6.conf.all.accept_redirects       = 0
net.ipv6.conf.default.accept_redirects   = 0

# Disable IPv6 Router Advertisements (prevents rogue router MITM)
net.ipv6.conf.all.accept_ra              = 0
net.ipv6.conf.default.accept_ra          = 0

# Log suspicious packets & ignore broadcasts
net.ipv4.conf.all.log_martians           = 1
net.ipv4.icmp_echo_ignore_broadcasts     = 1

# Hardlink/symlink protection
fs.protected_hardlinks                   = 1
fs.protected_symlinks                    = 1

# Node.js performance & memory tuning
fs.file-max                              = 100000
net.core.somaxconn                       = 65535
net.ipv4.tcp_max_tw_buckets              = 1440000
vm.swappiness                            = ${SWAPPINESS:-10}
vm.vfs_cache_pressure                    = 50
SYSCTL
    chmod 644 "$SYSCTL_CONF"
    sysctl -p "$SYSCTL_CONF" 2>/dev/null | tail -3 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true

    # ── Swap Configuration & Cushion ─────────────────────────────────────────
    local swap_action="${SWAP_SIZE:-2G}"
    local active_swappiness="${SWAPPINESS:-10}"
    local active_threshold="${SWAP_RAM_THRESHOLD:-90}"

    if [[ "$swap_action" =~ ^(0|none|skip)$ ]]; then
        info "Swapfile creation skipped by user/flag."
    elif [[ "$swap_action" == "keep" ]]; then
        local current_sw
        current_sw=$(grep SwapTotal /proc/meminfo 2>/dev/null | awk '{printf "%d MB", $2/1024}' || echo "active")
        ok "Retaining existing swap configuration (${current_sw}, activates at ${active_threshold}% RAM, swappiness=${active_swappiness})."
    else
        local alloc_flag alloc_mb
        if [[ "$swap_action" =~ ^([0-9]+)[Gg]$ ]]; then
            local num="${BASH_REMATCH[1]}"
            alloc_mb=$(( num * 1024 ))
            alloc_flag="${num}G"
        elif [[ "$swap_action" =~ ^([0-9]+)[Mm]$ ]]; then
            local num="${BASH_REMATCH[1]}"
            alloc_mb="$num"
            alloc_flag="${num}M"
        elif [[ "$swap_action" =~ ^[0-9]+$ ]]; then
            alloc_mb="$swap_action"
            alloc_flag="${swap_action}M"
        else
            alloc_mb=2048
            alloc_flag="2G"
        fi

        local need_create=true
        if [[ -f /swapfile ]]; then
            local existing_bytes
            existing_bytes=$(stat -c %s /swapfile 2>/dev/null || wc -c < /swapfile 2>/dev/null || echo 0)
            local target_bytes=$(( alloc_mb * 1024 * 1024 ))
            if (( existing_bytes >= target_bytes * 95 / 100 && existing_bytes <= target_bytes * 105 / 100 )); then
                need_create=false
                chmod 600 /swapfile
                swapon /swapfile &>/dev/null || true
                ok "Existing /swapfile matches requested size (${alloc_flag}) — active."
            else
                info "Resizing existing /swapfile to ${alloc_flag}..."
                swapoff /swapfile 2>/dev/null || true
                rm -f /swapfile
            fi
        fi

        if $need_create; then
            info "Allocating ${alloc_flag} swapfile (/swapfile)..."
            fallocate -l "$alloc_flag" /swapfile 2>/dev/null || \
                dd if=/dev/zero of=/swapfile bs=1M count="$alloc_mb" status=none 2>/dev/null || true
            if [[ -f /swapfile ]]; then
                chmod 600 /swapfile
                mkswap /swapfile &>/dev/null || true
                if swapon /swapfile &>/dev/null; then
                    ok "${alloc_flag} swap cushion created & activated (/swapfile)."
                else
                    warn "Swapfile created but swapon failed (environment may be containerized or lack swap privileges)."
                fi
                if ! grep -q '/swapfile' /etc/fstab 2>/dev/null; then
                    echo '/swapfile none swap sw 0 0' >> /etc/fstab
                fi
            else
                warn "Failed to create /swapfile (insufficient disk space or permission denied)."
            fi
        fi
        ok "Swap configured: ${alloc_flag} (/swapfile, activates at ${active_threshold}% RAM, swappiness=${active_swappiness})."
    fi

    ok "Kernel: SYN flood, IP spoof, ICMP, file descriptor & memory limits tuned."

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  11 — FAIL2BAN
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_fail2ban() {
    section "11" "fail2ban — Brute Force Protection"

    if ! command -v fail2ban-server &>/dev/null; then
        info "fail2ban not installed — installing now..."
        apt-get install -y fail2ban 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        if ! command -v fail2ban-server &>/dev/null; then
            warn "fail2ban installation failed — install manually: apt-get install -y fail2ban"
            section_end; return
        fi
        ok "fail2ban installed."
    fi

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

    ok "fail2ban: ban after 5 failed SSH attempts (1 hour)."

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  12 — UFW
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_firewall() {
    $GEN_FW || { section "12" "UFW"; warn "Skipped."; section_end; return; }

    section "12" "UFW Firewall"

    if ! command -v ufw &>/dev/null; then
        warn "UFW not installed: apt-get install -y ufw"; section_end; return
    fi

    # Detect SSH port from sshd_config (fallback to 22 safely without pipefail trigger)
    local ssh_port=22
    if [[ -f /etc/ssh/sshd_config ]]; then
        local detected_port
        detected_port=$(awk '/^[Pp]ort[ \t]+[0-9]+/ {print $2; exit}' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true)
        if [[ -n "$detected_port" && "$detected_port" =~ ^[0-9]+$ ]]; then
            ssh_port="$detected_port"
        fi
    fi

    # Enforce IPv6 filtering in UFW so IPv6 cannot bypass firewall
    if [[ -f /etc/default/ufw ]]; then
        sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw 2>/dev/null || true
    fi

    run "ufw default deny incoming"
    run "ufw default allow outgoing"
    run "ufw default deny routed"
    run "ufw logging low"
    run "ufw allow $ssh_port/tcp   comment 'SSH'"
    # Cockpit Web Console (9090) is strictly bound to 127.0.0.1 — no external UFW rule opened

    if [[ "$OPEN_NGINX_PORTS" == true ]]; then
        run "ufw allow 80/tcp comment 'HTTP'"
        run "ufw allow 443/tcp comment 'HTTPS'"
    fi

    if [[ "$OPEN_EMAIL_PORTS" == true ]]; then
        run "ufw allow 25/tcp comment 'SMTP'"
        run "ufw allow 465/tcp comment 'SMTPS'"
        run "ufw allow 587/tcp comment 'SMTP Submission'"
        run "ufw allow 143/tcp comment 'IMAP'"
        run "ufw allow 993/tcp comment 'IMAPS'"
        run "ufw allow 110/tcp comment 'POP3'"
        run "ufw allow 995/tcp comment 'POP3S'"
    fi

    if [[ -n "$CUSTOM_PORTS" ]]; then
        IFS=',' read -ra PORTS <<< "$CUSTOM_PORTS"
        for port in "${PORTS[@]}"; do
            port=$(echo "$port" | xargs)  # trim whitespace
            if [[ -n "$port" ]]; then
                run "ufw allow $port comment 'Custom'"
            fi
        done
    fi

    ufw --force enable 2>/dev/null || true

    local fw_desc="SSH($ssh_port)"
    [[ "$OPEN_NGINX_PORTS" == true ]] && fw_desc="$fw_desc, Nginx(80/443)"
    [[ "$OPEN_EMAIL_PORTS" == true ]] && fw_desc="$fw_desc, Email"
    [[ -n "$CUSTOM_PORTS" ]] && fw_desc="$fw_desc, Custom($CUSTOM_PORTS)"
    ok "UFW active: $fw_desc open. Allow other ports as needed."
    info "Open more ports as needed:  sudo ufw allow <port>/tcp"

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  13 — LOGROTATE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_logrotate() {
    section "13" "Log Rotation"

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

    ok "Logrotate configured: daily rotation, compression, copytruncate (0 MB idle RAM)."

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  SERVER METADATA — shared canonical state for docker.sh and nginx.sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

write_server_metadata() {
    cat > /etc/production-server.conf <<EOF
# Production Server Metadata — generated by init.sh
# Shared state across docker.sh, nginx.sh, and companion tools
DEPLOY_USER="${USERNAME}"
DEPLOY_HOME="/home/${USERNAME}"
NODE_VERSION="${NODE_VER}"
PROVISION_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
MONITORING="cockpit"
COCKPIT_PORT="9090"
DOCKER_METRICS_PORT="9323"
SWAP_SIZE="${SWAP_SIZE:-auto}"
SWAP_RAM_THRESHOLD="${SWAP_RAM_THRESHOLD:-90}"
SWAPPINESS="${SWAPPINESS:-10}"
UFW_CONFIGURED="true"
OPEN_NGINX_PORTS="${OPEN_NGINX_PORTS}"
EOF
    chmod 644 /etc/production-server.conf 2>/dev/null || true
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  14 — SUMMARY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

print_summary() {
    echo ""
    echo -e "${PRP}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${PRP}${BOLD}║${R}  ${GRN}${BOLD}%-72s${R}  ${PRP}${BOLD}║${R}\n" \
            "✔  Provisioning Complete"
    printf  "  ${PRP}${BOLD}║${R}  ${GRY}%-72s${R}  ${PRP}${BOLD}║${R}\n" \
            "Your Node.js production server is ready."
    echo -e "${PRP}${BOLD}  ╠${HR2}╣${R}"

    _row() { printf "  ${PRP}${BOLD}║${R}  ${GRY}%-18s${R}  ${WHT}${BOLD}%-52s${R}  ${PRP}${BOLD}║${R}\n" "$1" "$2"; }
    _sep() { echo -e "  ${PRP}${BOLD}╠${HR2}╣${R}"; }
    _hdr() { printf "  ${PRP}${BOLD}║${R}  ${CYN}${BOLD}%-72s${R}  ${PRP}${BOLD}║${R}\n" "$1"; }

    _hdr "Server Details"
    _sep
    _row "User"           "$USERNAME"
    _row "Home Directory" "/home/$USERNAME"
    _row "Node.js"        "v${NODE_VER}  (via NVM ${NVM_VERSION})"
    _row "PM2 Service"    "pm2-${USERNAME}  (auto-starts on reboot)"
    _row "Swap Cushion"   "${SWAP_SIZE:-2G} (trigger: ${SWAP_RAM_THRESHOLD:-90}% RAM, swappiness=${SWAPPINESS:-10})"
    _row "SSH Access"     "Password + SSH Key  (both supported)"
    _row "Root Access"    "sudo -i  (direct root SSH disabled)"
    _row "Monitoring"     "Cockpit GUI :9090  (0 MB idle RAM)"

    _sep
    if [[ -n "$PASSWORD" && "$PASSWORD" != "__KEEP__" ]]; then
        _row "Password" "$PASSWORD"
        _row "" "Save this now -- it will NOT be shown again."
    else
        _row "Password" "(existing password retained)"
    fi

    _sep
    _hdr "Deploy Your First Node.js App (repeat per project)"
    _sep
    local node_steps=(
        "ssh ${USERNAME}@<server-ip>"
        "git clone https://github.com/you/repo.git ~/projects/myapp"
        "cd ~/projects/myapp && npm install"
        "nano .env                     <- add your environment secrets"
        "pm2 start app.js --name myapp -- --port 3000"
        "pm2 save                      <- REQUIRED: survive reboots"
    )
    local i=1
    for s in "${node_steps[@]}"; do
        printf "  ${PRP}${BOLD}║${R}  ${GRN}${BOLD}%s.${R}  ${WHT}%-68s${R}  ${PRP}${BOLD}║${R}\n" "$i" "$s"
        (( i++ ))
    done

    _sep
    _hdr "Management & Monitoring Quick Reference"
    _sep
    local mon_steps=(
        "server_status               quick overview of system & services"
        "tunnel                      show SSH tunnel command for Cockpit GUI"
        "sys_logs                    view recent system journal logs"
        "sys_errors                  view critical system error logs"
        "nginx_logs                  view web server access and errors"
        "pm2_jlogs                   view PM2 systemd journal logs"
        "pm2 monit                   live terminal Node.js process monitor"
        "pm2 logs                    tail live logs of all PM2 apps"
        "plog_app <name>             view last 100 lines for one app"
        "plog_errors                 view recent errors from all apps"
    )
    for s in "${mon_steps[@]}"; do
        printf "  ${PRP}${BOLD}║${R}  ${CYN}>${R}  ${WHT}%-69s${R}  ${PRP}${BOLD}║${R}\n" "$s"
    done

    _sep
    _hdr "COCKPIT WEB CONSOLE (Host, Logs & Node.js PM2 GUI)"
    _sep
    local cockpit_info=(
        "Access via SSH Tunnel (Socket Active on 127.0.0.1:9090):"
        "  ssh -L 9090:127.0.0.1:9090 ${USERNAME}@<server-ip>"
        "  Open in Browser: https://localhost:9090"
        "  Login with: ${USERNAME} (or root) and your password"
        ""
        "Features Included:"
        "  - Node.js (PM2) GUI: live app list, RAM/CPU, start/stop & logs"
        "  - Real-time hardware utilization (CPU, RAM, Disk I/O, Network)"
        "  - systemd service control (start/stop/restart PM2, Nginx, Docker)"
        "  - Journald log search, filtering by priority, unit, and keyword"
        "  - Web terminal with full root/sudo escalation"
        "  - Pure Zero-Idle-RAM: sleeps completely until opened in browser"
    )
    for s in "${cockpit_info[@]}"; do
        printf "  ${PRP}${BOLD}║${R}  ${WHT}%-72s${R}  ${PRP}${BOLD}║${R}\n" "$s"
    done

    _sep
    _hdr "Add a Second Project (fully independent)"
    _sep
    local multi_steps=(
        "pm2 start app.js --name blog -- --port 4000"
        "pm2 save                      <- always save after adding an app"
        "Each app has its own port, logs, and restart policy"
    )
    for s in "${multi_steps[@]}"; do
        printf "  ${PRP}${BOLD}║${R}  ${GRN}*${R}  ${WHT}%-69s${R}  ${PRP}${BOLD}║${R}\n" "$s"
    done

    _sep
    printf  "  ${PRP}${BOLD}║${R}  ${GRY}%-72s${R}  ${PRP}${BOLD}║${R}\n" \
            "Log file: ${LOG_FILE}"
    echo -e "${PRP}${BOLD}  ╚${HR2}╝${R}"
    echo ""
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  MAIN
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

main() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    touch "$LOG_FILE" 2>/dev/null && chmod 640 "$LOG_FILE" 2>/dev/null || true

    parse_args "$@"
    show_banner
    prompt_inputs   # ask for username, password, Node version if not passed as flags

    _log INFO "=== init.sh v${SCRIPT_VERSION} started. User=$USERNAME ==="

    preflight           # 01
    create_user         # 02
    setup_ssh           # 03 — password + key; root SSH blocked
    setup_sudo          # 04 — full root + targeted NOPASSWD
    setup_shell         # 05 — aliases, NVM, PM2
    install_git         # 06
    install_node        # 07
    install_pm2         # 08 — bulletproof
    setup_monitoring    # 09 — Cockpit Web Console + PM2 GUI + server_status
    harden_kernel       # 10
    setup_fail2ban      # 11
    setup_firewall      # 12
    setup_logrotate     # 13
    write_server_metadata # Saves canonical server config to /etc/production-server.conf
    print_summary       # 14

    _log INFO "=== Provisioning complete. User=$USERNAME ==="
}

main "$@"