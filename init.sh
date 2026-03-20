#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  init.sh  —  Node.js Production Server Provisioning  v7.0.0                 ║
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
# ║  09. Monitoring — Prometheus + Grafana + node_exporter + PM2 exporter       ║
# ║      + Loki (log backend) + Promtail (log agent) + status script            ║
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
# ║        --no-mon     Skip Grafana/Prometheus monitoring                       ║
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

readonly SCRIPT_VERSION="7.0.0"
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
    YLW=$'\033[38;5;220m'  ORG=$'\033[38;5;208m'
    WHT=$'\033[38;5;255m'  GRY=$'\033[38;5;244m'  RED=$'\033[38;5;196m'
    TICK="${GRN}✔${R}"  CROSS="${RED}✘${R}"  WARN_IC="${YLW}⚠${R}"
    ARROW="${CYN}›${R}"
else
    R='' BOLD='' DIM='' GRN='' BLU='' CYN='' YLW='' ORG='' WHT='' GRY='' RED=''
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
            "  Ubuntu 20.04 / 22.04 / 24.04 LTS  ·  Git · NVM · PM2 · Nginx · Grafana"
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
        "    --no-mon"   "Skip Grafana/Prometheus monitoring installation" \
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
    _conf_row "Monitoring"  "$( $SETUP_MON   && echo "✔ Grafana · Prometheus · Loki · Promtail · PM2 exporter" || echo "– skip (--no-mon)")"
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
#  09 — MONITORING
#
#  Five layers:
#    A. node_exporter  — system metrics collector (CPU, RAM, disk, network)
#    B. Prometheus     — metrics database (15-day retention)
#    C. Grafana        — beautiful real-time browser dashboard (port 3001)
#    D. PM2 monit      — built-in process monitor for Node.js apps
#    E. server_status  — quick CLI overview of everything
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_monitoring() {
    $SETUP_MON || { section "09" "Monitoring"; warn "Skipped (--no-mon)."; section_end; return; }

    section "09" "Monitoring — Prometheus + Grafana + PM2 + Status Script"

    # Detect system architecture once (used by Prometheus and node_exporter)
    local arch
    arch=$(dpkg --print-architecture 2>/dev/null || uname -m)
    case "$arch" in
        amd64|x86_64) arch="amd64" ;;
        arm64|aarch64) arch="arm64" ;;
        *) arch="amd64" ;;
    esac

    # ── A. node_exporter — system metrics collector ───────────────────────────
    local ne_ver="1.8.2"
    info "Installing node_exporter v${ne_ver} (system metrics collector)..."
    if ! command -v node_exporter &>/dev/null; then
        wget -q \
            "https://github.com/prometheus/node_exporter/releases/download/v${ne_ver}/node_exporter-${ne_ver}.linux-${arch}.tar.gz" \
            -O /tmp/node_exporter.tar.gz 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        if [[ -f /tmp/node_exporter.tar.gz ]]; then
            tar xzf /tmp/node_exporter.tar.gz -C /tmp
            mv "/tmp/node_exporter-${ne_ver}.linux-${arch}/node_exporter" /usr/local/bin/
            rm -rf "/tmp/node_exporter-${ne_ver}.linux-${arch}" /tmp/node_exporter.tar.gz
            ok "node_exporter installed."
        else
            warn "node_exporter download failed — install manually from https://prometheus.io/download/"
        fi
    else
        ok "node_exporter already installed."
    fi

    # Create node_exporter service user and systemd unit
    useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true
    if [[ ! -f /etc/systemd/system/node_exporter.service ]]; then
        cat > /etc/systemd/system/node_exporter.service <<'NESERVICE'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=127.0.0.1:9100
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
NESERVICE
        systemctl daemon-reload
        systemctl enable --now node_exporter 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        ok "node_exporter service enabled (127.0.0.1:9100)."
    else
        ok "node_exporter service already configured."
    fi

    # ── B. Prometheus — metrics database ─────────────────────────────────────
    local prom_ver="2.53.1"
    info "Installing Prometheus v${prom_ver} (metrics database)..."
    if ! command -v prometheus &>/dev/null; then
        wget -q \
            "https://github.com/prometheus/prometheus/releases/download/v${prom_ver}/prometheus-${prom_ver}.linux-${arch}.tar.gz" \
            -O /tmp/prometheus.tar.gz 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        if [[ -f /tmp/prometheus.tar.gz ]]; then
            tar xzf /tmp/prometheus.tar.gz -C /tmp
            mv "/tmp/prometheus-${prom_ver}.linux-${arch}/prometheus"  /usr/local/bin/
            mv "/tmp/prometheus-${prom_ver}.linux-${arch}/promtool"    /usr/local/bin/
            mkdir -p /etc/prometheus /var/lib/prometheus
            cp -r "/tmp/prometheus-${prom_ver}.linux-${arch}/consoles"          /etc/prometheus/
            cp -r "/tmp/prometheus-${prom_ver}.linux-${arch}/console_libraries" /etc/prometheus/
            rm -rf "/tmp/prometheus-${prom_ver}.linux-${arch}" /tmp/prometheus.tar.gz
            ok "Prometheus installed."
        else
            warn "Prometheus download failed — install manually from https://prometheus.io/download/"
        fi
    else
        ok "Prometheus already installed."
    fi

    # Prometheus system user, directories, config
    useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true
    mkdir -p /etc/prometheus /var/lib/prometheus
    chown prometheus:prometheus /etc/prometheus /var/lib/prometheus

    if [[ ! -f /etc/prometheus/prometheus.yml ]]; then
        cat > /etc/prometheus/prometheus.yml <<'PROMCFG'
