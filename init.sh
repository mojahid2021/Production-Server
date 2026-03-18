#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  init.sh  —  Node.js Production Server Provisioning  v6.0.0                 ║
# ║  Ubuntu 20.04 / 22.04 / 24.04 LTS                                           ║
# ╠══════════════════════════════════════════════════════════════════════════════╣
# ║                                                                              ║
# ║  WHAT THIS DOES                                                              ║
# ║  01. Creates deploy user with password + SSH key access                      ║
# ║  02. Root access via sudo (password required)                                ║
# ║  03. SSH: password + key login; direct root SSH blocked                      ║
# ║  04. Installs Git, NVM, Node.js, PM2 (bulletproof startup)                  ║
# ║  05. Nginx base setup for MULTIPLE Node.js projects                          ║
# ║  06. Shell profile — aliases, NVM, PM2 auto-complete                        ║
# ║  07. Monitoring: Netdata (real-time) + PM2 dashboard + status script        ║
# ║  08. fail2ban, sysctl hardening, UFW, logrotate                             ║
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
# ║        --no-mon     Skip Netdata monitoring                                  ║
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

readonly SCRIPT_VERSION="6.0.0"
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
USER_PW=""    # captured (hidden) deploy-user password for informational/confirmation use
ROOT_PW=""    # captured (hidden) root password for informational/confirmation use

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  COLORS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [[ -t 1 ]] && tput colors &>/dev/null && (( $(tput colors) >= 8 )); then
    R=$'\033[0m'  BOLD=$'\033[1m'  DIM=$'\033[2m'
    GRN=$'\033[38;5;82m'   BLU=$'\033[38;5;33m'   CYN=$'\033[38;5;45m'
    YLW=$'\033[38;5;220m'  ORG=$'\033[38;5;208m'  PRP=$'\033[38;5;141m'
    WHT=$'\033[38;5;255m'  GRY=$'\033[38;5;244m'  RED=$'\033[38;5;196m'
    TICK="${GRN}✔${R}"  CROSS="${RED}✘${R}"  WARN_IC="${YLW}⚠${R}"
    ARROW="${CYN}›${R}"
else
    R='' BOLD='' DIM='' GRN='' BLU='' CYN='' YLW='' ORG='' PRP='' WHT='' GRY='' RED=''
    TICK='[OK]' CROSS='[ERR]' WARN_IC='[WARN]' ARROW='->'
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
die()   { echo -e "\n  ${CROSS}  ${RED}${BOLD}FATAL: $*${R}\n" >&2; _log ERROR "$*"; exit 1; }

section()     { echo ""; echo -e "  ${BLU}${BOLD}┌─ $1 / $2${R}"; echo -e "  ${BLU}${DIM}│${R}"; }
section_end() { echo -e "  ${BLU}${DIM}└${HR:0:60}${R}"; }

