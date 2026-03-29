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
# ║      + Loki (log backend) + Promtail (log agent)                             ║
# ║      + ClickHouse (2-day analytics) + status script                          ║
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
    clear
    echo ""
    echo -e "${PRP}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${PRP}${BOLD}║${R}  ${CYN}${BOLD}%-74s${R}${PRP}${BOLD}║${R}\n" \
            "⚡  init.sh  —  Node.js Production Server Provisioner  v${SCRIPT_VERSION}"
    printf  "  ${PRP}${BOLD}║${R}  ${GRY}%-74s${R}${PRP}${BOLD}║${R}\n" \
            "Ubuntu 20.04 / 22.04 / 24.04 LTS  ·  Git · NVM · Node.js · PM2 · Grafana"
    echo -e "${PRP}${BOLD}  ╠${HR2}╣${R}"
    printf  "  ${PRP}${BOLD}║${R}  ${GRN}%-14s${R}${GRY}%-62s${R}${PRP}${BOLD}║${R}\n" \
            "  Interactive" "sudo ./init.sh"
    printf  "  ${PRP}${BOLD}║${R}  ${GRN}%-14s${R}${GRY}%-62s${R}${PRP}${BOLD}║${R}\n" \
            "  With flags " "sudo ./init.sh -u <user> -n 20"
    echo -e "${PRP}${BOLD}  ╠${HR2}╣${R}"
    printf  "  ${PRP}${BOLD}║${R}  ${DIM}${GRY}%-74s${R}${PRP}${BOLD}║${R}\n" \
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
    printf  "  ${PRP}${BOLD}║${R}  ${CYN}${BOLD}%-74s${R}${PRP}${BOLD}║${R}\n" \
            "⚡  init.sh  —  Node.js Production Server Provisioner  v${SCRIPT_VERSION}"
    printf  "  ${PRP}${BOLD}║${R}  ${DIM}${GRY}%-74s${R}${PRP}${BOLD}║${R}\n" \
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
        "    --no-nvm"   "Skip NVM + Node.js installation" \
        "    --no-pm2"   "Skip PM2 installation" \
        "    --no-fw"    "Skip UFW firewall configuration" \
        "    --no-mon"   "Skip Grafana/Prometheus monitoring installation" \
        "-h  --help"     "Show this help and exit"
    echo ""
    echo -e "  ${BOLD}${WHT}Examples${R}"
    echo -e "  ${PRP}${DIM}${HR:0:60}${R}"
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
    printf  "  ${PRP}${BOLD}║${R}  ${WHT}${BOLD}%-74s${R}${PRP}${BOLD}║${R}\n" \
            "⚙   Interactive Setup Wizard"
    printf  "  ${PRP}${BOLD}║${R}  ${GRY}%-74s${R}${PRP}${BOLD}║${R}\n" \
            "Answer each prompt below.  Press Enter to accept any default value."
    echo -e "${PRP}${BOLD}  ╚${HR2}╝${R}"

    # ══════════════════════════════════════════════════════════════════════════
    # STEP 1 — Username
    # ══════════════════════════════════════════════════════════════════════════
    if [[ -z "$USERNAME" ]]; then
        _step 1 3 "Deploy Username"
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
    _step 4 4 "Additional Firewall Ports"
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
    # CONFIRMATION SUMMARY
    # ══════════════════════════════════════════════════════════════════════════
    echo ""
    echo -e "${PRP}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${PRP}${BOLD}║${R}${WHT}${BOLD}%-76s${R}${PRP}${BOLD}║${R}\n" \
            "  📋  Configuration Summary — Please Review"
    echo -e "${PRP}${BOLD}  ╠${HR2}╣${R}"
    _conf_row() {
        printf "  ${PRP}${BOLD}║${R}  ${GRY}%-18s${R}  ${WHT}${BOLD}%-52s${R}  ${PRP}${BOLD}║${R}\n" "$1" "$2"
    }
    _conf_row "Username"    "$USERNAME"
    _conf_row "Password"    "$([ -n "$CUSTOM_PASS" ] && echo "custom (hidden)" || echo "will be auto-generated")"
    _conf_row "Node.js"     "v${NODE_VER}  (via NVM ${NVM_VERSION})"
    _conf_row "NVM"         "$(  $INSTALL_NVM && echo "✔ install" || echo "– skip (--no-nvm)")"
    _conf_row "PM2"         "$(  $INSTALL_PM2 && echo "✔ install" || echo "– skip (--no-pm2)")"
    _conf_row "UFW"         "$(  $GEN_FW      && echo "✔ configure" || echo "– skip (--no-fw)")"
    _conf_row "Firewall"    "SSH + $( [[ "$OPEN_NGINX_PORTS" == true ]] && echo "Nginx " ; [[ "$OPEN_EMAIL_PORTS" == true ]] && echo "Email " ; [[ -n "$CUSTOM_PORTS" ]] && echo "Custom " ; echo "")"
    _conf_row "Monitoring"  "$( $SETUP_MON   && echo "✔ Prometheus · Grafana · Loki · ClickHouse · PM2" || echo "– skip (--no-mon)")"
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

# ── ClickHouse log queries (centralized logging) ──────────────────
# Query PM2 logs from ClickHouse instead of local files
ch_logs_pm2() {
    local app="${1:-}"
    local limit="${2:-50}"
    local query
    
    if [[ -z "$app" ]]; then
        query="SELECT timestamp, app_name, log_level, message FROM pm2_logs.logs WHERE log_type='pm2' ORDER BY timestamp DESC LIMIT $limit FORMAT PrettyCompact"
    else
        query="SELECT timestamp, app_name, log_level, message FROM pm2_logs.logs WHERE log_type='pm2' AND app_name='$app' ORDER BY timestamp DESC LIMIT $limit FORMAT PrettyCompact"
    fi
    
    clickhouse-client --query "$query" 2>/dev/null || echo "ClickHouse not responding"
}

# Query ClickHouse errors (all apps)
ch_logs_errors() {
    local app="${1:-}"
    local limit="${2:-50}"
    local query
    
    if [[ -z "$app" ]]; then
        query="SELECT timestamp, app_name, log_level, message FROM pm2_logs.logs WHERE log_level='ERROR' ORDER BY timestamp DESC LIMIT $limit FORMAT PrettyCompact"
    else
        query="SELECT timestamp, app_name, log_level, message FROM pm2_logs.logs WHERE log_level='ERROR' AND app_name='$app' ORDER BY timestamp DESC LIMIT $limit FORMAT PrettyCompact"
    fi
    
    clickhouse-client --query "$query" 2>/dev/null || echo "ClickHouse not responding"
}

# View system logs in ClickHouse
ch_logs_system() {
    local limit="${1:-50}"
    clickhouse-client --query "SELECT timestamp, log_type, message FROM pm2_logs.system_logs ORDER BY timestamp DESC LIMIT $limit FORMAT PrettyCompact" 2>/dev/null || echo "ClickHouse not responding"
}

# View Nginx logs in ClickHouse
ch_logs_nginx() {
    local limit="${1:-50}"
    clickhouse-client --query "SELECT timestamp, http_status, request_method, request_path, response_time_ms FROM pm2_logs.nginx_logs ORDER BY timestamp DESC LIMIT $limit FORMAT PrettyCompact" 2>/dev/null || echo "ClickHouse not responding"
}

# Get log count (storage analysis)
ch_logs_stats() {
    echo "ClickHouse Log Statistics:"
    echo ""
    clickhouse-client --query "SELECT 'PM2 logs' as source, COUNT() as count, ROUND(SUM(1)/1024/1024, 2) as size_mb FROM pm2_logs.pm2_logs UNION ALL SELECT 'System logs', COUNT(), ROUND(SUM(1)/1024/1024, 2) FROM pm2_logs.system_logs UNION ALL SELECT 'Nginx logs', COUNT(), ROUND(SUM(1)/1024/1024, 2) FROM pm2_logs.nginx_logs FORMAT PrettyCompact" 2>/dev/null || echo "ClickHouse not responding"
}

# ── ClickHouse shortcuts ──────────────────────────────────────────
alias ch_pm2='ch_logs_pm2'                    # View PM2 logs
alias ch_errors='ch_logs_errors'              # View errors
alias ch_system='ch_logs_system'              # View system logs
alias ch_nginx='ch_logs_nginx'                # View nginx logs
alias ch_stats='ch_logs_stats'                # Log statistics
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
#  09 — MONITORING
#
#  Five layers:
#    A. node_exporter  — system metrics collector (CPU, RAM, disk, network)
#    B. Prometheus     — metrics database (15-day retention)
#    C. Grafana        — beautiful real-time browser dashboard (port 13001)
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
        cat > /etc/prometheus/prometheus.yml <<PROMCFG
global:
  scrape_interval:     15s
  evaluation_interval: 15s
  external_labels:
    environment: 'production'
    job_origin: 'init.sh'

alerting:
  alertmanagers: []

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['127.0.0.1:9100']
    scrape_interval: 30s
    scrape_timeout: 10s
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: 'go_.*'
        action: drop

  - job_name: 'pm2'
    scrape_interval: 10s
    scrape_timeout: 5s
    static_configs:
      - targets: ['127.0.0.1:9209']
        labels:
          instance: pm2_apps
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: 'process_.*|go_.*'
        action: drop
PROMCFG
        # Validate config with promtool if available
        if command -v promtool &>/dev/null; then
            if promtool check config /etc/prometheus/prometheus.yml &>/dev/null; then
                ok "Prometheus config validated."
            else
                warn "Prometheus config validation failed — check /etc/prometheus/prometheus.yml"
            fi
        fi
        chown prometheus:prometheus /etc/prometheus/prometheus.yml
        ok "Prometheus config written to /etc/prometheus/prometheus.yml."
    else
        # Patch existing config to add PM2 exporter job if not present
        if ! grep -q "job_name: 'pm2'" /etc/prometheus/prometheus.yml 2>/dev/null; then
            cat >> /etc/prometheus/prometheus.yml <<PROMPM2

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
After=network-online.target node-exporter.service
Wants=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus/ \
    --web.listen-address=127.0.0.1:9090 \
    --web.enable-lifecycle \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --storage.tsdb.retention.time=15d
Restart=always
RestartSec=10
StartLimitInterval=60s
StartLimitBurst=3
HealthCheck=/bin/bash -c 'curl -sf http://127.0.0.1:9090/-/healthy || exit 1'

[Install]
WantedBy=multi-user.target
PROMSVC
        systemctl daemon-reload
        systemctl enable node-exporter 2>/dev/null || true
        systemctl enable --now prometheus 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        sleep 3  # Wait for Prometheus to be ready
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

    # Configure Grafana: bind to localhost only, port 13001
    # (uncommon port to avoid conflicts with Node.js apps and other services)
    if [[ -f /etc/grafana/grafana.ini ]]; then
        sed -i 's/^;*\s*http_port\s*=.*/http_port = 13001/'     /etc/grafana/grafana.ini 2>/dev/null || true
        sed -i 's/^;*\s*http_addr\s*=.*/http_addr = 127.0.0.1/' /etc/grafana/grafana.ini 2>/dev/null || true
        ok "Grafana: configured to listen on 127.0.0.1:13001."
    fi

    # Provision Prometheus as the default Grafana data source
    mkdir -p /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards
    
    # Create dashboard providers for organized folders
    cat > /etc/grafana/provisioning/dashboards/system.yaml <<SYSPROV
apiVersion: 1
providers:
  - name: 'System Dashboards'
    orgId: 1
    folder: 'System'
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards/system
SYSPROV
    chown grafana:grafana /etc/grafana/provisioning/dashboards/system.yaml 2>/dev/null || true
    
    cat > /etc/grafana/provisioning/dashboards/applications.yaml <<APPPROV
apiVersion: 1
providers:
  - name: 'Application Dashboards'
    orgId: 1
    folder: 'Applications'
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards/applications
APPPROV
    chown grafana:grafana /etc/grafana/provisioning/dashboards/applications.yaml 2>/dev/null || true
    
    # Create dashboard directories
    mkdir -p /var/lib/grafana/dashboards/system /var/lib/grafana/dashboards/applications 2>/dev/null || true
    
    ok "Grafana dashboard folders created (System, Applications, Logs)."
    if [[ ! -f /etc/grafana/provisioning/datasources/prometheus.yaml ]]; then
        cat > /etc/grafana/provisioning/datasources/prometheus.yaml <<'GFDS'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    uid: Prometheus
    url: http://127.0.0.1:9090
    access: proxy
    isDefault: true
    editable: false