global:
  scrape_interval:     15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['127.0.0.1:9100']

  - job_name: 'pm2'
    scrape_interval: 10s
    static_configs:
      - targets: ['127.0.0.1:9209']
        labels:
          instance: pm2_apps
PROMCFG
        chown prometheus:prometheus /etc/prometheus/prometheus.yml
        ok "Prometheus config written to /etc/prometheus/prometheus.yml."
    else
        # Patch existing config to add PM2 exporter job if not present
        if ! grep -q "job_name: 'pm2'" /etc/prometheus/prometheus.yml 2>/dev/null; then
            cat >> /etc/prometheus/prometheus.yml <<'PROMPM2'

  - job_name: 'pm2'
    scrape_interval: 10s
    static_configs:
      - targets: ['127.0.0.1:9209']
        labels:
          instance: pm2_apps
PROMPM2
            ok "Prometheus config patched — PM2 exporter scrape job added."
        else
            ok "Prometheus config already exists (PM2 job present)."
        fi
    fi

    if [[ ! -f /etc/systemd/system/prometheus.service ]]; then
        cat > /etc/systemd/system/prometheus.service <<'PROMSVC'
[Unit]
Description=Prometheus Monitoring
After=network.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus/ \
    --web.listen-address=127.0.0.1:9090 \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --storage.tsdb.retention.time=15d
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
PROMSVC
        systemctl daemon-reload
        systemctl enable --now prometheus 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        ok "Prometheus service enabled (127.0.0.1:9090)."
    else
        ok "Prometheus service already configured."
    fi

    # ── C. Grafana — dashboard UI ─────────────────────────────────────────────
    info "Installing Grafana (dashboard UI)..."
    if ! command -v grafana-server &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https software-properties-common 2>/dev/null | \
            tail -3 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        if wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key 2>/dev/null; then
            echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" \
                > /etc/apt/sources.list.d/grafana.list
            DEBIAN_FRONTEND=noninteractive apt-get update -q 2>/dev/null | \
                tail -3 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
            DEBIAN_FRONTEND=noninteractive apt-get install -y grafana 2>&1 | \
                tail -5 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || {
                warn "Grafana install failed — try manually: apt-get install -y grafana"
            }
        else
            warn "Grafana GPG key download failed — see: https://grafana.com/docs/grafana/latest/setup-grafana/installation/debian/"
        fi
    else
        ok "Grafana already installed."
    fi

    # Configure Grafana: bind to localhost only, port 3001
    # (port 3001 avoids conflicts with Node.js apps commonly running on port 3000)
    if [[ -f /etc/grafana/grafana.ini ]]; then
        sed -i 's/^;*\s*http_port\s*=.*/http_port = 3001/'      /etc/grafana/grafana.ini 2>/dev/null || true
        sed -i 's/^;*\s*http_addr\s*=.*/http_addr = 127.0.0.1/' /etc/grafana/grafana.ini 2>/dev/null || true
        ok "Grafana: configured to listen on 127.0.0.1:3001."
    fi

    # Provision Prometheus as the default Grafana data source
    mkdir -p /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards
    if [[ ! -f /etc/grafana/provisioning/datasources/prometheus.yaml ]]; then
        cat > /etc/grafana/provisioning/datasources/prometheus.yaml <<'GFDS'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    url: http://127.0.0.1:9090
    access: proxy
    isDefault: true
    editable: false