run() {
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
            "  ⚡  init.sh  —  Node.js Production Server Provisioner  v${SCRIPT_VERSION}"
    printf  "  ${BLU}${BOLD}║${R}${GRY}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  Ubuntu 20.04 / 22.04 / 24.04 LTS  ·  Git · NVM · PM2 · Nginx · Netdata"
    echo -e "${BLU}${BOLD}  ╠${HR2}╣${R}"
    printf  "  ${BLU}${BOLD}║${R}${GRY}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  Run:  sudo ./init.sh                    (interactive)"
    printf  "  ${BLU}${BOLD}║${R}${GRY}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  Run:  sudo ./init.sh -u <user> -n 20   (with flags)"
    echo -e "${BLU}${BOLD}  ╚${HR2}╝${R}"
    echo ""
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  USAGE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

usage() {
    echo ""
    echo -e "${BLU}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${BLU}${BOLD}║${R}${WHT}${BOLD}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  init.sh  —  Node.js Production Server Provisioner  v${SCRIPT_VERSION}"
    echo -e "${BLU}${BOLD}  ╚${HR2}╝${R}"
    echo ""
    echo -e "  ${BOLD}${WHT}Usage${R}"
    echo -e "  ${GRY}${HR:0:60}${R}"
    echo -e "    ${CYN}sudo ./init.sh${R}                          ${GRY}# fully interactive (recommended)${R}"
    echo -e "    ${CYN}sudo ./init.sh${R} ${WHT}-u <username> [OPTIONS]${R}  ${GRY}# pass values directly${R}"
    echo ""
    echo -e "  ${BOLD}${WHT}Options${R}"
    echo -e "  ${GRY}${HR:0:60}${R}"
    printf  "    ${CYN}%-22s${R}  ${WHT}%s${R}\n" \
        "-u  USERNAME"   "Deploy username                       (required)" \
        "-p  PASSWORD"   "Custom password                       (auto-generated if omitted)" \
        "-k  PUBKEY"     "Path to SSH public key file           (optional)" \
        "-n  NODE_VER"   "Node.js version: 18, 20, 22, lts/*   (default: 20)" \
        "    --no-nvm"   "Skip NVM + Node.js installation" \
        "    --no-pm2"   "Skip PM2 installation" \
        "    --no-fw"    "Skip UFW firewall configuration" \
        "    --no-mon"   "Skip Netdata monitoring installation" \
        "-h  --help"     "Show this help and exit"
    echo ""
    echo -e "  ${BOLD}${WHT}Examples${R}"
    echo -e "  ${GRY}${HR:0:60}${R}"
    echo -e "    ${GRN}sudo ./init.sh${R}                          ${GRY}# interactive wizard${R}"
    echo -e "    ${GRN}sudo ./init.sh -u mojahid -n 20${R}         ${GRY}# set user + Node version${R}"
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
        echo -e "  ${BLU}${BOLD}┌${prefix}${pad}${R}"
        echo -e "  ${BLU}${BOLD}│${R}"
    }
    # Print a labelled hint line under a step
    _hint() { echo -e "  ${BLU}${BOLD}│${R}  ${GRY}$*${R}"; }
    # Close the step box — same width as _step header
    _step_end() { echo -e "  ${BLU}${BOLD}└$(printf '─%.0s' $(seq 1 "${_STEP_W}"))${R}"; echo ""; }
    # Print an inline prompt arrow
    _prompt() { printf "  ${BLU}${BOLD}│${R}  ${CYN}${BOLD}❯${R}  "; }
    # Print a success line
    _ok()   { echo -e "  ${BLU}${BOLD}│${R}  ${TICK}  $*"; }
    # Print a warning line inside a step
    _warn() { echo -e "  ${BLU}${BOLD}│${R}  ${WARN_IC}  ${YLW}$*${R}"; }

    # ── Header ────────────────────────────────────────────────────────────────
    echo ""
    echo -e "${BLU}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${BLU}${BOLD}║${R}${WHT}${BOLD}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  ⚙   Interactive Setup Wizard"
    printf  "  ${BLU}${BOLD}║${R}${GRY}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  Answer each prompt below.  Press Enter to accept any default value."
    echo -e "${BLU}${BOLD}  ╚${HR2}╝${R}"

    # ══════════════════════════════════════════════════════════════════════════
    # STEP 1 — Username
    # ══════════════════════════════════════════════════════════════════════════
    if [[ -z "$USERNAME" ]]; then
        _step 1 3 "Deploy Username"
        _hint "The Linux user that will own and run your Node.js projects."
        _hint "Rules: lowercase letters, digits, _ or -  ·  max 31 chars  ·  start with a letter"
        _hint "Example:  mojahid   deploy   webadmin"
        echo -e "  ${BLU}${BOLD}│${R}"
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
                _warn "User '${USERNAME}' already exists on this system. Choose a different name."
                USERNAME=""
                continue
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
        _step 2 3 "Deploy User Password"
        _hint "Type a custom password, or press Enter to auto-generate a secure one."
        _hint "Minimum 8 characters if you choose your own.  Input is hidden."
        echo -e "  ${BLU}${BOLD}│${R}"
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
        _step_end
    else
        echo -e "  ${TICK}  ${GRY}Password provided via flag.${R}"
        echo ""
    fi

    # ══════════════════════════════════════════════════════════════════════════
    # STEP 3 — Node.js version
    # ══════════════════════════════════════════════════════════════════════════
    _step 3 3 "Node.js Version"
    _hint "Which Node.js version to install via NVM."
    _hint "Options: 18  20  22  lts/*     Recommended: 20"
    _hint "Press Enter to accept the default: ${WHT}${NODE_VER}${GRY}"
    echo -e "  ${BLU}${BOLD}│${R}"
    _prompt && get_input && _node_input="$REPLY"
    if [[ -n "$_node_input" ]]; then
        NODE_VER="$_node_input"
    fi
    _ok "Node.js version:  ${WHT}${BOLD}v${NODE_VER}${R}"
    _step_end

    # ══════════════════════════════════════════════════════════════════════════
    # CONFIRMATION SUMMARY
    # ══════════════════════════════════════════════════════════════════════════
    echo ""
    echo -e "${BLU}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${BLU}${BOLD}║${R}${WHT}${BOLD}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  📋  Configuration Summary — Please Review"
    echo -e "${BLU}${BOLD}  ╠${HR2}╣${R}"
    _conf_row() {
        printf "  ${BLU}${BOLD}║${R}  ${GRY}%-18s${R}  ${WHT}${BOLD}%-52s${R}  ${BLU}${BOLD}║${R}\n" "$1" "$2"
    }
    _conf_row "Username"    "$USERNAME"
    _conf_row "Password"    "$([ -n "$CUSTOM_PASS" ] && echo "custom (hidden)" || echo "will be auto-generated")"
    _conf_row "Node.js"     "v${NODE_VER}  (via NVM ${NVM_VERSION})"
    _conf_row "NVM"         "$(  $INSTALL_NVM && echo "✔ install" || echo "– skip (--no-nvm)")"
    _conf_row "PM2"         "$(  $INSTALL_PM2 && echo "✔ install" || echo "– skip (--no-pm2)")"
    _conf_row "UFW"         "$(  $GEN_FW      && echo "✔ configure" || echo "– skip (--no-fw)")"
    _conf_row "Monitoring"  "$( $SETUP_MON   && echo "✔ Netdata + PM2 + server_status" || echo "– skip (--no-mon)")"
    echo -e "${BLU}${BOLD}  ╚${HR2}╝${R}"
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

    local cmd="useradd --gid '$USERNAME' --shell /bin/bash --comment 'Deploy $USERNAME' --create-home --home-dir '/home/$USERNAME' '$USERNAME'"
    run "$cmd"
    ok "User '$USERNAME' created → /home/$USERNAME"

    local hashed
    hashed=$(openssl passwd -6 "$PASSWORD") || die "Failed to hash password (openssl error)."
    [[ -n "$hashed" ]] || die "Password hash is empty — check openssl installation."
    usermod -p "$hashed" "$USERNAME"
    ok "Password set."

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

        systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
        ok "sshd: PasswordAuthentication=yes, PermitRootLogin=no."
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
#  06 — SHELL PROFILE
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
        apt-get install -y git 2>&1 | tail -3 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
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
#  09 — PM2
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

    # Netdata runs on port 19999 by default — restrict to localhost only
    if [[ -f /etc/netdata/netdata.conf ]]; then
        # Bind only to localhost — access via SSH tunnel, not public internet
        sed -i 's/.*bind to.*/\tbind to = 127.0.0.1/' /etc/netdata/netdata.conf 2>/dev/null || true
        systemctl restart netdata 2>/dev/null || true
        ok "Netdata: bound to 127.0.0.1:19999 (localhost only)."
        info "Access dashboard via SSH tunnel:"
        info "  ssh -L 19999:localhost:19999 $USERNAME@<server-ip>"
        info "  Then open: http://localhost:19999"
    fi

    # ── B. PM2 log rotation module ────────────────────────────────────────────
    if $INSTALL_PM2; then
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

    ok "server_status script installed → $STATUS_SCRIPT"
    ok "Run from anywhere:  server_status"

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  12 — KERNEL HARDENING
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

harden_kernel() {
    section "11" "Kernel Hardening (sysctl)"

    cat > "$SYSCTL_CONF" <<SYSCTL
# Kernel hardening — init.sh v${SCRIPT_VERSION}

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

    ufw --force enable 2>/dev/null || true

    ok "UFW active: SSH(22) open. Allow other ports as needed."
    info "Open more ports as needed:  sudo ufw allow <port>/tcp"

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  15 — LOGROTATE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_logrotate() {
    section "14" "Log Rotation"

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

    ok "Logrotate: PM2 logs 14-day retention, daily rotation, compressed."

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  16 — SUMMARY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

print_summary() {
    echo ""
    echo -e "${BLU}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${BLU}${BOLD}║${R}${GRN}${BOLD}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  ✔  Provisioning Complete"
    printf  "  ${BLU}${BOLD}║${R}${GRY}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  Your Node.js production server is ready."
    echo -e "${BLU}${BOLD}  ╠${HR2}╣${R}"

    _row() { printf "  ${BLU}${BOLD}║${R}  ${GRY}%-22s${R}  ${WHT}${BOLD}%-50s${R}  ${BLU}${BOLD}║${R}\n" "$1" "$2"; }
    _sep() { echo -e "  ${BLU}${BOLD}╠${HR2}╣${R}"; }
    _hdr() { printf "  ${BLU}${BOLD}║${R}  ${CYN}${BOLD}%-74s${R}  ${BLU}${BOLD}║${R}\n" "$1"; }

    _hdr "Server Details"
    _sep
    _row "User"           "$USERNAME"
    _row "Home Directory" "/home/$USERNAME"
    _row "Node.js"        "v${NODE_VER}  (via NVM ${NVM_VERSION})"
    _row "PM2 Service"    "pm2-${USERNAME}  (systemd — auto-starts on reboot)"
    _row "SSH Access"     "password + SSH key  (both supported)"
    _row "Root Access"    "ssh ${USERNAME}@<server>  →  sudo -i  (direct root SSH blocked)"
    _row "Monitoring"     "server_status  ·  pm2 monit  ·  Netdata :19999"

    _sep
    printf "  ${BLU}${BOLD}║${R}  ${YLW}${BOLD}%-22s${R}  ${ORG}${BOLD}%-50s${R}  ${BLU}${BOLD}║${R}\n" \
        "⚠  Password" "$PASSWORD"
    printf "  ${BLU}${BOLD}║${R}  ${GRY}%-22s${R}  ${GRY}%-50s${R}  ${BLU}${BOLD}║${R}\n" \
        "" "Save this now — it will NOT be shown again."

    _sep
    _hdr "🚀  Deploy Your First Node.js App  (repeat per project)"
    _sep
    local node_steps=(
        "ssh ${USERNAME}@<server-ip>"
        "git clone https://github.com/you/repo.git ~/projects/myapp"
        "cd ~/projects/myapp && npm install"
        "nano .env                     ← add your environment secrets"
        "pm2 start app.js --name myapp -- --port 3000"
        "pm2 save                      ← REQUIRED: survive reboots"
    )
    local i=1
    for s in "${node_steps[@]}"; do
        printf "  ${BLU}${BOLD}║${R}  ${GRN}${BOLD}%s.${R}  ${WHT}%-68s${R}  ${BLU}${BOLD}║${R}\n" "$i" "$s"
        (( i++ ))
    done

    _sep
    _hdr "📡  Monitoring & Health Checks"
    _sep
    local mon_steps=(
        "server_status                 quick overview of the whole server"
        "pm2 monit                     live Node.js process monitor (CPU/RAM)"
        "pm2 logs                      tail live app logs"
        "pm2 logs myapp --lines 200    last 200 lines for one app"
        "Netdata real-time dashboard:"
        "  ssh -L 19999:localhost:19999 ${USERNAME}@<server-ip>"
        "  → open http://localhost:19999 in your browser"
    )
    for s in "${mon_steps[@]}"; do
        printf "  ${BLU}${BOLD}║${R}  ${CYN}›${R}  ${WHT}%-70s${R}  ${BLU}${BOLD}║${R}\n" "$s"
    done

    _sep
    _hdr "📖  Add a Second Project  (fully independent)"
    _sep
    local multi_steps=(
        "pm2 start app.js --name blog -- --port 4000"
        "pm2 save                      ← always save after adding an app"
        "Each app has its own port, logs, and restart policy"
    )
    for s in "${multi_steps[@]}"; do
        printf "  ${BLU}${BOLD}║${R}  ${GRN}·${R}  ${WHT}%-70s${R}  ${BLU}${BOLD}║${R}\n" "$s"
    done

    _sep
    printf  "  ${BLU}${BOLD}║${R}${GRY}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  Log file: ${LOG_FILE}"
    echo -e "${BLU}${BOLD}  ╚${HR2}╝${R}"
    echo ""
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

    _log INFO "=== init.sh v${SCRIPT_VERSION} started. User=$USERNAME ==="

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