GFDS
        chown grafana:grafana /etc/grafana/provisioning/datasources/prometheus.yaml 2>/dev/null || true
        ok "Grafana: Prometheus data source provisioned."
    else
        # Patch uid into existing file if missing (fixes installs from before this version)
        if ! grep -q "uid: Prometheus" /etc/grafana/provisioning/datasources/prometheus.yaml 2>/dev/null; then
            sed -i '/type: prometheus/a\    uid: Prometheus' /etc/grafana/provisioning/datasources/prometheus.yaml 2>/dev/null || true
            ok "Grafana: Prometheus data source uid patched."
        else
            ok "Grafana: Prometheus data source already provisioned."
        fi
    fi

    # Provision Loki as a Grafana data source (added after Loki is installed later)
    if [[ ! -f /etc/grafana/provisioning/datasources/loki.yaml ]]; then
        cat > /etc/grafana/provisioning/datasources/loki.yaml <<'GFLO'
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    uid: Loki
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
        # Patch uid into existing file if missing
        if ! grep -q "uid: Loki" /etc/grafana/provisioning/datasources/loki.yaml 2>/dev/null; then
            sed -i '/type: loki/a\    uid: Loki' /etc/grafana/provisioning/datasources/loki.yaml 2>/dev/null || true
            ok "Grafana: Loki data source uid patched."
        else
            ok "Grafana: Loki data source already provisioned."
        fi
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
      path: /var/lib/grafana/dashboards/system
GFDB
        chown grafana:grafana /etc/grafana/provisioning/dashboards/node_exporter.yaml 2>/dev/null || true
        ok "Grafana System dashboard provider provisioned."
    fi

    # Provision PM2 Process Monitor dashboard (Applications folder)
    cat > /var/lib/grafana/dashboards/applications/01-pm2-process-monitor.json <<'PM2DASH'
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
            { "options": { "0": { "color": "red",   "index": 0, "text": "offline" },
                           "1": { "color": "green", "index": 1, "text": "online"  } },
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
          "expr": "pm2_up",
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
          "expr": "pm2_cpu",
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
          "expr": "pm2_memory",
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
          "expr": "pm2_restarts",
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
          "expr": "pm2_uptime",
          "legendFormat": "{{name}} Uptime",
          "refId": "A" }
      ],
      "title": "PM2 App Uptime",
      "type": "timeseries"
    },
    {
      "datasource": { "type": "prometheus", "uid": "Prometheus" },
      "fieldConfig": {
        "defaults": { "color": { "mode": "palette-classic" }, "unit": "short",
          "custom": { "lineWidth": 2, "fillOpacity": 10 } },
        "overrides": []
      },
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 20 },
      "id": 6,
      "options": { "legend": { "calcs": ["lastNotNull"], "displayMode": "table", "placement": "bottom" },
                   "tooltip": { "mode": "multi" } },
      "targets": [
        { "datasource": { "type": "prometheus", "uid": "Prometheus" },
          "expr": "pm2_instances",
          "legendFormat": "{{name}} Instances",
          "refId": "A" }
      ],
      "title": "PM2 App Instances",
      "type": "timeseries"
    }
  ],
  "refresh": "10s",
  "schemaVersion": 38,
  "tags": ["pm2", "nodejs", "process"],
  "time": { "from": "now-1h", "to": "now" },
  "timepicker": {},
  "timezone": "browser",
  "title": "⚙️ PM2 — Process Monitor",
  "description": "Real-time PM2 app monitoring: status, CPU, memory, uptime, restart counts",
  "uid": "pm2-process-monitor",
  "version": 2,
  "style": "dark"
}
PM2DASH
    chmod 644 /var/lib/grafana/dashboards/applications/01-pm2-process-monitor.json
    ok "✓ PM2 Process Monitor — Real-time PM2 app monitoring (status, CPU, memory, uptime, restart counts)"

    # ─── Applications Folder: Dashboard 2 ─────────────────────────────────────
    # Provision application logs dashboard (Applications folder)
    cat > /var/lib/grafana/dashboards/applications/02-app-logs.json <<'APPLOGS'
{
  "annotations": { "list": [] },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "id": null,
  "links": [],
  "panels": [
    {
      "datasource": { "type": "loki", "uid": "Loki" },
      "description": "All PM2 application output logs",
      "fieldConfig": { "defaults": {}, "overrides": [] },
      "gridPos": { "h": 10, "w": 24, "x": 0, "y": 0 },
      "id": 1,
      "options": {
        "dedupStrategy": "none",
        "enableLogDetails": true,
        "prettifyLogMessage": true,
        "showCommonLabels": false,
        "showLabels": true,
        "showTime": true,
        "sortOrder": "Descending",
        "wrapLogMessage": true
      },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "{job=\"pm2\"}",
          "legendFormat": "",
          "refId": "A" }
      ],
      "title": "PM2 App Output Logs",
      "type": "logs"
    },
    {
      "datasource": { "type": "loki", "uid": "Loki" },
      "description": "Web server access and error logs",
      "fieldConfig": { "defaults": {}, "overrides": [] },
      "gridPos": { "h": 10, "w": 24, "x": 0, "y": 10 },
      "id": 2,
      "options": {
        "dedupStrategy": "none",
        "enableLogDetails": true,
        "prettifyLogMessage": false,
        "showCommonLabels": false,
        "showLabels": true,
        "showTime": true,
        "sortOrder": "Descending",
        "wrapLogMessage": true
      },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "{job=\"nginx\"}",
          "legendFormat": "",
          "refId": "A" }
      ],
      "title": "Nginx Access & Error Logs",
      "type": "logs"
    }
  ],
  "refresh": "30s",
  "schemaVersion": 38,
  "tags": ["logs", "loki", "applications"],
  "time": { "from": "now-1h", "to": "now" },
  "timepicker": {},
  "timezone": "browser",
  "title": "📋 Applications — Log Viewer",
  "description": "Real-time application logs from Loki (PM2 and Nginx)",
  "uid": "app-logs",
  "version": 1,
  "style": "dark"
}
APPLOGS
    chmod 644 /var/lib/grafana/dashboards/applications/02-app-logs.json
    ok "✓ Applications — Log Viewer — PM2 app output + Nginx access/error logs"

    # ─── System Folder: System Logs Dashboard ────────────────────────────────
    cat > /var/lib/grafana/dashboards/system/01-system-logs.json <<'SYSLOGS'
{
  "annotations": { "list": [] },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "id": null,
  "links": [],
  "panels": [
    {
      "datasource": { "type": "loki", "uid": "Loki" },
      "description": "System messages and kernel logs",
      "fieldConfig": { "defaults": {}, "overrides": [] },
      "gridPos": { "h": 8, "w": 24, "x": 0, "y": 0 },
      "id": 1,
      "options": {
        "dedupStrategy": "none",
        "enableLogDetails": true,
        "prettifyLogMessage": false,
        "showCommonLabels": false,
        "showLabels": true,
        "showTime": true,
        "sortOrder": "Descending",
        "wrapLogMessage": true
      },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "{job=\"syslog\"}",
          "legendFormat": "",
          "refId": "A" }
      ],
      "title": "System Logs (syslog)",
      "type": "logs"
    },
    {
      "datasource": { "type": "loki", "uid": "Loki" },
      "description": "Authentication and sudo logs",
      "fieldConfig": { "defaults": {}, "overrides": [] },
      "gridPos": { "h": 8, "w": 24, "x": 0, "y": 8 },
      "id": 2,
      "options": {
        "dedupStrategy": "none",
        "enableLogDetails": true,
        "prettifyLogMessage": false,
        "showCommonLabels": false,
        "showLabels": true,
        "showTime": true,
        "sortOrder": "Descending",
        "wrapLogMessage": true
      },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "{job=\"auth\"}",
          "legendFormat": "",
          "refId": "A" }
      ],
      "title": "Authentication Logs (auth)",
      "type": "logs"
    },
    {
      "datasource": { "type": "loki", "uid": "Loki" },
      "description": "Kernel and driver logs",
      "fieldConfig": { "defaults": {}, "overrides": [] },
      "gridPos": { "h": 8, "w": 24, "x": 0, "y": 16 },
      "id": 3,
      "options": {
        "dedupStrategy": "none",
        "enableLogDetails": true,
        "prettifyLogMessage": false,
        "showCommonLabels": false,
        "showLabels": true,
        "showTime": true,
        "sortOrder": "Descending",
        "wrapLogMessage": false
      },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "{job=\"kern\"}",
          "legendFormat": "",
          "refId": "A" }
      ],
      "title": "Kernel Logs (kern)",
      "type": "logs"
    }
  ],
  "refresh": "30s",
  "schemaVersion": 38,
  "tags": ["logs", "loki", "system"],
  "time": { "from": "now-1h", "to": "now" },
  "timepicker": {},
  "timezone": "browser",
  "title": "🖥️  System — Log Viewer",
  "description": "System-level logs from Loki (syslog, auth, kernel)",
  "uid": "system-logs",
  "version": 1,
  "style": "dark"
}
SYSLOGS
    chmod 644 /var/lib/grafana/dashboards/system/01-system-logs.json
    ok "✓ System — Log Viewer — System-level logs (syslog, auth, kernel)"

    # ─── Applications Folder: Log Explorer ────────────────────────────────────
    cat > /var/lib/grafana/dashboards/applications/03-loki-explorer.json <<'LOGDASH'
{
  "annotations": { "list": [] },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "id": null,
  "links": [],
  "panels": [
    {
      "datasource": { "type": "loki", "uid": "Loki" },
      "fieldConfig": { "defaults": {}, "overrides": [] },
      "gridPos": { "h": 12, "w": 24, "x": 0, "y": 0 },
      "id": 1,
      "options": {
        "dedupStrategy": "none",
        "enableLogDetails": true,
        "prettifyLogMessage": false,
        "showCommonLabels": false,
        "showLabels": true,
        "showTime": true,
        "sortOrder": "Descending",
        "wrapLogMessage": true
      },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "{job=\"pm2\"}",
          "legendFormat": "",
          "refId": "A" }
      ],
      "title": "PM2 App Logs",
      "type": "logs"
    },
    {
      "datasource": { "type": "loki", "uid": "Loki" },
      "fieldConfig": { "defaults": {}, "overrides": [] },
      "gridPos": { "h": 8, "w": 24, "x": 0, "y": 12 },
      "id": 2,
      "options": {
        "dedupStrategy": "none",
        "enableLogDetails": true,
        "prettifyLogMessage": false,
        "showCommonLabels": false,
        "showLabels": true,
        "showTime": true,
        "sortOrder": "Descending",
        "wrapLogMessage": true
      },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "{job=\"nginx\"}",
          "legendFormat": "",
          "refId": "A" }
      ],
      "title": "Nginx Logs",
      "type": "logs"
    },
    {
      "datasource": { "type": "loki", "uid": "Loki" },
      "fieldConfig": { "defaults": {}, "overrides": [] },
      "gridPos": { "h": 8, "w": 24, "x": 0, "y": 20 },
      "id": 3,
      "options": {
        "dedupStrategy": "none",
        "enableLogDetails": true,
        "prettifyLogMessage": false,
        "showCommonLabels": false,
        "showLabels": true,
        "showTime": true,
        "sortOrder": "Descending",
        "wrapLogMessage": false
      },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "{job=~\"syslog|auth|kern\"}",
          "legendFormat": "",
          "refId": "A" }
      ],
      "title": "System Logs (syslog / auth / kern)",
      "type": "logs"
    }
  ],
  "refresh": "30s",
  "schemaVersion": 38,
  "tags": ["logs", "loki", "pm2", "nginx"],
  "time": { "from": "now-1h", "to": "now" },
  "timepicker": {},
  "timezone": "browser",
  "title": "Log Explorer",
  "uid": "log-explorer",
  "version": 1
}
LOGDASH
    chmod 644 /var/lib/grafana/dashboards/applications/03-loki-explorer.json
    ok "✓ Loki — Log Explorer — Free-form log query explorer for debugging & analysis"

    info ""
    info "════════════════════════════════════════════════════════════════"
    info "📊 GRAFANA DASHBOARD STRUCTURE — PER-APP & PER-CONTAINER"
    info "════════════════════════════════════════════════════════════════"
    info ""
    info "📁 SYSTEM FOLDER (/var/lib/grafana/dashboards/system/)"
    info "   └─ 🖥️  System — Log Viewer"
    info "      ├─ System Messages & Kernel Logs (syslog)"
    info "      ├─ Authentication & Sudo Activity (auth)"
    info "      └─ Kernel & Driver Logs (kern)"
    info ""
    info "📁 APPLICATIONS FOLDER — PER-APP MONITORING SUITE"
    info "   (/var/lib/grafana/dashboards/applications/)"
    info "   │"
    info "   ├─ 🎯 TEMPLATES (Use as base for each app):"
    info "   │  ├─ Template — App Metrics & Status"
    info "   │  │  ├─ Real-time app status (online/offline)"
    info "   │  │  ├─ CPU usage for selected app"
    info "   │  │  ├─ Memory usage for selected app"
    info "   │  │  ├─ Restart counts & reliability"
    info "   │  │  └─ Uptime & instance tracking"
    info "   │  │"
    info "   │  ├─ Template — App Logs & Activity"
    info "   │  │  ├─ Application output logs"
    info "   │  │  ├─ Application error logs"
    info "   │  │  ├─ Nginx logs for app"
    info "   │  │  └─ Request patterns & trends"
    info "   │  │"
    info "   │  ├─ Template — App Errors & Health"
    info "   │  │  ├─ Error count & rate for app"
    info "   │  │  ├─ Error trends over time"
    info "   │  │  ├─ Error distribution by type"
    info "   │  │  └─ Health score computation"
    info "   │  │"
    info "   │  └─ 🔍 Loki — Log Explorer (search all apps)"
    info "   │     └─ Free-form log queries across all data"
    info ""
    info "📁 DOCKER FOLDER — PER-CONTAINER MONITORING SUITE"
    info "   (/var/lib/grafana/dashboards/docker/)"
    info "   │"
    info "   ├─ 🎯 TEMPLATES (Use as base for each container):"
    info "   │  ├─ Template — Container Metrics & Status"
    info "   │  │  ├─ Container running status"
    info "   │  │  ├─ CPU & memory metrics"
    info "   │  │  ├─ Memory limit & utilization %"
    info "   │  │  ├─ Restart counts"
    info "   │  │  └─ Uptime tracking"
    info "   │  │"
    info "   │  ├─ Template — Container Logs & Activity"
    info "   │  │  ├─ Application logs from container"
    info "   │  │  ├─ Error and warning logs"
    info "   │  │  ├─ Log volume trends"
    info "   │  │  └─ Error rate metrics"
    info "   │  │"
    info "   │  └─ Template — Container Network & Disk I/O"
    info "   │     ├─ Network received/transmitted (MB/s)"
    info "   │     ├─ Disk reads/writes (MB/s)"
    info "   │     ├─ Network packets and errors"
    info "   │     └─ I/O performance tracking"
    info ""
    info "📁 LOGS FOLDER (/var/lib/grafana/dashboards/logs/)"
    info "   ├─ 📊 Logs — Overview (all apps aggregate)"
    info "   ├─ ⚠️  Logs — Error Analysis (all apps aggregate)"
    info "   └─ 💚 Logs — App Health (all apps aggregate)"
    info ""
    info "════════════════════════════════════════════════════════════════"
    info "🎯 HOW TO USE:"
    info ""
    info "   📌 FOR APPLICATIONS (PM2 processes):"
    info "      1. Start with a template dashboard (01-03 in Applications)"
    info "      2. Duplicate it in Grafana for each of your apps"
    info "      3. Edit the app_name variable to match your PM2 process name"
    info "      4. Save with your app name as the dashboard title"
    info ""
    info "   🐳 FOR DOCKER CONTAINERS:"
    info "      1. Start with a template dashboard (01-03 in Docker)"
    info "      2. Duplicate it in Grafana for each of your containers"
    info "      3. Edit the container_name variable to match your container name"
    info "      4. Save with your container name as the dashboard title"
    info ""
    info "📌 QUICK NAVIGATION:"
    info "   • Single app metrics?        → Duplicate 01-template-app-metrics.json"
    info "   • Single app logs?           → Duplicate 02-template-app-logs.json"
    info "   • Single app errors?         → Duplicate 03-template-app-errors.json"
    info "   • Single container metrics?  → Duplicate 01-template-container-metrics.json"
    info "   • Single container logs?     → Duplicate 02-template-container-logs.json"
    info "   • Container network/disk?    → Duplicate 03-template-container-io.json"
    info "   • Compare multiple apps?     → Use Logs folder (system-wide aggregate)"
    info "   • Free-form log search?      → Use Loki — Log Explorer"
    info "════════════════════════════════════════════════════════════════"
    info ""

    # ── D. PM2 logging configuration & log rotation ───────────────────────────
    if $INSTALL_PM2; then
        # 1. Enhanced PM2 logging format with timestamps
        su - "$USERNAME" -c "
            export NVM_DIR=\"\$HOME/.nvm\"; source \"\$NVM_DIR/nvm.sh\"
            pm2 config set module_conf \"{\\\"pm2-logrotate\\\":{\\\"max_size\\\":\\\"50M\\\",\\\"retain\\\":10,\\\"compress\\\":true,\\\"cron\\\":\\\"0 0 * * *\\\"}}\" 2>/dev/null || true
        " 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true

        # 2. Install pm2-logrotate for automatic log rotation
        su - "$USERNAME" -c "
            export NVM_DIR=\"\$HOME/.nvm\"; source \"\$NVM_DIR/nvm.sh\"
            pm2 install pm2-logrotate 2>/dev/null || true
            pm2 set pm2-logrotate:max_size 50M 2>/dev/null || true
            pm2 set pm2-logrotate:retain 10   2>/dev/null || true
            pm2 set pm2-logrotate:compress true 2>/dev/null || true
            pm2 set pm2-logrotate:cron '0 0 * * *' 2>/dev/null || true
            pm2 set pm2-logrotate:dateFormat 'YYYY-MM-DD_HH-mm-ss' 2>/dev/null || true
        " 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        ok "PM2 log rotation module installed:"
        echo -e "  ${GRY}   • Max size: 50MB per log file${R}"
        echo -e "  ${GRY}   • Retention: 10 rotated files${R}"
        echo -e "  ${GRY}   • Compression: enabled${R}"
        echo -e "  ${GRY}   • Daily rotation: 00:00 UTC${R}"

        # 3. Create global PM2 default config file for auto-logging
        local pm2_home="/home/${USERNAME}/.pm2"
        mkdir -p "$pm2_home"
        
        cat > "$pm2_home/conf.js" <<'PM2CONF'