GFDS
        chown grafana:grafana /etc/grafana/provisioning/datasources/prometheus.yaml 2>/dev/null || true
        ok "Grafana: Prometheus data source provisioned."
    else
        ok "Grafana: Prometheus data source already provisioned."
    fi

    # Provision Loki as a Grafana data source (added after Loki is installed later)
    if [[ ! -f /etc/grafana/provisioning/datasources/loki.yaml ]]; then
        cat > /etc/grafana/provisioning/datasources/loki.yaml <<'GFLO'
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    url: http://127.0.0.1:3100
    access: proxy
    isDefault: false
    editable: false
    jsonData:
      maxLines: 1000
GFLO
        chown grafana:grafana /etc/grafana/provisioning/datasources/loki.yaml 2>/dev/null || true
        ok "Grafana: Loki data source provisioned."
    else
        ok "Grafana: Loki data source already provisioned."
    fi

    # Download and provision the Node Exporter Full dashboard (Grafana.com ID 1860)
    local dash_dir="/var/lib/grafana/dashboards"
    mkdir -p "$dash_dir"
    if [[ ! -f "${dash_dir}/node_exporter_full.json" ]]; then
        info "Downloading Node Exporter Full dashboard (grafana.com/dashboards/1860)..."
        if curl -fsSL \
            "https://grafana.com/api/dashboards/1860/revisions/latest/download" \
            -o "${dash_dir}/node_exporter_full.json" 2>/dev/null; then
            # Replace datasource input placeholder with our provisioned source name
            sed -i 's/\${DS_PROMETHEUS}/Prometheus/g; s/"\${DS_PROMETHEUS}"/"Prometheus"/g' "${dash_dir}/node_exporter_full.json" 2>/dev/null || true
            chown -R grafana:grafana "$dash_dir" 2>/dev/null || true
            ok "Node Exporter Full dashboard downloaded."
        else
            warn "Dashboard download failed — import manually: Grafana → + → Import → ID 1860"
        fi
    else
        ok "Node Exporter Full dashboard already present."
    fi

    # Provision dashboard directory in Grafana
    if [[ ! -f /etc/grafana/provisioning/dashboards/node_exporter.yaml ]]; then
        cat > /etc/grafana/provisioning/dashboards/node_exporter.yaml <<GFDB
apiVersion: 1
providers:
  - name: 'Node Exporter'
    orgId: 1
    folder: 'System'
    type: file
    disableDeletion: false
    editable: true
    options:
      path: ${dash_dir}