// PM2 Global Configuration
// Automatically applied to ALL pm2 start commands
module.exports = {
  // Default logging behavior for any app started
  apps: [],
  
  // Global defaults (inherited by all apps)
  default_options: {
    // Log file paths — auto-created with app name
    output: null,          // Set dynamically per app
    error: null,           // Set dynamically per app
    log: null,             // Combined logs
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    
    // Core settings
    autorestart: true,
    max_restarts: 10,
    min_uptime: '10s',
    max_memory_restart: '500M',
    
    // Ensure stdout/stderr captured
    merge_logs: false,
    
    // Don't watch node_modules
    ignore_watch: ['node_modules', '.git', 'logs', 'dist']
  }
};
PM2CONF
        chown "$USERNAME:$USERNAME" "$pm2_home/conf.js"
        ok "PM2 global config created (auto-applies to all apps)."

        # 4. Create auto-logging wrapper helper script
        local pm2_bin
        pm2_bin=$(su - "$USERNAME" -c 'export NVM_DIR="$HOME/.nvm"; source "$NVM_DIR/nvm.sh"; which pm2' 2>/dev/null || echo "")
        
        if [[ -n "$pm2_bin" ]]; then
            cat > "$pm2_home/pm2-start-logs.sh" <<'PM2STARTSCRIPT'
#!/bin/bash
# pm2-start-logs.sh — PM2 app start with AUTOMATIC detailed logging
# 
# Usage:
#   pm2-start-logs app.js                    # Auto: app-out.log + app-error.log
#   pm2-start-logs app.js --name myapp       # Auto: myapp-out.log + myapp-error.log
#   pm2-start-logs app.js --name api -- --port 3000
#
# Logs are automatically saved to: ~/.pm2/logs/
# Each app gets separate output and error logs with timestamps

set -euo pipefail

# Detect app name
get_app_name() {
    local script="$1"
    shift
    
    # Check if --name is provided
    for i in "$@"; do
        if [[ "$prev" == "--name" ]]; then
            echo "$i"
            return 0
        fi
        prev="$i"
    done
    
    # Fall back to script name without extension
    basename "$script" | sed 's/\.[^.]*$//'
}

# Get NVM setup
setup_nvm() {
    if [[ ! -f "$HOME/.nvm/nvm.sh" ]]; then
        echo "Error: NVM not found. Please install via init.sh first."
        return 1
    fi
    export NVM_DIR="$HOME/.nvm"
    source "$NVM_DIR/nvm.sh"
    return 0
}

# Main logic
if [[ $# -eq 0 ]]; then
    echo "Usage: pm2-start-logs <app.js> [pm2-options]"
    echo "Example: pm2-start-logs app.js --name myapp -- --port 3000"
    echo ""
    echo "Logs auto-saved to: ~/.pm2/logs/<app-name>-{out,error}.log"
    exit 1
fi

setup_nvm || exit 1

local script="$1"
shift
local app_name=$(get_app_name "$script" "$@")
local logs_dir="$HOME/.pm2/logs"

# Ensure logs directory exists
mkdir -p "$logs_dir"

# Start app with automatic logging
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
echo ""
echo "View logs:"
echo "  pm2 logs $app_name          (live)"
echo "  plog_app $app_name          (last 100 lines)"
echo "  plog_errors $app_name       (errors only)"
echo ""
PM2STARTSCRIPT
            chmod +x "$pm2_home/pm2-start-logs.sh"
            chown "$USERNAME:$USERNAME" "$pm2_home/pm2-start-logs.sh"
            ok "PM2 auto-logging wrapper script created."
            echo -e "  ${GRY}   Usage: pm2-start-logs app.js --name myapp${R}"
            echo -e "  ${GRY}   (Auto creates separate output + error logs)${R}"
        fi

        # 5. Create enhanced ecosystem.config.js template
        cat > "$pm2_home/ecosystem.template.js" <<'ECOSYSTEMTEMPLATE'
// PM2 Ecosystem Configuration Template
// Each app gets its own detailed logs with timestamps and separation
// Usage: pm2 start ecosystem.config.js

module.exports = {
  apps: [
    // ──────────────────────────────────────────────────────────────
    // APP 1: Main API Server
    // ──────────────────────────────────────────────────────────────
    {
      name: 'api-server',
      script: 'app.js',
      cwd: '/home/username/projects/api',
      
      // Logging: Detailed output and error logs
      output: '/home/username/.pm2/logs/api-server-out.log',
      error: '/home/username/.pm2/logs/api-server-error.log',
      
      // Log format with timestamps
      log: '/home/username/.pm2/logs/api-server-combined.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      
      // Process management
      instances: 1,
      exec_mode: 'cluster',
      instance_var: 'INSTANCE_ID',
      
      // Environment variables
      env: {
        NODE_ENV: 'production',
        PORT: 3000,
        LOG_LEVEL: 'info'
      },
      
      // Restart policies
      watch: false,
      ignore_watch: ['node_modules', '.git', 'logs'],
      max_memory_restart: '500M',
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      
      // Process signals
      kill_timeout: 5000,
      listen_timeout: 3000,
      shutdown_with_message: false
    },

    // ──────────────────────────────────────────────────────────────
    // APP 2: Background Jobs Worker
    // ──────────────────────────────────────────────────────────────
    {
      name: 'worker-jobs',
      script: 'worker.js',
      cwd: '/home/username/projects/worker',
      
      // Detailed separate logging
      output: '/home/username/.pm2/logs/worker-jobs-out.log',
      error: '/home/username/.pm2/logs/worker-jobs-error.log',
      log: '/home/username/.pm2/logs/worker-jobs-combined.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      
      // Worker-specific settings
      instances: 2,
      exec_mode: 'cluster',
      instance_var: 'WORKER_ID',
      
      env: {
        NODE_ENV: 'production',
        WORKER_CONCURRENCY: 5,
        LOG_LEVEL: 'debug'
      },
      
      watch: false,
      ignore_watch: ['node_modules', '.git', 'logs'],
      max_memory_restart: '300M'
    },

    // ──────────────────────────────────────────────────────────────
    // APP 3: Real-time Service (WebSocket)
    // ──────────────────────────────────────────────────────────────
    {
      name: 'realtime-service',
      script: 'websocket.js',
      cwd: '/home/username/projects/realtime',
      
      // WebSocket streaming logs
      output: '/home/username/.pm2/logs/realtime-service-out.log',
      error: '/home/username/.pm2/logs/realtime-service-error.log',
      log: '/home/username/.pm2/logs/realtime-service-combined.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss.SSS Z',
      
      instances: 1,
      exec_mode: 'fork',
      
      env: {
        NODE_ENV: 'production',
        PORT: 4000,
        LOG_LEVEL: 'verbose'
      },
      
      watch: false,
      max_memory_restart: '200M',
      error_file: '/home/username/.pm2/logs/realtime-error-detailed.log',
      out_file: '/home/username/.pm2/logs/realtime-output-detailed.log'
    }
  ],

  // Global PM2 settings
  deploy: {
    production: {
      user: 'username',
      host: 'your-server.com',
      ref: 'origin/main',
      repo: 'git@github.com:you/repo.git',
      path: '/home/username/projects/production'
    }
  }
};
ECOSYSTEMTEMPLATE
        chown "$USERNAME:$USERNAME" "$pm2_home/ecosystem.template.js"
        ok "PM2 ecosystem.config.js template created → ~/.pm2/ecosystem.template.js"
        echo -e "  ${GRY}   Customize and use: cp ~/.pm2/ecosystem.template.js ecosystem.config.js${R}"
        echo -e "  ${GRY}   Then start: pm2 start ecosystem.config.js${R}"
    fi

        # Install pm2-prometheus-exporter so PM2 process states appear in Grafana
        su - "$USERNAME" -c "
            export NVM_DIR=\"\$HOME/.nvm\"; source \"\$NVM_DIR/nvm.sh\"
            pm2 install pm2-prometheus-exporter 2>/dev/null || true
            pm2 set pm2-prometheus-exporter:port 9209 2>/dev/null || true
            pm2 save 2>/dev/null || true
        " 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        ok "PM2 Prometheus exporter installed — exposes metrics on 127.0.0.1:9209."
        info "Scrape target added to Prometheus. PM2 apps appear in Grafana automatically."
    fi

    # ── E. Loki — system log backend ──────────────────────────────────────────
    local loki_ver="3.0.0"
    info "Installing Loki v${loki_ver} (log aggregation backend)..."
    # Ensure unzip is available for extracting the release archive
    if ! command -v unzip &>/dev/null; then
        apt-get install -y unzip 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
    fi
    if ! command -v loki &>/dev/null; then
        local loki_url="https://github.com/grafana/loki/releases/download/v${loki_ver}/loki-linux-${arch}.zip"
        rm -f /tmp/loki.zip
        # Try curl first (handles redirects better), fall back to wget
        if command -v curl &>/dev/null; then
            curl -fsSL "$loki_url" -o /tmp/loki.zip 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        else
            wget -q "$loki_url" -O /tmp/loki.zip 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        fi
        if [[ -f /tmp/loki.zip ]] && unzip -t /tmp/loki.zip &>/dev/null; then
            # Discover the binary name inside the archive (handles naming variations)
            local loki_bin
            loki_bin=$(unzip -Z1 /tmp/loki.zip 2>/dev/null | grep -E '^loki-linux' | head -1) || true
            if [[ -n "$loki_bin" ]]; then
                cd /tmp && unzip -q loki.zip "$loki_bin" 2>/dev/null || true
                if [[ -f "/tmp/$loki_bin" ]]; then
                    mv "/tmp/$loki_bin" /usr/local/bin/loki
                    chmod +x /usr/local/bin/loki
                    rm -f /tmp/loki.zip
                    ok "Loki binary installed → /usr/local/bin/loki"
                else
                    warn "Loki binary not found in archive — install manually from https://github.com/grafana/loki/releases"
                fi
            else
                warn "Loki binary not found in archive — install manually from https://github.com/grafana/loki/releases"
            fi
        else
            rm -f /tmp/loki.zip
            warn "Loki download failed — install manually from https://github.com/grafana/loki/releases"
        fi
    else
        ok "Loki already installed."
    fi

    useradd --no-create-home --shell /bin/false loki 2>/dev/null || true
    mkdir -p /etc/loki /var/lib/loki
    chown loki:loki /var/lib/loki

    if [[ ! -f /etc/loki/loki.yml ]]; then
        cat > /etc/loki/loki.yml <<LOKICFG
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096
  log_level: warn
  log_format: json
  graceful_shutdown_timeout: 30s

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
  ingestion_rate_mb: 32
  ingestion_burst_size_mb: 64
  max_cache_freshness_per_query: 10m
  split_queries_by_interval: 24h

compactor:
  working_directory: /var/lib/loki/compactor
  retention_enabled: true
  delete_request_store: filesystem
  shared_store: filesystem

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
After=network-online.target
Wants=network-online.target

[Service]
User=loki
Group=loki
Type=simple
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki.yml
Restart=always
RestartSec=10
StartLimitInterval=60s
StartLimitBurst=3
LimitNOFILE=65536
HealthCheck=/bin/bash -c 'curl -sf http://127.0.0.1:3100/ready || exit 1'

[Install]
WantedBy=multi-user.target
LOKISVC
        systemctl daemon-reload
        systemctl enable --now loki 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        sleep 3  # Wait for Loki to be ready
        ok "Loki service enabled (127.0.0.1:3100)."
    else
        ok "Loki service already configured."
    fi

    # ── F. Promtail — log agent (system logs + PM2 logs → Loki) ───────────────
    local promtail_ver="3.0.0"
    info "Installing Promtail v${promtail_ver} (log collection agent)..."
    if ! command -v promtail &>/dev/null; then
        local promtail_url="https://github.com/grafana/loki/releases/download/v${promtail_ver}/promtail-linux-${arch}.zip"
        rm -f /tmp/promtail.zip
        # Try curl first (handles redirects better), fall back to wget
        if command -v curl &>/dev/null; then
            curl -fsSL "$promtail_url" -o /tmp/promtail.zip 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        else
            wget -q "$promtail_url" -O /tmp/promtail.zip 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        fi
        if [[ -f /tmp/promtail.zip ]] && unzip -t /tmp/promtail.zip &>/dev/null; then
            # Discover the binary name inside the archive (handles naming variations)
            local promtail_bin
            promtail_bin=$(unzip -Z1 /tmp/promtail.zip 2>/dev/null | grep -E '^promtail-linux' | head -1) || true
            if [[ -n "$promtail_bin" ]]; then
                cd /tmp && unzip -q promtail.zip "$promtail_bin" 2>/dev/null || true
                if [[ -f "/tmp/$promtail_bin" ]]; then
                    mv "/tmp/$promtail_bin" /usr/local/bin/promtail
                    chmod +x /usr/local/bin/promtail
                    rm -f /tmp/promtail.zip
                    ok "Promtail binary installed → /usr/local/bin/promtail"
                else
                    warn "Promtail binary not found in archive — install manually from https://github.com/grafana/loki/releases"
                fi
            else
                warn "Promtail binary not found in archive — install manually from https://github.com/grafana/loki/releases"
            fi
        else
            rm -f /tmp/promtail.zip
            warn "Promtail download failed — install manually from https://github.com/grafana/loki/releases"
        fi
    else
        ok "Promtail already installed."
    fi

    useradd --no-create-home --shell /bin/false promtail 2>/dev/null || true
    usermod -aG adm promtail 2>/dev/null || true   # read /var/log/* files
    mkdir -p /etc/promtail /var/lib/promtail
    chown promtail:promtail /var/lib/promtail

    # Set up ACL permissions for Promtail BEFORE creating config
    info "Setting up Promtail permissions for log access..."
    if ! command -v setfacl &>/dev/null; then
        apt-get install -y acl 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
    fi
    if command -v setfacl &>/dev/null; then
        setfacl -m "u:promtail:rx" "/home/${USERNAME}" 2>/dev/null || true
        setfacl -m "u:promtail:rx" "/home/${USERNAME}/.pm2" 2>/dev/null || true
        setfacl -R -m "u:promtail:rX" "${pm2_log_dir}" 2>/dev/null || true
        setfacl -m "u:promtail:rx" -m "d:u:promtail:rx" "${pm2_log_dir}" 2>/dev/null || true
        ok "ACL permissions set for Promtail."
    else
        warn "setfacl not available — Promtail may have limited log access"
    fi

    local pm2_log_dir="/home/${USERNAME}/.pm2/logs"
    local hostname_val="$(hostname 2>/dev/null || echo 'server')"
    if [[ ! -f /etc/promtail/promtail.yml ]]; then
        cat > /etc/promtail/promtail.yml <<PTCFG
server:
  http_listen_port: 9080
  grpc_listen_port: 0
  log_level: warn
  compression: gzip

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://127.0.0.1:3100/loki/api/v1/push
    max_retries: 3
    min_backoff: 100ms
    max_backoff: 10s

scrape_configs:

  # ── Syslog ──────────────────────────────────────────────────────────────────
  - job_name: syslog
    static_configs:
      - targets: [localhost]
        labels:
          job: syslog
          host: ${hostname_val}
          __path__: /var/log/syslog
    pipeline_stages:
      - match:
          selector: '{job="syslog"}'
          stages:
            - regex:
                expression: '^(?P<timestamp>\S+\s+\S+\s+\S+)\s+(?P<host>\S+)\s+(?P<process>[^:\[]+)[^\:]*:\s*(?P<message>.*)$'
            - labels:
                process: process

  # ── Auth log ─────────────────────────────────────────────────────────────────
  - job_name: auth
    static_configs:
      - targets: [localhost]
        labels:
          job: auth
          host: ${hostname_val}
          __path__: /var/log/auth.log

  # ── Kernel log ───────────────────────────────────────────────────────────────
  - job_name: kern
    static_configs:
      - targets: [localhost]
        labels:
          job: kern
          host: ${hostname_val}
          __path__: /var/log/kern.log

  # ── PM2 app logs ─────────────────────────────────────────────────────────────
  - job_name: pm2
    static_configs:
      - targets: [localhost]
        labels:
          job: pm2
          host: ${hostname_val}
          __path__: ${pm2_log_dir}/*.log
    pipeline_stages:
      - match:
          selector: '{job="pm2"}'
          stages:
            - regex:
                expression: '^(?P<timestamp>\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:\d{2})?)\s+(?P<level>\S+)\s+(?P<message>.*)$'
            - labels:
                level: level

  # ── Nginx access + error logs ─────────────────────────────────────────────
  - job_name: nginx
    static_configs:
      - targets: [localhost]
        labels:
          job: nginx
          host: ${hostname_val}
          __path__: /var/log/nginx/*.log
PTCFG
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
After=network-online.target loki.service
Wants=network-online.target loki.service

[Service]
User=promtail
Group=promtail
Type=simple
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail.yml
ExecReload=/bin/kill -SIGHUP $MAINPID
Restart=always
RestartSec=10
StartLimitInterval=60s
StartLimitBurst=3
LimitNOFILE=65536
HealthCheck=/bin/bash -c 'curl -sf http://127.0.0.1:9080/loki/api/v1/tail || exit 1'

[Install]
WantedBy=multi-user.target
PTSVC
        systemctl daemon-reload
        systemctl enable --now promtail 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        sleep 2  # Wait for Promtail to be ready
        ok "Promtail service enabled — collecting system logs + PM2 app logs."
    else
        ok "Promtail service already configured."
    fi

    # ── G. ClickHouse — 2-day short-term log backend (analytical queries) ──────
    # ClickHouse is great for fast log analysis with retention policies
    info "Installing ClickHouse for 2-day short-term logging..."
    
    if ! command -v clickhouse-client &>/dev/null; then
        # Add ClickHouse repository
        apt-get install -y apt-transport-https ca-certificates dirmngr gnupg 2>&1 | tail -2 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        echo "deb https://packages.clickhouse.com/deb stable main" | tee /etc/apt/sources.list.d/clickhouse.list 2>/dev/null || true
        apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv E0C9851CC6E98FB3 2>&1 | tail -1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        apt-get update -qq 2>&1 | tail -1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        apt-get install -y clickhouse-server clickhouse-client 2>&1 | tail -3 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        ok "ClickHouse installed."
    else
        ok "ClickHouse already installed."
    fi

    # Create ClickHouse config directory
    mkdir -p /etc/clickhouse-server/config.d
    
    # Configure ClickHouse for production with proper retention
    if [[ ! -f /etc/clickhouse-server/config.d/logging.xml ]]; then
        cat > /etc/clickhouse-server/config.d/logging.xml <<'CHCFG'
<yandex>
    <!-- Log levels: trace, debug, information, warning, error, fatal -->
    <logger>
        <level>warning</level>
        <log>/var/log/clickhouse-server/clickhouse-server.log</log>
        <errorlog>/var/log/clickhouse-server/clickhouse-server.err.log</errorlog>
        <size>1000M</size>
        <count>10</count>
    </logger>
    
    <!-- Query log for performance analysis -->
    <query_log>
        <database>system</database>
        <table>query_log</table>
        <partition_by>toYYYYMM(event_time)</partition_by>
        <flush_interval_milliseconds>7500</flush_interval_milliseconds>
    </query_log>

    <!-- HTTP interface on port 17123 -->
    <http_port>17123</http_port>
    <tcp_port>19000</tcp_port>
    
    <listen_host>127.0.0.1</listen_host>
</yandex>
CHCFG
        chown clickhouse:clickhouse /etc/clickhouse-server/config.d/logging.xml
        ok "ClickHouse logging config created."
    fi

    # Start ClickHouse
    systemctl daemon-reload
    systemctl enable --now clickhouse-server 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
    sleep 3  # Wait for ClickHouse to start
    ok "ClickHouse service enabled (127.0.0.1:17123 HTTP, 19000 TCP)."

    # Create PM2 logs table with 2-day TTL
    if ! clickhouse-client --query "SHOW TABLES FROM pm2_logs" 2>/dev/null | grep -q "logs"; then
        info "Creating ClickHouse unified log schema (PM2 + System + Nginx → ClickHouse)..."
        clickhouse-client <<'CHSQL' 2>&1 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
CREATE DATABASE IF NOT EXISTS pm2_logs;

-- Main unified logs table (all types: PM2, system, nginx)
CREATE TABLE IF NOT EXISTS pm2_logs.logs (
    timestamp DateTime DEFAULT now(),
    log_type Enum('pm2', 'system', 'nginx', 'syslog', 'auth', 'kern', 'other') = 'other',
    app_name String,
    log_level String,
    message String,
    hostname String DEFAULT 'localhost',
    source_file String DEFAULT '',
    process_id UInt32 DEFAULT 0,
    received_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (timestamp, log_type, app_name)
PARTITION BY toYYYYMMDD(timestamp)
TTL timestamp + INTERVAL 2 DAY DELETE
SETTINGS ttl_only_drop_parts = 1;

-- Buffer table for batching writes (improves performance)
CREATE TABLE IF NOT EXISTS pm2_logs.logs_buffer AS pm2_logs.logs
ENGINE = Buffer(pm2_logs, logs, 16, 10, 60, 100000, 1000000, 10485760, 104857600);

-- PM2 logs table (for specific PM2 querying)
CREATE TABLE IF NOT EXISTS pm2_logs.pm2_logs (
    timestamp DateTime DEFAULT now(),
    app_name String,
    log_level String,
    message String,
    hostname String DEFAULT 'localhost',
    received_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (timestamp, app_name)
PARTITION BY toYYYYMMDD(timestamp)
TTL timestamp + INTERVAL 2 DAY DELETE;

-- System logs table (syslog, auth, kern)
CREATE TABLE IF NOT EXISTS pm2_logs.system_logs (
    timestamp DateTime DEFAULT now(),
    log_type Enum('syslog', 'auth', 'kern') = 'syslog',
    hostname String DEFAULT 'localhost',
    facility String DEFAULT '',
    severity String DEFAULT '',
    message String,
    received_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (timestamp, log_type)
PARTITION BY toYYYYMMDD(timestamp)
TTL timestamp + INTERVAL 2 DAY DELETE;

-- Nginx logs table
CREATE TABLE IF NOT EXISTS pm2_logs.nginx_logs (
    timestamp DateTime DEFAULT now(),
    hostname String DEFAULT 'localhost',
    remote_addr String,
    request_method String,
    request_path String,
    http_status UInt16,
    response_time_ms Float32,
    bytes_sent UInt64,
    user_agent String,
    received_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (timestamp, hostname)
PARTITION BY toYYYYMMDD(timestamp)
TTL timestamp + INTERVAL 2 DAY DELETE;

CHSQL
        ok "ClickHouse: Unified log tables created (2-day auto-retention)."
    else
        ok "ClickHouse: Log tables already exist."
    fi

    # Create HTTP endpoint for PM2 logs insertion
    if [[ ! -f /etc/clickhouse-server/config.d/http_listen.xml ]]; then
        cat > /etc/clickhouse-server/config.d/http_listen.xml <<'CHHTTP'
<yandex>
    <!-- HTTP interface for log insertion -->
    <http_port>17123</http_port>
    <tcp_port>19000</tcp_port>
    <listen_host>127.0.0.1</listen_host>
    
    <!-- Allow inserts from localhost -->
    <http_handlers>
        <rule>
            <url_regex>^/api/.*</url_regex>
            <handler>static</handler>
            <content_type>application/json</content_type>
            <response_content>/etc/clickhouse-server/not_found.html</response_content>
        </rule>
    </http_handlers>
</yandex>
CHHTTP
        chown clickhouse:clickhouse /etc/clickhouse-server/config.d/http_listen.xml
        ok "ClickHouse HTTP endpoint configured."
    fi

    # Create PM2 log shipper script (sends PM2 logs to ClickHouse)
    if [[ $INSTALL_PM2 == true ]]; then
        local pm2_logs_shipper="/usr/local/bin/pm2-logs-to-clickhouse"
        cat > "$pm2_logs_shipper" <<'PM2SHIPPER'
#!/bin/bash
# pm2-logs-to-clickhouse.sh — Ship PM2 logs to ClickHouse & cleanup local storage
# 
# Monitors ~/.pm2/logs/, ships to ClickHouse, then deletes local files
# Saves disk space while maintaining analytics in ClickHouse (2-day retention)

set -euo pipefail

CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-127.0.0.1}"
CLICKHOUSE_PORT="${CLICKHOUSE_PORT:-17123}"
CLICKHOUSE_DB="${CLICKHOUSE_DB:-pm2_logs}"
CLICKHOUSE_TABLE="${CLICKHOUSE_TABLE:-logs}"
PM2_LOGS_DIR="${HOME}/.pm2/logs"
STATE_FILE="${HOME}/.pm2/logs-shipped.state"
LOG_DELETE_AFTER=${LOG_DELETE_AFTER:-1800}  # Delete after 30 min (5400=90 min, 1800=30 min)

# Initialize state file
[[ ! -f "$STATE_FILE" ]] && echo "0" > "$STATE_FILE"

ship_logs() {
    local app_name="$1"
    local log_file="$2"
    local log_type="${3:-pm2}"
    
    [[ ! -f "$log_file" ]] && return 1
    
    local shipped_lines=$(grep "$log_file" "$STATE_FILE" 2>/dev/null | cut -d: -f2 || echo "0")
    local total_lines=$(wc -l < "$log_file" 2>/dev/null || echo "0")
    
    if (( total_lines > shipped_lines )); then
        # Extract new lines
        local new_logs=$(tail -n +$((shipped_lines + 1)) "$log_file" 2>/dev/null | head -n $((total_lines - shipped_lines)))
        local ship_success=1
        
        # Parse and send to ClickHouse
        echo "$new_logs" | while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            
            # Extract timestamp and message
            local timestamp=$(echo "$line" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' || echo "$(date '+%Y-%m-%d %H:%M:%S')")
            local message=$(echo "$line" | sed 's/^[0-9: -]* //' | tr -d "'\"")
            local log_level="INFO"
            [[ "$message" =~ ERROR|error ]] && log_level="ERROR"
            [[ "$message" =~ WARN|warn ]] && log_level="WARN"
            [[ "$message" =~ SUCCESS|success ]] && log_level="SUCCESS"
            
            # Insert into ClickHouse (with retry)
            local retry=0
            while (( retry < 3 )); do
                if curl -s --max-time 5 "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/" \
                    -d "INSERT INTO ${CLICKHOUSE_DB}.${CLICKHOUSE_TABLE} 
                        (log_type, app_name, log_level, message, timestamp) 
                        VALUES ('${log_type}', '${app_name}', '${log_level}', '${message}', '${timestamp}')" \
                    2>/dev/null | grep -q 'Ok\|^$'; then
                    break
                fi
                (( retry++ ))
                sleep 1
            done
        done
        
        # Update state
        sed -i "/${log_file}/d" "$STATE_FILE" 2>/dev/null || true
        echo "$log_file:$total_lines" >> "$STATE_FILE"
        return 0
    fi
    return 1
}

cleanup_shipped_logs() {
    local log_file="$1"
    [[ ! -f "$log_file" ]] && return
    
    # Only delete if it's older than LOG_DELETE_AFTER seconds
    local file_mtime=$(stat -c %Y "$log_file" 2>/dev/null || stat -f %m "$log_file" 2>/dev/null || echo 0)
    local now=$(date +%s)
    local age=$(( now - file_mtime ))
    
    if (( age > LOG_DELETE_AFTER )); then
        rm -f "$log_file"
    fi
}

# Monitor PM2 logs directory
while true; do
    if [[ -d "$PM2_LOGS_DIR" ]]; then
        # Ship new logs
        for log_file in "$PM2_LOGS_DIR"/*-out.log "$PM2_LOGS_DIR"/*-error.log; do
            [[ -f "$log_file" ]] || continue
            app_name=$(basename "$log_file" | sed 's/-out\.log\|-error\.log//')
            ship_logs "$app_name" "$log_file" "pm2" || true
        done
        
        # Cleanup old shipped logs (after 30 min in ClickHouse)
        for log_file in "$PM2_LOGS_DIR"/*-out.log "$PM2_LOGS_DIR"/*-error.log "$PM2_LOGS_DIR"/*.gz; do
            [[ -f "$log_file" ]] && cleanup_shipped_logs "$log_file"
        done
    fi
    sleep 5  # Check every 5 seconds
done
PM2SHIPPER
        chmod +x "$pm2_logs_shipper"
        ok "PM2 log shipper created → $pm2_logs_shipper"
        
        # Create systemd service for PM2 log shipper
        cat > /etc/systemd/system/pm2-logs-clickhouse.service <<'PM2SVC'
[Unit]
Description=PM2 Logs to ClickHouse Shipper
After=pm2-stack.service clickhouse-server.service
Wants=pm2-stack.service clickhouse-server.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/pm2-logs-to-clickhouse
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment="HOME=/root"

[Install]
WantedBy=multi-user.target
PM2SVC
        systemctl daemon-reload
        systemctl enable --now pm2-logs-clickhouse 2>/dev/null || true
        ok "PM2 log shipper service enabled (ships to ClickHouse & auto-deletes local files)."
    fi

    # ── H. Create Professional Grafana Log Analytics Dashboards ────────────────────
    info "Creating professional log analytics dashboard suite..."
    
    # Create dashboard provider for Logs folder
    if [[ ! -f /etc/grafana/provisioning/dashboards/logs.yaml ]]; then
        cat > /etc/grafana/provisioning/dashboards/logs.yaml <<LOGSPROV
apiVersion: 1
providers:
  - name: 'Logs'
    orgId: 1
    folder: 'Logs'
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards/logs
LOGSPROV
        chown grafana:grafana /etc/grafana/provisioning/dashboards/logs.yaml 2>/dev/null || true
        ok "Dashboard provider created for 'Logs' folder."
    fi
    
    # Create dashboards directory
    mkdir -p /var/lib/grafana/dashboards/logs 2>/dev/null || true
    
    # 1. Template Dashboard for Per-App Metrics
    cat > /var/lib/grafana/dashboards/applications/01-template-app-metrics.json <<'DASHBOARD_TEMPLATE_METRICS'
{
  "dashboard": {
    "title": "📊 Template — App Metrics & Status",
    "description": "Use this as a template: duplicate & change app_name for per-app monitoring. Shows real-time status, CPU, memory, restarts for ONE selected app.",
    "timezone": "browser",
    "templating": {
      "list": [
        {
          "name": "app_name",
          "type": "textbox",
          "label": "App Name",
          "description": "Set to PM2 process name (your actual app name)"
        }
      ]
    },
    "panels": [
      {
        "title": "App Status",
        "description": "Real-time status for this app",
        "targets": [{"expr": "SELECT status FROM pm2_process_metrics WHERE process_name = $${app_name}$ LIMIT 1"}],
        "type": "stat",
        "gridPos": {"x": 0, "y": 0, "w": 6, "h": 3}
      },
      {
        "title": "CPU Usage (%)",
        "description": "CPU for this app only",
        "targets": [{"expr": "SELECT cpu_usage FROM pm2_process_metrics WHERE process_name = $${app_name}$"}],
        "type": "timeseries",
        "gridPos": {"x": 6, "y": 0, "w": 6, "h": 3}
      },
      {
        "title": "Memory (MB)",
        "description": "Memory for this app only",
        "targets": [{"expr": "SELECT memory_mb FROM pm2_process_metrics WHERE process_name = $${app_name}$"}],
        "type": "timeseries",
        "gridPos": {"x": 12, "y": 0, "w": 6, "h": 3}
      },
      {
        "title": "Restart Count",
        "description": "Total restarts for this app",
        "targets": [{"expr": "SELECT restart_count FROM pm2_process_metrics WHERE process_name = $${app_name}$ ORDER BY timestamp DESC LIMIT 1"}],
        "type": "stat",
        "gridPos": {"x": 18, "y": 0, "w": 6, "h": 3}
      },
      {
        "title": "Uptime (Hours)",
        "description": "How long this app has been running",
        "targets": [{"expr": "SELECT uptime_hours FROM pm2_process_metrics WHERE process_name = $${app_name}$ ORDER BY timestamp DESC LIMIT 1"}],
        "type": "stat",
        "gridPos": {"x": 0, "y": 3, "w": 6, "h": 3}
      },
      {
        "title": "Process Instances",
        "description": "Number of instances/workers for this app",
        "targets": [{"expr": "SELECT instance_count FROM pm2_process_metrics WHERE process_name = $${app_name}$ ORDER BY timestamp DESC LIMIT 1"}],
        "type": "stat",
        "gridPos": {"x": 6, "y": 3, "w": 6, "h": 3}
      }
    ],
    "refresh": "15s",
    "time": {"from": "now-6h", "to": "now"},
    "schemaVersion": 38,
    "style": "dark",
    "version": 1
  }
}
DASHBOARD_TEMPLATE_METRICS
    
    # 2. Template Dashboard for Per-App Logs
    cat > /var/lib/grafana/dashboards/applications/02-template-app-logs.json <<'DASHBOARD_TEMPLATE_LOGS'
{
  "dashboard": {
    "title": "📋 Template — App Logs & Activity",
    "description": "Use this as a template: duplicate & change app_name for per-app logs. Shows application output, errors, and request patterns for ONE selected app.",
    "timezone": "browser",
    "templating": {
      "list": [
        {
          "name": "app_name",
          "type": "textbox",
          "label": "App Name",
          "description": "Set to PM2 process name (your actual app name)"
        }
      ]
    },
    "panels": [
      {
        "title": "Total Logs (24h)",
        "targets": [{"expr": "SELECT COUNT() FROM pm2_logs.logs WHERE app_name = $${app_name}$ AND timestamp > now() - 86400"}],
        "type": "stat",
        "gridPos": {"x": 0, "y": 0, "w": 6, "h": 3}
      },
      {
        "title": "Error Count (24h)",
        "targets": [{"expr": "SELECT COUNT() FROM pm2_logs.logs WHERE app_name = $${app_name}$ AND log_level='ERROR' AND timestamp > now() - 86400"}],
        "type": "stat",
        "gridPos": {"x": 6, "y": 0, "w": 6, "h": 3}
      },
      {
        "title": "Warning Count (24h)",
        "targets": [{"expr": "SELECT COUNT() FROM pm2_logs.logs WHERE app_name = $${app_name}$ AND log_level='WARN' AND timestamp > now() - 86400"}],
        "type": "stat",
        "gridPos": {"x": 12, "y": 0, "w": 6, "h": 3}
      },
      {
        "title": "Log Volume Trend",
        "description": "Activity over time for this app",
        "targets": [{"expr": "SELECT toStartOfHour(timestamp) as time, COUNT(*) FROM pm2_logs.logs WHERE app_name = $${app_name}$ AND timestamp > now() - 86400 GROUP BY time ORDER BY time"}],
        "type": "timeseries",
        "gridPos": {"x": 0, "y": 3, "w": 12, "h": 8}
      },
      {
        "title": "Log Levels Distribution",
        "description": "Info, warn, error breakdown for this app",
        "targets": [{"expr": "SELECT log_level, COUNT() FROM pm2_logs.logs WHERE app_name = $${app_name}$ AND timestamp > now() - 86400 GROUP BY log_level"}],
        "type": "piechart",
        "gridPos": {"x": 12, "y": 3, "w": 12, "h": 8}
      },
      {
        "title": "Recent Logs (Last 50)",
        "description": "Latest log entries for this app",
        "targets": [{"expr": "SELECT timestamp, log_level, message FROM pm2_logs.logs WHERE app_name = $${app_name}$ ORDER BY timestamp DESC LIMIT 50"}],
        "type": "table",
        "gridPos": {"x": 0, "y": 11, "w": 24, "h": 10}
      }
    ],
    "refresh": "30s",
    "time": {"from": "now-24h", "to": "now"},
    "schemaVersion": 38,
    "style": "dark",
    "version": 1
  }
}
DASHBOARD_TEMPLATE_LOGS
    
    # 3. Template Dashboard for Per-App Errors & Health
    cat > /var/lib/grafana/dashboards/applications/03-template-app-errors.json <<'DASHBOARD_TEMPLATE_ERRORS'
{
  "dashboard": {
    "title": "⚠️  Template — App Errors & Health",
    "description": "Use this as a template: duplicate & change app_name for per-app monitoring. Shows errors, health score, and incidents for ONE selected app.",
    "timezone": "browser",
    "templating": {
      "list": [
        {
          "name": "app_name",
          "type": "textbox",
          "label": "App Name",
          "description": "Set to PM2 process name (your actual app name)"
        }
      ]
    },
    "panels": [
      {
        "title": "Health Score",
        "description": "100% = no errors, 0% = all errors. Higher is better.",
        "targets": [{"expr": "SELECT ROUND(100 - (SUM(IF(log_level='ERROR', 1, 0)) * 100 / COUNT()), 1) FROM pm2_logs.logs WHERE app_name = $${app_name}$ AND timestamp > now() - 86400"}],
        "type": "stat",
        "gridPos": {"x": 0, "y": 0, "w": 8, "h": 3},
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "unit": "percent", "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": null}, {"color": "yellow", "value": 80}, {"color": "green", "value": 95}]}}}
      },
      {
        "title": "Error Rate (%)",
        "targets": [{"expr": "SELECT ROUND(SUM(IF(log_level='ERROR', 1, 0)) * 100 / COUNT(), 2) FROM pm2_logs.logs WHERE app_name = $${app_name}$ AND timestamp > now() - 86400"}],
        "type": "stat",
        "gridPos": {"x": 8, "y": 0, "w": 8, "h": 3},
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "unit": "percent", "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "yellow", "value": 5}, {"color": "red", "value": 10}]}}}
      },
      {
        "title": "Last Error Time",
        "targets": [{"expr": "SELECT MAX(timestamp) FROM pm2_logs.logs WHERE app_name = $${app_name}$ AND log_level='ERROR'"}],
        "type": "stat",
        "gridPos": {"x": 16, "y": 0, "w": 8, "h": 3}
      },
      {
        "title": "Error Trend (Hourly)",
        "description": "Errors over time for this app",
        "targets": [{"expr": "SELECT toStartOfHour(timestamp) as time, COUNT() FROM pm2_logs.logs WHERE app_name = $${app_name}$ AND log_level='ERROR' AND timestamp > now() - 86400 GROUP BY time ORDER BY time"}],
        "type": "timeseries",
        "gridPos": {"x": 0, "y": 3, "w": 12, "h": 8}
      },
      {
        "title": "Error Distribution by Type",
        "description": "Top error types for this app",
        "targets": [{"expr": "SELECT message, COUNT() as count FROM pm2_logs.logs WHERE app_name = $${app_name}$ AND log_level='ERROR' AND timestamp > now() - 86400 GROUP BY message ORDER BY count DESC LIMIT 10"}],
        "type": "bargauge",
        "gridPos": {"x": 12, "y": 3, "w": 12, "h": 8}
      },
      {
        "title": "Recent Errors (Last 30)",
        "description": "Latest errors for this app",
        "targets": [{"expr": "SELECT timestamp, log_level, message FROM pm2_logs.logs WHERE app_name = $${app_name}$ AND log_level='ERROR' ORDER BY timestamp DESC LIMIT 30"}],
        "type": "table",
        "gridPos": {"x": 0, "y": 11, "w": 24, "h": 10}
      }
    ],
    "refresh": "30s",
    "time": {"from": "now-24h", "to": "now"},
    "schemaVersion": 38,
    "style": "dark",
    "version": 1
  }
}
DASHBOARD_TEMPLATE_ERRORS
      },
      {
        "title": "Error Trend (24h)",
        "description": "Hourly error count over last 24 hours",
        "targets": [{"expr": "SELECT toStartOfHour(timestamp) as time, COUNT(*) as Errors FROM pm2_logs.logs WHERE log_level='ERROR' AND timestamp > now() - 86400 GROUP BY time ORDER BY time"}],
        "type": "timeseries",
        "gridPos": {"x": 0, "y": 3, "w": 12, "h": 8},
        "fieldConfig": {"defaults": {"custom": {"lineWidth": 2}, "color": {"mode": "palette-classic"}}}
      },
      {
        "title": "All Logs Trend (24h)",
        "description": "Hourly log volume over last 24 hours",
        "targets": [{"expr": "SELECT toStartOfHour(timestamp) as time, COUNT(*) as Volume FROM pm2_logs.logs WHERE timestamp > now() - 86400 GROUP BY time ORDER BY time"}],
        "type": "timeseries",
        "gridPos": {"x": 12, "y": 3, "w": 12, "h": 8},
        "fieldConfig": {"defaults": {"custom": {"lineWidth": 2}, "color": {"mode": "palette-classic"}}}
      },
      {
        "title": "Log Distribution by Level",
        "description": "Percentage breakdown: ERROR, WARN, INFO, SUCCESS",
        "targets": [{"expr": "SELECT log_level, COUNT() as count FROM pm2_logs.logs WHERE timestamp > now() - 86400 GROUP BY log_level"}],
        "type": "piechart",
        "gridPos": {"x": 0, "y": 11, "w": 8, "h": 8}
      },
      {
        "title": "Top 10 Apps by Error Count",
        "description": "Apps with most errors in last 24h",
        "targets": [{"expr": "SELECT app_name, COUNT() as Errors FROM pm2_logs.logs WHERE log_level='ERROR' AND timestamp > now() - 86400 GROUP BY app_name ORDER BY Errors DESC LIMIT 10"}],
        "type": "bargauge",
        "gridPos": {"x": 8, "y": 11, "w": 8, "h": 8}
      },
      {
        "title": "Health Score by App",
        "description": "Lower error rate = healthier. Error rate % per app",
        "targets": [{"expr": "SELECT app_name, ROUND(100 - (SUM(IF(log_level='ERROR', 1, 0)) * 100 / COUNT()), 2) as health FROM pm2_logs.logs WHERE timestamp > now() - 86400 GROUP BY app_name ORDER BY health DESC LIMIT 15"}],
        "type": "bargauge",
        "gridPos": {"x": 16, "y": 11, "w": 8, "h": 8}
      },
      {
        "title": "App Activity (24h Summary)",
        "description": "Total logs, errors, and error rate per app",
        "targets": [{"expr": "SELECT app_name, COUNT() as total_logs, SUM(IF(log_level='ERROR', 1, 0)) as errors, ROUND(SUM(IF(log_level='ERROR', 1, 0)) * 100 / COUNT(), 2) as error_rate_pct FROM pm2_logs.logs WHERE timestamp > now() - 86400 GROUP BY app_name ORDER BY error_rate_pct DESC LIMIT 20"}],
        "type": "table",
        "gridPos": {"x": 0, "y": 19, "w": 24, "h": 8}
      }
    ],
    "refresh": "30s",
    "time": {"from": "now-24h", "to": "now"},
    "schemaVersion": 38,
    "style": "dark",
    "version": 1
  }
}
DASHBOARD_TEMPLATE_ERRORS


    
    # Create Logs folder copies for aggregate dashboards (for backward compatibility)
    cat > /var/lib/grafana/dashboards/logs/01-overview.json <<'DASHBOARD_AGGREGATE_OVERVIEW'
{
  "dashboard": {
    "title": "📊 Logs — Overview",
    "description": "Aggregate log analytics across ALL applications: error rates, trends, overall health",
    "timezone": "browser",
    "panels": [
      {
        "title": "Total Logs (24h)",
        "targets": [{"expr": "SELECT COUNT() FROM pm2_logs.logs WHERE timestamp > now() - 86400"}],
        "type": "stat",
        "gridPos": {"x": 0, "y": 0, "w": 6, "h": 3},
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "thresholds": {"mode": "absolute", "steps": [{"color": "blue", "value": null}]}}}
      },
      {
        "title": "Error Rate (%)",
        "targets": [{"expr": "SELECT ROUND(SUM(IF(log_level='ERROR', 1, 0)) * 100 / COUNT(), 2) FROM pm2_logs.logs WHERE timestamp > now() - 86400"}],
        "type": "stat",
        "gridPos": {"x": 6, "y": 0, "w": 6, "h": 3},
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "unit": "percent", "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "yellow", "value": 5}, {"color": "red", "value": 10}]}}}
      },
      {
        "title": "Warning Rate (%)",
        "targets": [{"expr": "SELECT ROUND(SUM(IF(log_level='WARN', 1, 0)) * 100 / COUNT(), 2) FROM pm2_logs.logs WHERE timestamp > now() - 86400"}],
        "type": "stat",
        "gridPos": {"x": 12, "y": 0, "w": 6, "h": 3},
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "unit": "percent", "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "yellow", "value": 10}, {"color": "orange", "value": 20}]}}}
      },
      {
        "title": "Top Error-Prone Apps",
        "targets": [{"expr": "SELECT app_name, COUNT() as errors FROM pm2_logs.logs WHERE log_level='ERROR' AND timestamp > now() - 86400 GROUP BY app_name ORDER BY errors DESC LIMIT 10"}],
        "type": "bargauge",
        "gridPos": {"x": 18, "y": 0, "w": 6, "h": 3}
      },
      {
        "title": "Error Trend (24h)",
        "targets": [{"expr": "SELECT toStartOfHour(timestamp) as time, COUNT() FROM pm2_logs.logs WHERE log_level='ERROR' AND timestamp > now() - 86400 GROUP BY time ORDER BY time"}],
        "type": "timeseries",
        "gridPos": {"x": 0, "y": 3, "w": 12, "h": 8}
      },
      {
        "title": "All Apps Activity",
        "targets": [{"expr": "SELECT app_name, COUNT() as logs FROM pm2_logs.logs WHERE timestamp > now() - 86400 GROUP BY app_name ORDER BY logs DESC"}],
        "type": "bargauge",
        "gridPos": {"x": 12, "y": 3, "w": 12, "h": 8}
      }
    ],
    "refresh": "30s",
    "time": {"from": "now-24h", "to": "now"},
    "schemaVersion": 38,
    "style": "dark",
    "version": 1
  }
}
DASHBOARD_AGGREGATE_OVERVIEW
    
    cat > /var/lib/grafana/dashboards/logs/02-error-analysis.json <<'DASHBOARD_AGGREGATE_ERRORS'
{
  "dashboard": {
    "title": "⚠️  Logs — Error Analysis",
    "description": "System-wide error analytics: patterns, distributions, recent incidents across ALL applications",
    "timezone": "browser",
    "panels": [
      {
        "title": "Total Errors (24h)",
        "targets": [{"expr": "SELECT COUNT() FROM pm2_logs.logs WHERE log_level='ERROR' AND timestamp > now() - 86400"}],
        "type": "stat",
        "gridPos": {"x": 0, "y": 0, "w": 6, "h": 3},
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "red", "value": 1}]}}}
      },
      {
        "title": "Error Rate (%)",
        "targets": [{"expr": "SELECT ROUND(SUM(IF(log_level='ERROR', 1, 0)) * 100 / COUNT(), 2) FROM pm2_logs.logs WHERE timestamp > now() - 86400"}],
        "type": "stat",
        "gridPos": {"x": 6, "y": 0, "w": 6, "h": 3},
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "unit": "percent", "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "yellow", "value": 5}, {"color": "red", "value": 10}]}}}
      },
      {
        "title": "Apps with Errors",
        "targets": [{"expr": "SELECT COUNT(DISTINCT app_name) FROM pm2_logs.logs WHERE log_level='ERROR' AND timestamp > now() - 86400"}],
        "type": "stat",
        "gridPos": {"x": 12, "y": 0, "w": 6, "h": 3}
      },
      {
        "title": "Errors Last Hour",
        "targets": [{"expr": "SELECT COUNT() FROM pm2_logs.logs WHERE log_level='ERROR' AND timestamp > now() - 3600"}],
        "type": "stat",
        "gridPos": {"x": 18, "y": 0, "w": 6, "h": 3},
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "red", "value": 10}]}}}
      },
      {
        "title": "Error Trend (Hourly)",
        "targets": [{"expr": "SELECT toStartOfHour(timestamp) as time, COUNT() FROM pm2_logs.logs WHERE log_level='ERROR' AND timestamp > now() - 86400 GROUP BY time ORDER BY time"}],
        "type": "timeseries",
        "gridPos": {"x": 0, "y": 3, "w": 12, "h": 8}
      },
      {
        "title": "Errors by App",
        "targets": [{"expr": "SELECT app_name, COUNT() as errors FROM pm2_logs.logs WHERE log_level='ERROR' AND timestamp > now() - 86400 GROUP BY app_name ORDER BY errors DESC"}],
        "type": "bargauge",
        "gridPos": {"x": 12, "y": 3, "w": 12, "h": 8}
      },
      {
        "title": "Recent Errors (Last 50)",
        "targets": [{"expr": "SELECT timestamp, app_name, message FROM pm2_logs.logs WHERE log_level='ERROR' ORDER BY timestamp DESC LIMIT 50"}],
        "type": "table",
        "gridPos": {"x": 0, "y": 11, "w": 24, "h": 10}
      }
    ],
    "refresh": "30s",
    "time": {"from": "now-24h", "to": "now"},
    "schemaVersion": 38,
    "style": "dark",
    "version": 1
  }
}
DASHBOARD_AGGREGATE_ERRORS
    
    cat > /var/lib/grafana/dashboards/logs/03-app-health.json <<'DASHBOARD_AGGREGATE_HEALTH'
{
  "dashboard": {
    "title": "💚 Logs — App Health",
    "description": "Cross-application health monitoring: health scores, availability, activity summary for ALL applications",
    "timezone": "browser",
    "panels": [
      {
        "title": "System Health Score",
        "description": "Overall 100% = no errors, 0% = all errors.",
        "targets": [{"expr": "SELECT ROUND(100 - (SUM(IF(log_level='ERROR', 1, 0)) * 100 / COUNT()), 1) FROM pm2_logs.logs WHERE timestamp > now() - 86400"}],
        "type": "stat",
        "gridPos": {"x": 0, "y": 0, "w": 8, "h": 3},
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "unit": "percent", "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": null}, {"color": "yellow", "value": 80}, {"color": "green", "value": 95}]}}}
      },
      {
        "title": "Healthy Apps",
        "targets": [{"expr": "SELECT COUNT(*) FROM (SELECT app_name FROM pm2_logs.logs WHERE timestamp > now() - 86400 GROUP BY app_name HAVING SUM(IF(log_level='ERROR', 1, 0)) = 0) WHERE 1=1"}],
        "type": "stat",
        "gridPos": {"x": 8, "y": 0, "w": 8, "h": 3}
      },
      {
        "title": "Problematic Apps",
        "targets": [{"expr": "SELECT COUNT(*) FROM (SELECT app_name FROM pm2_logs.logs WHERE timestamp > now() - 86400 GROUP BY app_name HAVING SUM(IF(log_level='ERROR', 1, 0)) > 0) WHERE 1=1"}],
        "type": "stat",
        "gridPos": {"x": 16, "y": 0, "w": 8, "h": 3}
      },
      {
        "title": "App Health Summary",
        "description": "Health score per app (higher = better, no errors = 100%)",
        "targets": [{"expr": "SELECT app_name, ROUND(100 - (SUM(IF(log_level='ERROR', 1, 0)) * 100 / COUNT()), 1) as health_score, COUNT() as log_volume FROM pm2_logs.logs WHERE timestamp > now() - 86400 GROUP BY app_name ORDER BY health_score DESC"}],
        "type": "table",
        "gridPos": {"x": 0, "y": 3, "w": 24, "h": 10}
      }
    ],
    "refresh": "30s",
    "time": {"from": "now-24h", "to": "now"},
    "schemaVersion": 38,
    "style": "dark",
    "version": 1
  }
}
DASHBOARD_AGGREGATE_HEALTH
    
    chmod 644 /var/lib/grafana/dashboards/logs/*.json 2>/dev/null || true
    chmod 644 /var/lib/grafana/dashboards/applications/*.json 2>/dev/null || true
    
    ok "✓ Per-App Dashboard Templates Created (No Dummy Data)."
    ok "   Templates: Duplicate and customize for each of your apps"
    ok "   ├─ 01-template-app-metrics.json → Real-time metrics & status"
    ok "   ├─ 02-template-app-logs.json → Application logs & activity"
    ok "   └─ 03-template-app-errors.json → Errors, health score, incidents"
    ok ""
    ok "✓ System-Wide Dashboards (in Logs folder for comparison):"
    ok "   ├─ 01-overview.json → All apps aggregate"
    ok "   ├─ 02-error-analysis.json → System-wide errors"
    ok "   └─ 03-app-health.json → Cross-app health"
    ok ""
    ok "📌 HOW TO CREATE PER-APP DASHBOARDS:"
    ok "   1. Duplicate a template dashboard (e.g., 01-template-app-metrics.json)"
    ok "   2. Open the duplicate in Grafana"
    ok "   3. Edit template variable 'app_name' and set to your PM2 process name"
    ok "   4. Save with your app name as dashboard title"
    ok "   5. Queries auto-filter to show only that app's data"

    # Restart Grafana to pick up the new Loki datasource, dashboards, and ClickHouse integration
    systemctl restart grafana-server 2>/dev/null || true
    sleep 2
    
    # Restart Prometheus to reload config
    systemctl restart prometheus 2>/dev/null || true
    sleep 3
    
    ok "Grafana restarted — All dashboards active (System + PM2 + Logs)."

    # ── H. Health Check — Verify all monitoring components are responding ──────
    info "Performing monitoring stack health checks..."
    local checks_passed=0
    local checks_total=7
    
    # Check node_exporter
    if curl -sf --max-time 3 "http://127.0.0.1:9100/metrics" &>/dev/null; then
        ok "✓ node_exporter responding (127.0.0.1:9100)"
        (( checks_passed++ ))
    else
        warn "✗ node_exporter not responding — restart with: systemctl restart node_exporter"
    fi
    
    # Check Prometheus
    if curl -sf --max-time 3 "http://127.0.0.1:9090/-/healthy" &>/dev/null; then
        ok "✓ Prometheus responding (127.0.0.1:9090)"
        (( checks_passed++ ))
    else
        warn "✗ Prometheus not responding — restart with: systemctl restart prometheus"
    fi
    
    # Check Loki
    if curl -sf --max-time 3 "http://127.0.0.1:3100/ready" &>/dev/null; then
        ok "✓ Loki responding (127.0.0.1:3100)"
        (( checks_passed++ ))
    else
        warn "✗ Loki not responding — restart with: systemctl restart loki"
    fi
    
    # Check Promtail
    if curl -sf --max-time 3 "http://127.0.0.1:9080/loki/api/v1/tail" &>/dev/null; then
        ok "✓ Promtail responding (127.0.0.1:9080)"
        (( checks_passed++ ))
    else
        warn "✗ Promtail not responding — restart with: systemctl restart promtail"
    fi
    
    # Check Grafana
    if curl -sf --max-time 3 "http://127.0.0.1:13001/api/health" &>/dev/null; then
        ok "✓ Grafana responding (127.0.0.1:13001)"
        (( checks_passed++ ))
    else
        warn "✗ Grafana not responding — restart with: systemctl restart grafana-server"
    fi
    
    # Check PM2 exporter
    if curl -sf --max-time 3 "http://127.0.0.1:9209/metrics" &>/dev/null; then
        ok "✓ PM2 exporter responding (127.0.0.1:9209)"
        (( checks_passed++ ))
    else
        warn "⚠ PM2 exporter not responding yet (may need an app running) — expected for new installations"
    fi
    
    # Check ClickHouse
    if curl -sf --max-time 3 "http://127.0.0.1:17123/" &>/dev/null; then
        ok "✓ ClickHouse responding (127.0.0.1:17123)"
        (( checks_passed++ ))
    else
        warn "✗ ClickHouse not responding — restart with: systemctl restart clickhouse-server"
    fi
    
    ok "Health checks: $checks_passed/$checks_total passed"

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
if [[ -n "\${mem_total}" && "\${mem_total}" -gt 0 ]] 2>/dev/null; then
    mem_pct=\$(( mem_used * 100 / mem_total ))
else
    mem_pct=0
fi
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

# ── Log Pipeline (Loki + Promtail + ClickHouse) ───────────────────────────────
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
if systemctl is-active --quiet clickhouse-server 2>/dev/null; then
    echo -e "  \${GRN}✔\${R}  ClickHouse running (2-day logs  127.0.0.1:17123)"
else
    echo -e "  \${YLW}⚠\${R}  ClickHouse not running  (sudo systemctl start clickhouse-server)"
fi

# ── Grafana Dashboard ─────────────────────────────────────────────────────────
echo ""
echo -e "  \${BOLD}\${WHT}Monitoring Dashboard (Grafana + Prometheus)\${R}"
if systemctl is-active --quiet grafana-server 2>/dev/null; then
    echo -e "  \${GRN}✔\${R}  Grafana running — access via SSH tunnel:"
    echo -e "  \${GRY}     ssh -L 13001:localhost:13001 ${deploy_user}@<server-ip>\${R}"
    echo -e "  \${GRY}     Then open: http://localhost:13001\${R}"
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
if curl -sf --max-time 3 "http://127.0.0.1:9209/metrics" 2>/dev/null | grep -q "pm2_up"; then
    echo -e "  \${GRN}✔\${R}  PM2 exporter running (127.0.0.1:9209)"
else
    echo -e "  \${YLW}⚠\${R}  PM2 exporter not responding — run: su - ${deploy_user} -c 'pm2 install pm2-prometheus-exporter'"
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
echo -e "  \${GRY}PM2 live: pm2 monit  │  App logs: pm2 logs  │  Grafana: http://localhost:13001\${R}"
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

    # Detect SSH port from sshd_config
    ssh_port=$(grep -i "^port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)
    if [[ -z "$ssh_port" || ! "$ssh_port" =~ ^[0-9]+$ ]]; then
        ssh_port=22
    fi

    run "ufw default deny incoming"
    run "ufw default allow outgoing"
    run "ufw allow $ssh_port/tcp   comment 'SSH'"
    # Monitoring ports (9090/9100/13001) are bound to 127.0.0.1 — no UFW rule needed

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

    ok "Logrotate configured (backup rotation only — main logs deleted by shipper)."

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  14 — SUMMARY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

print_summary() {
    echo ""
    echo -e "${PRP}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${PRP}${BOLD}║${R}${GRN}${BOLD}%-76s${R}${PRP}${BOLD}║${R}\n" \
            "  ✔  Provisioning Complete"
    printf  "  ${PRP}${BOLD}║${R}${GRY}%-76s${R}${PRP}${BOLD}║${R}\n" \
            "  Your Node.js production server is ready."
    echo -e "${PRP}${BOLD}  ╠${HR2}╣${R}"

    _row() { printf "  ${PRP}${BOLD}║${R}  ${GRY}%-22s${R}  ${WHT}${BOLD}%-50s${R}  ${PRP}${BOLD}║${R}\n" "$1" "$2"; }
    _sep() { echo -e "  ${PRP}${BOLD}╠${HR2}╣${R}"; }
    _hdr() { printf "  ${PRP}${BOLD}║${R}  ${CYN}${BOLD}%-74s${R}  ${PRP}${BOLD}║${R}\n" "$1"; }

    _hdr "Server Details"
    _sep
    _row "User"           "$USERNAME"
    _row "Home Directory" "/home/$USERNAME"
    _row "Node.js"        "v${NODE_VER}  (via NVM ${NVM_VERSION})"
    _row "PM2 Service"    "pm2-${USERNAME}  (systemd — auto-starts on reboot)"
    _row "SSH Access"     "password + SSH key  (both supported)"
    _row "Root Access"    "ssh ${USERNAME}@<server>  →  sudo -i  (direct root SSH blocked)"
    _row "Monitoring"     "Grafana :13001 [System + PM2 + Logs] · ClickHouse :17123"

    _sep
    printf "  ${PRP}${BOLD}║${R}  ${YLW}${BOLD}%-22s${R}  ${ORG}${BOLD}%-50s${R}  ${PRP}${BOLD}║${R}\n" \
        "⚠  Password" "$PASSWORD"
    printf "  ${PRP}${BOLD}║${R}  ${GRY}%-22s${R}  ${GRY}%-50s${R}  ${PRP}${BOLD}║${R}\n" \
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
        printf "  ${PRP}${BOLD}║${R}  ${GRN}${BOLD}%s.${R}  ${WHT}%-68s${R}  ${PRP}${BOLD}║${R}\n" "$i" "$s"
        (( i++ ))
    done

    _sep
    _hdr "📡  Monitoring & Health Checks"
    _sep
    local mon_steps=(
        "server_status                 quick overview of the whole server"
        "pm2 monit                     live Node.js process monitor (CPU/RAM)"
        ""
        "🗄️  CENTRALIZED LOGGING VIA CLICKHOUSE (2-DAY RETENTION):"
        "ch_pm2 [app]                  view PM2 logs from ClickHouse"
        "ch_errors [app]               view error logs only"
        "ch_system                     view system logs (syslog, auth, kern)"
        "ch_nginx                      view Nginx access logs"
        "ch_stats                      show log count & storage usage"
        ""
        "pm2 logs                      tail LIVE all app logs (local files)"
        "plog_app <app-name>           view last 100 lines for ONE app only"
        "plog_errors                   view recent errors from all apps"
    )
    for s in "${mon_steps[@]}"; do
        [[ -z "$s" ]] && { printf "  ${PRP}${BOLD}║${R}\n"; continue; }
        printf "  ${PRP}${BOLD}║${R}  ${CYN}›${R}  ${WHT}%-70s${R}  ${PRP}${BOLD}║${R}\n" "$s"
    done

    _sep
    _hdr "📊 GRAFANA DASHBOARDS (Professional Monitoring Platform)"
    _sep
    local graf_header=(
        "🔗 Access:  ssh -L 13001:localhost:13001 \${USERNAME}@<server-ip>"
        "           http://localhost:13001  (admin/admin on first login)"
        ""
        "┌─────────────────────────────────────────────────────────┐"
        "│ 🖥️  SYSTEM FOLDER                                        │"
        "├─────────────────────────────────────────────────────────┤"
        "│ Status:     Infrastructure Monitoring & System Events    │"
        "│ Dashboards:                                             │"
        "│  1. System — Log Viewer                                 │"
        "│     • System messages (syslog) - OS-level events       │"
        "│     • Authentication logs - Security & access tracking │"
        "│     • Kernel logs - Hardware & driver messages         │"
        "│                                                         │"
        "│  2. Node Exporter — System Metrics                      │"
        "│     • CPU utilization & load average                  │"
        "│     • Memory (RAM) usage & swap                        │"
        "│     • Disk I/O & space utilization                     │"
        "│     • Network traffic & connections                    │"
        "└─────────────────────────────────────────────────────────┘"
        ""
        "┌─────────────────────────────────────────────────────────┐"
        "│ ⚙️  APPLICATIONS FOLDER                                 │"
        "├─────────────────────────────────────────────────────────┤"
        "│ Status:     Node.js App Processes & Activity Logs       │"
        "│ Dashboards:                                             │"
        "│  1. PM2 — Process Monitor (Real-time)                  │"
        "│     • App status - Online/offline state per app        │"
        "│     • Resource usage - CPU & memory per app            │"
        "│     • Reliability metrics - Uptime & restart counts    │"
        "│     • Instance tracking - Replicas & scaling           │"
        "│     • 10-second refresh rate - Live updates            │"
        "│                                                         │"
        "│  2. Applications — Log Viewer (Real-time)              │"
        "│     • PM2 app output - Application stdout logs         │"
        "│     • Nginx HTTPlogs - Web server access & errors      │"
        "│     • 30-second refresh - Near real-time visibility   │"
        "│                                                         │"
        "│  3. Loki — Log Explorer (Query Interface)              │"
        "│     • Free-form log searching - Find issues instantly  │"
        "│     • Multiple data sources - PM2, Nginx, system       │"
        "│     • Debugging aid - Trace request flows & errors     │"
        "└─────────────────────────────────────────────────────────┘"
        ""
        "┌─────────────────────────────────────────────────────────┐"
        "│ 📋 LOGS FOLDER (Real-time Analytics)                    │"
        "├─────────────────────────────────────────────────────────┤"
        "│ Status:     ClickHouse Log Analytics (2-day retention)  │"
        "│ Dashboards:                                             │"
        "│  1. Overview — Health Dashboard                        │"
        "│     • Total logs KPI - Volume tracking                 │"
        "│     • Error rate card - Success vs failure ratio       │"
        "│     • Error trends - Time-series visualization         │"
        "│     • Log distribution - By type & severity            │"
        "│     • Top apps chart - Highest activity apps           │"
        "│     • Health scores - Per-application scoring          │"
        "│                                                         │"
        "│  2. Error Analysis — Deep Dive Dashboard               │"
        "│     • Error count & rate - Volume & velocity           │"
        "│     • Error trend chart - Over time analysis            │"
        "│     • Log levels - Distribution breakdown              │"
        "│     • Apps with errors - Error density per app         │"
        "│     • Error rate by app - Comparative view             │"
        "│     • Recent errors table - Last 100 incidents         │"
        "│                                                         │"
        "│  3. App Health — Availability Dashboard                │"
        "│     • Health scores - Computed per-app metric           │"
        "│     • Log volume tracking - Activity levels             │"
        "│     • Availability by app - Uptime percentage           │"
        "│     • Activity patterns - Traffic & usage trends        │"
        "│     • Recent issues - New problems summary              │"
        "│                                                         │"
        "│     Auto-refresh: 30 seconds                           │"
        "│     Data retention: 2 days in ClickHouse               │"
        "└─────────────────────────────────────────────────────────┘"
    )
    for s in "${graf_header[@]}"; do
        [[ -z "$s" ]] && { printf "  ${PRP}${BOLD}║${R}\n"; continue; }
        printf "  ${PRP}${BOLD}║${R}  ${WHT}%-70s${R}  ${PRP}${BOLD}║${R}\n" "$s"
    done

    _sep
    _hdr "🎯 Quick Dashboard Access Guide"
    _sep
    local quick_guide=(
        "SELECT what to monitor:                                  "
        ""
        "👉 Real-time app monitoring?"
        "   → Use 'PM2 — Process Monitor' (⚙️  Applications folder)"
        "   • Shows live CPU, memory, status"
        "   • 10-second updates"
        ""
        "👉 Find app errors or debug issues?"
        "   → Use 'Loki — Log Explorer' (⚙️  Applications folder)"
        "   • Search logs by app, keyword, or time"
        "   • Drill into specific incidents"
        ""
        "👉 Analyze error patterns & trends?"
        "   → Use 'Error Analysis' (📋 Logs folder)"
        "   • See error rate over time"
        "   • Identify problematic apps"
        "   • Heatmaps & distribution charts"
        ""
        "👉 Check system health & resources?"
        "   → Use 'System — Log Viewer' (🖥️  System folder)"
        "   • OS events & kernel logs"
        "   • Authentication activity"
        ""
        "👉 Get overview of everything?"
        "   → Use 'Overview' (📋 Logs folder)"
        "   • KPI cards with key metrics"
        "   • Top apps & health scores"
        "   • Dashboard at a glance"
    )
    for s in "${quick_guide[@]}"; do
        [[ -z "$s" ]] && { printf "  ${PRP}${BOLD}║${R}\n"; continue; }
        printf "  ${PRP}${BOLD}║${R}  ${WHT}%-70s${R}  ${PRP}${BOLD}║${R}\n" "$s"
    done

    _sep
    _hdr "ClickHouse Web UI (Advanced SQL Queries)"
    _sep
    cat <<'CHUI'
  ║  Optional: Access ClickHouse directly for custom analysis
  ║  
  ║  ssh -L 17123:localhost:17123 ${USERNAME}@<server-ip>
  ║  http://localhost:17123/play
  ║  
  ║  Built-in queries for:
  ║   • Log count by app             • Error distribution
  ║   • Log volume trends            • Recent 100 records per app
CHUI

    _sep
    _hdr "🚀  PM2 App Configuration (Separate Logs per App)"
    _sep
    local pm2_config_steps=(
        "1. Edit ecosystem config:  nano ~/.pm2/ecosystem.config.js"
        "   (Copy from ~/.pm2/ecosystem.template.js and customize per app)"
        ""
        "2. Each app in ecosystem.config.js gets separate logging:"
        "   ✓ output file  — app's stdout logs (auto-shipped to ClickHouse)"
        "   ✓ error file   — app's stderr/errors only (auto-shipped)"
        "   ✓ log_date_format — timestamps on every line"
        ""
        "3. Start apps from ecosystem config:"
        "   pm2 start ecosystem.config.js"
        ""
        "4. View Logs (3 methods):"
        "   CLI:      ch_pm2, ch_errors, ch_system, ch_stats"
        "   LIVE:     pm2 logs, plog_app <app>, plog_errors"
        "   DASHBOARD: Grafana :13001 → See above for each dashboard"
        ""
        "5. Log Analytics (Real-time Dashboards — Automatically Generated):"
        "   📊 Logs — Overview          KPI metrics, error rate, success rate, trends"
        "   ⚠️  Logs — Error Analysis    Error patterns, incidents, deep dive analysis"
        "   💚 Logs — App Health         Health scores, availability, activity per app"
        ""
        "6. Automated Log Management:"
        "   • Logs shipped to ClickHouse every 5 seconds"
        "   • Local files auto-deleted after 30 min (saves disk)"
        "   • ClickHouse 2-day TTL — auto-delete old analytics"
        "   • Zero manual cleanup needed"
        ""
        "7. Log Lifecycle:"
        "   Created → Local storage (30 min) → ClickHouse → Auto-delete"
        "   Total retention: 2 days in ClickHouse (real-time analytics)"
    )
    for s in "${pm2_config_steps[@]}"; do
        [[ -z "$s" ]] && { printf "  ${PRP}${BOLD}║${R}\n"; continue; }
        printf "  ${PRP}${BOLD}║${R}  ${WHT}%-70s${R}  ${PRP}${BOLD}║${R}\n" "$s"
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
        printf "  ${PRP}${BOLD}║${R}  ${GRN}·${R}  ${WHT}%-70s${R}  ${PRP}${BOLD}║${R}\n" "$s"
    done

    _sep
    printf  "  ${PRP}${BOLD}║${R}${GRY}%-76s${R}${PRP}${BOLD}║${R}\n" \
            "  Log file: ${LOG_FILE}"
    echo -e "${PRP}${BOLD}  ╚${HR2}╝${R}"
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