GFDB
        chown grafana:grafana /etc/grafana/provisioning/dashboards/node_exporter.yaml 2>/dev/null || true
        ok "Grafana dashboard provider provisioned."
    fi

    # Provision PM2 Process Monitor dashboard
    if [[ ! -f "${dash_dir}/pm2_apps.json" ]]; then
        cat > "${dash_dir}/pm2_apps.json" <<'PM2DASH'
{
  "annotations": { "list": [] },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 1,
  "id": null,
  "links": [],
  "panels": [
    {
      "datasource": { "type": "prometheus", "uid": "Prometheus" },
      "fieldConfig": {
        "defaults": {
          "color": { "mode": "thresholds" },
          "mappings": [
            { "options": { "0": { "color": "red",    "index": 0, "text": "stopped"  },
                           "1": { "color": "green",  "index": 1, "text": "online"   },
                           "2": { "color": "yellow", "index": 2, "text": "launching" },
                           "3": { "color": "orange", "index": 3, "text": "errored"  } },
              "type": "value" }
          ],
          "thresholds": { "mode": "absolute", "steps": [
            { "color": "red",   "value": null },
            { "color": "green", "value": 1    }
          ] },
          "unit": "short"
        },
        "overrides": []
      },
      "gridPos": { "h": 4, "w": 24, "x": 0, "y": 0 },
      "id": 1,
      "options": { "colorMode": "background", "graphMode": "none", "justifyMode": "auto",
                   "orientation": "auto", "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false },
                   "textMode": "auto" },
      "pluginVersion": "10.0.0",
      "targets": [
        { "datasource": { "type": "prometheus", "uid": "Prometheus" },
          "expr": "pm2_process_status",
          "instant": true,
          "legendFormat": "{{name}}",
          "refId": "A" }
      ],
      "title": "PM2 App Status",
      "type": "stat"
    },
    {
      "datasource": { "type": "prometheus", "uid": "Prometheus" },
      "fieldConfig": {
        "defaults": { "color": { "mode": "palette-classic" }, "unit": "percent",
          "custom": { "lineWidth": 2, "fillOpacity": 10 } },
        "overrides": []
      },
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 4 },
      "id": 2,
      "options": { "legend": { "calcs": ["mean","max"], "displayMode": "table", "placement": "bottom" },
                   "tooltip": { "mode": "multi" } },
      "targets": [
        { "datasource": { "type": "prometheus", "uid": "Prometheus" },
          "expr": "pm2_process_cpu_percent",
          "legendFormat": "{{name}} CPU %",
          "refId": "A" }
      ],
      "title": "PM2 CPU Usage per App",
      "type": "timeseries"
    },
    {
      "datasource": { "type": "prometheus", "uid": "Prometheus" },
      "fieldConfig": {
        "defaults": { "color": { "mode": "palette-classic" }, "unit": "bytes",
          "custom": { "lineWidth": 2, "fillOpacity": 10 } },
        "overrides": []
      },
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 4 },
      "id": 3,
      "options": { "legend": { "calcs": ["mean","max"], "displayMode": "table", "placement": "bottom" },
                   "tooltip": { "mode": "multi" } },
      "targets": [
        { "datasource": { "type": "prometheus", "uid": "Prometheus" },
          "expr": "pm2_process_memory_bytes",
          "legendFormat": "{{name}} Memory",
          "refId": "A" }
      ],
      "title": "PM2 Memory Usage per App",
      "type": "timeseries"
    },
    {
      "datasource": { "type": "prometheus", "uid": "Prometheus" },
      "fieldConfig": {
        "defaults": { "color": { "mode": "palette-classic" }, "unit": "short",
          "custom": { "lineWidth": 2, "fillOpacity": 10 } },
        "overrides": []
      },
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 12 },
      "id": 4,
      "options": { "legend": { "calcs": ["max"], "displayMode": "table", "placement": "bottom" },
                   "tooltip": { "mode": "multi" } },
      "targets": [
        { "datasource": { "type": "prometheus", "uid": "Prometheus" },
          "expr": "pm2_process_restart_count",
          "legendFormat": "{{name}} Restarts",
          "refId": "A" }
      ],
      "title": "PM2 Restart Count per App",
      "type": "timeseries"
    },
    {
      "datasource": { "type": "prometheus", "uid": "Prometheus" },
      "fieldConfig": {
        "defaults": { "color": { "mode": "palette-classic" }, "unit": "s",
          "custom": { "lineWidth": 2, "fillOpacity": 10 } },
        "overrides": []
      },
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 12 },
      "id": 5,
      "options": { "legend": { "calcs": ["lastNotNull"], "displayMode": "table", "placement": "bottom" },
                   "tooltip": { "mode": "multi" } },
      "targets": [
        { "datasource": { "type": "prometheus", "uid": "Prometheus" },
          "expr": "pm2_process_uptime_seconds",
          "legendFormat": "{{name}} Uptime",
          "refId": "A" }
      ],
      "title": "PM2 App Uptime",
      "type": "timeseries"
    }
  ],
  "refresh": "10s",
  "schemaVersion": 38,
  "tags": ["pm2", "nodejs", "process"],
  "time": { "from": "now-1h", "to": "now" },
  "timepicker": {},
  "timezone": "browser",
  "title": "PM2 Process Monitor",
  "uid": "pm2-process-monitor",
  "version": 1
}
PM2DASH
        chown -R grafana:grafana "$dash_dir" 2>/dev/null || true
        ok "Grafana: PM2 Process Monitor dashboard provisioned."
    else
        ok "Grafana: PM2 dashboard already present."
    fi

    # Start Grafana
    systemctl daemon-reload
    systemctl enable --now grafana-server 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
    ok "Grafana service enabled (127.0.0.1:3001)."
    info "Access Grafana dashboard via SSH tunnel:"
    info "  ssh -L 3001:localhost:3001 $USERNAME@<server-ip>"
    info "  Then open: http://localhost:3001  (default login: admin / admin)"
    info "  ⚠  Change your Grafana password immediately after first login!"

    # ── D. PM2 log rotation module ────────────────────────────────────────────
    if $INSTALL_PM2; then
        su - "$USERNAME" -c "
            export NVM_DIR=\"\$HOME/.nvm\"; source \"\$NVM_DIR/nvm.sh\"
            pm2 install pm2-logrotate 2>/dev/null || true
            pm2 set pm2-logrotate:max_size 50M 2>/dev/null || true
            pm2 set pm2-logrotate:retain 10   2>/dev/null || true
            pm2 set pm2-logrotate:compress true 2>/dev/null || true
        " 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        ok "PM2 log rotation module installed (50MB max, 10 files, compressed)."

        # Install pm2-prometheus-exporter so PM2 process states appear in Grafana
        su - "$USERNAME" -c "
            export NVM_DIR=\"\$HOME/.nvm\"; source \"\$NVM_DIR/nvm.sh\"
            pm2 install pm2-prometheus-exporter 2>/dev/null || true
            pm2 set pm2-prometheus-exporter:port 9209 2>/dev/null || true
        " 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        ok "PM2 Prometheus exporter installed — exposes metrics on 127.0.0.1:9209."
        info "Scrape target added to Prometheus. PM2 apps appear in Grafana automatically."
    fi

    # ── E. Loki — system log backend ──────────────────────────────────────────
    local loki_ver="3.0.0"
    info "Installing Loki v${loki_ver} (log aggregation backend)..."
    if ! command -v loki &>/dev/null; then
        wget -q \
            "https://github.com/grafana/loki/releases/download/v${loki_ver}/loki-linux-${arch}.zip" \
            -O /tmp/loki.zip 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        if [[ -f /tmp/loki.zip ]]; then
            cd /tmp && unzip -q loki.zip "loki-linux-${arch}" 2>/dev/null || true
            if [[ -f "/tmp/loki-linux-${arch}" ]]; then
                mv "/tmp/loki-linux-${arch}" /usr/local/bin/loki
                chmod +x /usr/local/bin/loki
                rm -f /tmp/loki.zip
                ok "Loki binary installed → /usr/local/bin/loki"
            else
                warn "Loki binary not found in archive — install manually from https://github.com/grafana/loki/releases"
            fi
        else
            warn "Loki download failed — install manually from https://github.com/grafana/loki/releases"
        fi
    else
        ok "Loki already installed."
    fi

    useradd --no-create-home --shell /bin/false loki 2>/dev/null || true
    mkdir -p /etc/loki /var/lib/loki
    chown loki:loki /var/lib/loki

    if [[ ! -f /etc/loki/loki.yml ]]; then
        cat > /etc/loki/loki.yml <<'LOKICFG'
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096
  log_level: warn

common:
  instance_addr: 127.0.0.1
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory:  /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100

schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 744h  # 31 days (744 = 31 × 24 hours)
  ingestion_rate_mb: 16
  ingestion_burst_size_mb: 32

compactor:
  working_directory: /var/lib/loki/compactor
  retention_enabled: true
  delete_request_store: filesystem

analytics:
  reporting_enabled: false
LOKICFG
        chown loki:loki /etc/loki/loki.yml
        ok "Loki config written to /etc/loki/loki.yml."
    else
        ok "Loki config already exists."
    fi

    if [[ ! -f /etc/systemd/system/loki.service ]]; then
        cat > /etc/systemd/system/loki.service <<'LOKISVC'
[Unit]
Description=Loki Log Aggregation Service
After=network.target

[Service]
User=loki
Group=loki
Type=simple
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki.yml
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
LOKISVC
        systemctl daemon-reload
        systemctl enable --now loki 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        ok "Loki service enabled (127.0.0.1:3100)."
    else
        ok "Loki service already configured."
    fi

    # ── F. Promtail — log agent (system logs + PM2 logs → Loki) ───────────────
    local promtail_ver="3.0.0"
    info "Installing Promtail v${promtail_ver} (log collection agent)..."
    if ! command -v promtail &>/dev/null; then
        wget -q \
            "https://github.com/grafana/loki/releases/download/v${promtail_ver}/promtail-linux-${arch}.zip" \
            -O /tmp/promtail.zip 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        if [[ -f /tmp/promtail.zip ]]; then
            cd /tmp && unzip -q promtail.zip "promtail-linux-${arch}" 2>/dev/null || true
            if [[ -f "/tmp/promtail-linux-${arch}" ]]; then
                mv "/tmp/promtail-linux-${arch}" /usr/local/bin/promtail
                chmod +x /usr/local/bin/promtail
                rm -f /tmp/promtail.zip
                ok "Promtail binary installed → /usr/local/bin/promtail"
            else
                warn "Promtail binary not found in archive — install manually from https://github.com/grafana/loki/releases"
            fi
        else
            warn "Promtail download failed — install manually from https://github.com/grafana/loki/releases"
        fi
    else
        ok "Promtail already installed."
    fi

    useradd --no-create-home --shell /bin/false promtail 2>/dev/null || true
    usermod -aG adm promtail 2>/dev/null || true   # read /var/log/* files
    mkdir -p /etc/promtail /var/lib/promtail
    chown promtail:promtail /var/lib/promtail

    local pm2_log_dir="/home/${USERNAME}/.pm2/logs"
    if [[ ! -f /etc/promtail/promtail.yml ]]; then
        cat > /etc/promtail/promtail.yml <<PTCFG
server:
  http_listen_port: 9080
  grpc_listen_port: 0
  log_level: warn

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://127.0.0.1:3100/loki/api/v1/push

scrape_configs:

  # ── Syslog ──────────────────────────────────────────────────────────────────
  - job_name: syslog
    static_configs:
      - targets: [localhost]
        labels:
          job:    syslog
          host:   $(hostname)
          __path__: /var/log/syslog
    pipeline_stages:
      - match:
          selector: '{job="syslog"}'
          stages:
            - regex:
                expression: '^(?P<timestamp>\S+\s+\S+\s+\S+)\s+(?P<host>\S+)\s+(?P<process>[^:\[]+)[^\:]*:\s*(?P<message>.*)$'
            - labels:
                process:

  # ── Auth log ─────────────────────────────────────────────────────────────────
  - job_name: auth
    static_configs:
      - targets: [localhost]
        labels:
          job:      auth
          host:     $(hostname)
          __path__: /var/log/auth.log

  # ── Kernel log ───────────────────────────────────────────────────────────────
  - job_name: kern
    static_configs:
      - targets: [localhost]
        labels:
          job:      kern
          host:     $(hostname)
          __path__: /var/log/kern.log

  # ── PM2 app logs ─────────────────────────────────────────────────────────────
  - job_name: pm2
    static_configs:
      - targets: [localhost]
        labels:
          job:      pm2
          host:     $(hostname)
          __path__: ${pm2_log_dir}/*.log
    pipeline_stages:
      - match:
          selector: '{job="pm2"}'
          stages:
            - regex:
                expression: '^(?P<timestamp>\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:\d{2})?)\s+(?P<level>\S+)\s+(?P<message>.*)$'
            - labels:
                level:
PTCFG
        # Allow promtail to read PM2 log directory (requires ACL support on the filesystem)
        if command -v setfacl &>/dev/null; then
            setfacl -m "u:promtail:rx" "/home/${USERNAME}" 2>/dev/null \
                || warn "setfacl failed for /home/${USERNAME} — Promtail may not read PM2 logs."
            setfacl -m "u:promtail:rx" "/home/${USERNAME}/.pm2" 2>/dev/null \
                || warn "setfacl failed for /home/${USERNAME}/.pm2 — Promtail may not read PM2 logs."
            setfacl -m "u:promtail:rx" "${pm2_log_dir}" 2>/dev/null \
                || warn "setfacl failed for ${pm2_log_dir} — Promtail may not read PM2 logs."
        else
            warn "setfacl not available — install 'acl' package so Promtail can access PM2 log dir."
        fi
        chown promtail:promtail /etc/promtail/promtail.yml
        ok "Promtail config written to /etc/promtail/promtail.yml."
        info "Collecting: syslog, auth.log, kern.log, PM2 app logs."
    else
        ok "Promtail config already exists."
    fi

    if [[ ! -f /etc/systemd/system/promtail.service ]]; then
        cat > /etc/systemd/system/promtail.service <<'PTSVC'
[Unit]
Description=Promtail Log Collection Agent
After=network.target loki.service

[Service]
User=promtail
Group=promtail
Type=simple
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail.yml
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
PTSVC
        systemctl daemon-reload
        systemctl enable --now promtail 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        ok "Promtail service enabled — collecting system logs + PM2 app logs."
    else
        ok "Promtail service already configured."
    fi

    # Restart Grafana to pick up the new Loki datasource and PM2 dashboard
    systemctl restart grafana-server 2>/dev/null || true
    ok "Grafana restarted — Loki datasource + PM2 dashboard now active."

    # ── G. server_status — quick CLI overview script ──────────────────────────
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

# ── Log Pipeline (Loki + Promtail) ───────────────────────────────────────────
echo ""
echo -e "  \${BOLD}\${WHT}Log Pipeline\${R}"
if systemctl is-active --quiet loki 2>/dev/null; then
    echo -e "  \${GRN}✔\${R}  Loki running    (log backend  127.0.0.1:3100)"
else
    echo -e "  \${RED}✘\${R}  Loki not running  (sudo systemctl start loki)"
fi
if systemctl is-active --quiet promtail 2>/dev/null; then
    echo -e "  \${GRN}✔\${R}  Promtail running (log agent   127.0.0.1:9080)"
else
    echo -e "  \${RED}✘\${R}  Promtail not running  (sudo systemctl start promtail)"
fi

# ── Grafana Dashboard ─────────────────────────────────────────────────────────
echo ""
echo -e "  \${BOLD}\${WHT}Monitoring Dashboard (Grafana + Prometheus)\${R}"
if systemctl is-active --quiet grafana-server 2>/dev/null; then
    echo -e "  \${GRN}✔\${R}  Grafana running — access via SSH tunnel:"
    echo -e "  \${GRY}     ssh -L 3001:localhost:3001 ${deploy_user}@<server-ip>\${R}"
    echo -e "  \${GRY}     Then open: http://localhost:3001\${R}"
else
    echo -e "  \${GRY}  Grafana not running (sudo systemctl start grafana-server)\${R}"
fi
if systemctl is-active --quiet prometheus 2>/dev/null; then
    echo -e "  \${GRN}✔\${R}  Prometheus running (127.0.0.1:9090)"
else
    echo -e "  \${GRY}  Prometheus not running (sudo systemctl start prometheus)\${R}"
fi
if systemctl is-active --quiet node_exporter 2>/dev/null; then
    echo -e "  \${GRN}✔\${R}  node_exporter running (127.0.0.1:9100)"
else
    echo -e "  \${GRY}  node_exporter not running (sudo systemctl start node_exporter)\${R}"
fi

echo ""
echo -e "  \${GRY}\${HR}\${R}"
echo -e "  \${GRY}PM2 live: pm2 monit  │  App logs: pm2 logs  │  System logs: Grafana → Loki datasource\${R}"
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
#  10 — KERNEL HARDENING
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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
#  11 — FAIL2BAN
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_fail2ban() {
    section "11" "fail2ban — Brute Force Protection"

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
#  12 — UFW
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_firewall() {
    $GEN_FW || { section "12" "UFW"; warn "Skipped."; section_end; return; }

    section "12" "UFW Firewall"

    if ! command -v ufw &>/dev/null; then
        warn "UFW not installed: apt-get install -y ufw"; section_end; return
    fi

    run "ufw default deny incoming"
    run "ufw default allow outgoing"
    run "ufw allow 22/tcp   comment 'SSH'"
    # Monitoring ports (9090/9100/3001) are bound to 127.0.0.1 — no UFW rule needed

    ufw --force enable 2>/dev/null || true

    ok "UFW active: SSH(22) open. Allow other ports as needed."
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

    ok "Logrotate: PM2 logs 14-day retention, daily rotation, compressed."

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  14 — SUMMARY
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
    _row "Monitoring"     "server_status  ·  pm2 monit  ·  Grafana :3001  ·  Loki :3100"

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
        "Grafana dashboard (system metrics + PM2 + logs — all in one):"
        "  ssh -L 3001:localhost:3001 ${USERNAME}@<server-ip>"
        "  → http://localhost:3001  (admin/admin — change on first login)"
        "  Dashboards: System → Node Exporter Full | Apps → PM2 Process Monitor"
        "  Logs:       Explore → select Loki → query {job='pm2'} or {job='syslog'}"
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
    setup_shell         # 05 — aliases, NVM, PM2
    install_git         # 06
    install_node        # 07
    install_pm2         # 08 — bulletproof
    setup_monitoring    # 09 — Prometheus + Grafana + PM2 logrotate + server_status
    harden_kernel       # 10
    setup_fail2ban      # 11
    setup_firewall      # 12
    setup_logrotate     # 13
    print_summary       # 14

    _log INFO "=== Provisioning complete. User=$USERNAME ==="
}

main "$@"