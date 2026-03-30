#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  docker.sh  —  Docker CE + Monitoring Integration  v1.0.0                   ║
# ║  Ubuntu 20.04 / 22.04 / 24.04 LTS                                           ║
# ╠══════════════════════════════════════════════════════════════════════════════╣
# ║                                                                              ║
# ║  COMPANION TO: init.sh (Node.js Production Server Provisioner)               ║
# ║  Requires Prometheus + Grafana already installed by init.sh                  ║
# ║                                                                              ║
# ║  WHAT THIS DOES                                                              ║
# ║  01. Preflight — checks OS, root, init.sh components                        ║
# ║  02. Install Docker CE (latest stable) + CLI + containerd + Buildx           ║
# ║  03. Install Docker Compose v2 plugin                                        ║
# ║  04. Configure optimized daemon.json (BuildKit, log rotation, live-restore)  ║
# ║  05. Add deploy user to docker group (no sudo needed)                        ║
# ║  06. Install ecosystem tools: ctop, Lazydocker, Docker Scout                 ║
# ║  07. Enable bash completion for docker & compose                              ║
# ║  08. Enable Docker daemon metrics endpoint (:9323) for Prometheus             ║
# ║  09. Deploy cAdvisor container — per-container CPU/RAM/net/disk metrics       ║
# ║  10. Deploy Loki container — Docker log aggregation backend (:3100)           ║
# ║  11. Deploy Promtail container — reads /var/lib/docker/containers logs        ║
# ║  12. Patch /etc/prometheus/prometheus.yml — add docker_engine + cadvisor     ║
# ║      NOTE: node_exporter scrape already exists from init.sh — not touched    ║
# ║  13. Provision Loki datasource in Grafana (/etc/grafana/provisioning)         ║
# ║  14. Download & provision Docker dashboards → /var/lib/grafana/dashboards/   ║
# ║  15. Reload Prometheus + Grafana — no restarts, live reload                  ║
# ║  16. Smoke test + full verification + summary                                 ║
# ║                                                                              ║
# ╠══════════════════════════════════════════════════════════════════════════════╣
# ║                                                                              ║
# ║  USAGE                                                                       ║
# ║    sudo ./docker.sh                     (runs everything)                    ║
# ║    sudo ./docker.sh --no-mon            (skip monitoring integration)         ║
# ║    sudo ./docker.sh --no-loki           (skip Loki/Promtail log pipeline)    ║
# ║    sudo ./docker.sh -u <username>       (specify deploy user)                 ║
# ║    sudo ./docker.sh -h                  (show this help)                      ║
# ║                                                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set -euo pipefail
IFS=$'\n\t'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  CONFIG — paths match init.sh exactly
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

readonly SCRIPT_VERSION="1.0.0"
readonly LOG_FILE="/var/log/docker_provision.log"

# ── init.sh-installed component paths (do not change) ─────────────────────────
readonly PROMETHEUS_CONFIG="/etc/prometheus/prometheus.yml"   # written by init.sh
readonly PROMETHEUS_URL="http://127.0.0.1:9090"               # bound by init.sh
readonly GRAFANA_PROVISIONING="/etc/grafana/provisioning"     # init.sh standard path
readonly GRAFANA_DASH_DIR="/var/lib/grafana/dashboards"       # init.sh dashboard dir
readonly GRAFANA_URL="http://127.0.0.1:13001"                 # init.sh configures port 13001

# ── Docker monitoring stack ────────────────────────────────────────────────────
readonly MONITORING_DIR="/opt/docker-monitoring"
readonly DOCKER_METRICS_PORT=9323      # Docker daemon metrics
readonly CADVISOR_PORT=8080            # Per-container metrics
readonly LOKI_PORT=3100                # Log backend
readonly PROMTAIL_STATUS_PORT=9080        # Promtail health endpoint (standalone Docker network)
readonly PROMTAIL_DOCKER_STATUS_PORT=9081 # Promtail-docker health endpoint (host-network mode — avoids clash with native Promtail on :9080)
# node_exporter :9100 is already running from init.sh — we never touch it

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  COLORS (identical to init.sh)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [[ -t 1 ]] && tput colors &>/dev/null && (( $(tput colors) >= 8 )); then
    R=$'\033[0m'  BOLD=$'\033[1m'  DIM=$'\033[2m'
    GRN=$'\033[38;5;82m'   BLU=$'\033[38;5;33m'   CYN=$'\033[38;5;45m'
    YLW=$'\033[38;5;220m'
    WHT=$'\033[38;5;255m'  GRY=$'\033[38;5;244m'  RED=$'\033[38;5;196m'
    TICK="${GRN}✔${R}"  CROSS="${RED}✘${R}"  WARN_IC="${YLW}⚠${R}"
    ARROW="${CYN}›${R}"
else
    R='' BOLD='' DIM='' GRN='' BLU='' CYN='' YLW='' WHT='' GRY='' RED=''
    TICK='[OK]' CROSS='[ERR]' WARN_IC='[WARN]' ARROW='->'
fi

readonly HR2="════════════════════════════════════════════════════════════════════════════"
readonly HR="────────────────────────────────────────────────────────────────────────────"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  OUTPUT (identical to init.sh)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

_log()  { printf '[%s] [%-5s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >> "$LOG_FILE" 2>/dev/null || true; }
ok()    { echo -e "  ${TICK}  $*";              _log INFO  "$*"; }
warn()  { echo -e "  ${WARN_IC}  ${YLW}$*${R}"; _log WARN  "$*"; }
info()  { echo -e "  ${ARROW}  ${GRY}$*${R}";   _log INFO  "$*"; }
die()   { echo -e "\n  ${CROSS}  ${RED}${BOLD}FATAL: $*${R}\n" >&2; _log ERROR "$*"; exit 1; }

section()     { echo ""; echo -e "  ${BLU}${BOLD}┌─ $1 / $2${R}"; echo -e "  ${BLU}${DIM}│${R}"; }
section_end() { echo -e "  ${BLU}${DIM}└${HR:0:60}${R}"; }

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  PARSE ARGS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

parse_args() {
    DEPLOY_USER="${SUDO_USER:-}"   # default: the user who ran sudo
    SETUP_MON=true                  # --no-mon disables monitoring integration
    SETUP_LOKI=true                 # --no-loki disables Loki/Promtail
    NATIVE_LOKI=false               # set to true at runtime when init.sh's native Loki is detected

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u)        DEPLOY_USER="${2:?}"; shift 2 ;;
            --no-mon)  SETUP_MON=false;      shift ;;
            --no-loki) SETUP_LOKI=false;     shift ;;
            -h|--help) usage ;;
            *) die "Unknown option: '$1'. Use -h for help." ;;
        esac
    done
}

usage() {
    clear
    echo ""
    echo -e "${BLU}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${BLU}${BOLD}║${R}${WHT}${BOLD}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  🐳  docker.sh  —  Docker CE + Monitoring Integration  v${SCRIPT_VERSION}"
    printf  "  ${BLU}${BOLD}║${R}${GRY}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  Companion to init.sh  ·  Ubuntu 20.04 / 22.04 / 24.04 LTS"
    echo -e "${BLU}${BOLD}  ╚${HR2}╝${R}"
    echo ""
    echo -e "  ${BOLD}${WHT}Usage${R}"
    echo -e "  ${GRY}${HR:0:60}${R}"
    echo -e "    ${CYN}sudo ./docker.sh${R}               ${GRY}# run everything (recommended)${R}"
    echo -e "    ${CYN}sudo ./docker.sh -u <user>${R}     ${GRY}# specify deploy username${R}"
    echo -e "    ${CYN}sudo ./docker.sh --no-mon${R}      ${GRY}# skip monitoring integration${R}"
    echo -e "    ${CYN}sudo ./docker.sh --no-loki${R}     ${GRY}# skip Loki/Promtail log pipeline${R}"
    echo -e "    ${CYN}sudo ./docker.sh -h${R}            ${GRY}# show this help${R}"
    echo ""
    exit 0
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  BANNER
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

show_banner() {
    clear
    echo ""
    echo -e "${BLU}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${BLU}${BOLD}║${R}${WHT}${BOLD}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  🐳  docker.sh  —  Docker CE + Full Monitoring Integration  v${SCRIPT_VERSION}"
    printf  "  ${BLU}${BOLD}║${R}${GRY}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  Docker · Compose v2 · BuildKit · cAdvisor · Loki · Grafana · Prometheus"
    echo -e "${BLU}${BOLD}  ╠${HR2}╣${R}"
    printf  "  ${BLU}${BOLD}║${R}${GRY}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  Companion to init.sh — integrates with your existing Prometheus + Grafana"
    printf  "  ${BLU}${BOLD}║${R}${GRY}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  node_exporter already running from init.sh — will NOT be touched"
    echo -e "${BLU}${BOLD}  ╚${HR2}╝${R}"
    echo ""
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  01 — PREFLIGHT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

preflight() {
    section "01" "Preflight Checks"

    [[ $EUID -eq 0 ]] || die "Must run as root:  sudo ./docker.sh"
    ok "Running as root."

    # OS check
    [[ -f /etc/os-release ]] && { source /etc/os-release; ok "OS: ${PRETTY_NAME:-Linux}"; }
    case "${ID:-}" in
        ubuntu|debian) ;;
        *) die "Unsupported OS: ${ID:-unknown}. Requires Ubuntu or Debian." ;;
    esac

    # Resolve deploy user
    if [[ -z "${DEPLOY_USER}" || "${DEPLOY_USER}" == "root" ]]; then
        # Try to find the user created by init.sh by checking /home
        local found_user
        found_user=$(ls /home 2>/dev/null | head -1 || true)
        if [[ -n "${found_user}" ]]; then
            DEPLOY_USER="${found_user}"
            warn "No user specified. Detected: '${DEPLOY_USER}' — use -u <name> to override."
        else
            DEPLOY_USER="root"
            warn "No deploy user found. Docker group will not be configured. Use -u <name>."
        fi
    fi
    ok "Deploy user: ${WHT}${BOLD}${DEPLOY_USER}${R}"

    # Check init.sh components if monitoring is requested
    if $SETUP_MON; then
        if [[ ! -f "${PROMETHEUS_CONFIG}" ]]; then
            warn "Prometheus config not found at ${PROMETHEUS_CONFIG}."
            warn "Run init.sh first, or use --no-mon to skip monitoring integration."
            warn "Continuing with Docker install only — monitoring steps will be skipped."
            SETUP_MON=false
        else
            ok "Prometheus config found: ${PROMETHEUS_CONFIG}"
        fi

        if [[ ! -d "${GRAFANA_PROVISIONING}" ]]; then
            warn "Grafana provisioning dir not found at ${GRAFANA_PROVISIONING}."
            warn "Monitoring integration will be skipped."
            SETUP_MON=false
        else
            ok "Grafana provisioning dir found: ${GRAFANA_PROVISIONING}"
        fi

        if systemctl is-active --quiet node_exporter 2>/dev/null; then
            ok "node_exporter already running (init.sh) — will not be reinstalled."
        else
            warn "node_exporter not detected. Run init.sh first for full monitoring."
        fi
    fi

    check_dependencies

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  DEPENDENCY CHECK + AUTO-INSTALL
#  Verifies all tools required before Docker installation begins.
#  Missing packages are installed automatically so the script can continue.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

check_dependencies() {
    info "Checking required tools and libraries..."

    # Always apt on Ubuntu/Debian (already validated above)
    DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null || true

    # ── Helper ───────────────────────────────────────────────────────────────
    _pkg_install() {
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$1" \
            2>&1 | grep -E '(Setting up|already installed)' || true
    }

    # ── 1. bash >= 4 ─────────────────────────────────────────────────────────
    local bash_ver="${BASH_VERSINFO[0]:-0}"
    if (( bash_ver < 4 )); then
        die "Bash 4+ required (found bash ${bash_ver}). Install a newer bash first."
    fi
    ok "bash ${BASH_VERSION} — ok"

    # ── 2. curl (Docker GPG key download, image pulls) ────────────────────────
    if command -v curl &>/dev/null; then
        ok "curl $(curl --version 2>/dev/null | head -1 | awk '{print $2}') — ok"
    else
        warn "curl not found — installing..."
        _pkg_install curl
        command -v curl &>/dev/null && ok "curl installed." \
            || die "Failed to install curl. Install it manually and re-run."
    fi

    # ── 3. gnupg (Docker repo signing key) ───────────────────────────────────
    if command -v gpg &>/dev/null; then
        ok "gnupg — ok"
    else
        warn "gnupg not found — installing..."
        _pkg_install gnupg
        command -v gpg &>/dev/null && ok "gnupg installed." \
            || die "Failed to install gnupg. Install it manually and re-run."
    fi

    # ── 4. lsb-release (OS codename for Docker repo URL) ─────────────────────
    if command -v lsb_release &>/dev/null; then
        ok "lsb-release — ok"
    else
        warn "lsb-release not found — installing..."
        _pkg_install lsb-release
        command -v lsb_release &>/dev/null && ok "lsb-release installed." \
            || warn "lsb-release not available — Docker repo setup may fail."
    fi

    # ── 5. ca-certificates (HTTPS connections) ───────────────────────────────
    if dpkg -l ca-certificates &>/dev/null 2>&1; then
        ok "ca-certificates — ok"
    else
        info "ca-certificates not found — installing..."
        _pkg_install ca-certificates
        ok "ca-certificates installed."
    fi

    # ── 6. jq (JSON config parsing — Prometheus/Grafana patching) ────────────
    if command -v jq &>/dev/null; then
        ok "jq $(jq --version 2>/dev/null) — ok"
    else
        info "jq not found — installing..."
        _pkg_install jq
        command -v jq &>/dev/null && ok "jq installed." \
            || warn "jq not available — JSON config steps will use sed fallbacks."
    fi

    # ── 7. wget (fallback downloader) ────────────────────────────────────────
    if command -v wget &>/dev/null; then
        ok "wget — ok"
    else
        info "wget not found — installing (fallback downloader)..."
        _pkg_install wget
        command -v wget &>/dev/null && ok "wget installed." \
            || warn "wget not available — curl will be used exclusively."
    fi

    # ── 8. coreutils: awk, grep, sed, cut, sort ──────────────────────────────
    local core_ok=true
    for _tool in awk grep sed cut sort; do
        if ! command -v "$_tool" &>/dev/null; then
            warn "Missing coreutil: ${_tool}"
            core_ok=false
        fi
    done
    if $core_ok; then
        ok "coreutils (awk, grep, sed, cut, sort) — ok"
    else
        warn "Some coreutils missing — installing..."
        _pkg_install coreutils
    fi

    # ── 9. systemctl (Docker service management) ─────────────────────────────
    if command -v systemctl &>/dev/null; then
        ok "systemctl — ok"
    elif command -v service &>/dev/null; then
        ok "service (SysV init) — ok"
    else
        warn "No systemctl or service found — Docker service management may require manual steps."
    fi

    ok "Dependency check complete — all required tools are available."
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  02 — REMOVE OLD / CONFLICTING DOCKER PACKAGES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

remove_old_docker() {
    section "02" "Remove Conflicting Packages"

    if command -v docker &>/dev/null; then
        local cur_ver
        cur_ver=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
        warn "Docker already installed (${cur_ver}) — upgrading to latest stable."
    else
        info "No existing Docker installation found. Fresh install."
    fi

    local OLD_PKGS=(
        docker docker-engine docker.io containerd runc
        docker-doc docker-compose docker-compose-v2 podman-docker
    )
    apt-get remove -y "${OLD_PKGS[@]}" 2>/dev/null || true
    ok "Conflicting packages removed (or were not present)."

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  03 — SYSTEM PREREQUISITES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

install_prerequisites() {
    section "03" "System Prerequisites"

    apt-get update -qq
    apt-get install -y \
        ca-certificates curl gnupg lsb-release \
        apt-transport-https software-properties-common \
        wget git jq make bash-completion
    ok "Prerequisites installed (curl, gnupg, jq, lsb-release, etc.)"

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  04 — DOCKER OFFICIAL REPOSITORY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

add_docker_repo() {
    section "04" "Docker Official APT Repository"

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${ID}/gpg" \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    ok "Docker GPG key added to /etc/apt/keyrings/docker.gpg"

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${ID} $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    ok "Official Docker APT repository configured."
    info "Source: download.docker.com/linux/${ID}  channel: stable"

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  05 — INSTALL DOCKER CE + CLI + CONTAINERD + BUILDX + COMPOSE V2
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

install_docker_ce() {
    section "05" "Docker CE + Compose v2 + BuildX + containerd"

    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    ok "Docker CE installed:    $(docker --version)"
    ok "Docker Compose:        $(docker compose version)"
    ok "Docker Buildx:         $(docker buildx version)"
    ok "containerd:            $(containerd --version)"
    ok "Docker service:         enabled + running via systemd"

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  06 — DAEMON.JSON — optimized production config + metrics endpoint
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

configure_daemon() {
    section "06" "Docker Daemon Configuration (daemon.json)"

    mkdir -p /etc/docker

    # Backup if exists
    if [[ -f /etc/docker/daemon.json ]]; then
        cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date +%s)"
        info "Existing daemon.json backed up."
    fi

    cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "5"
  },
  "storage-driver": "overlay2",
  "features": {
    "buildkit": true
  },
  "live-restore": true,
  "metrics-addr": "127.0.0.1:${DOCKER_METRICS_PORT}",
  "experimental": true,
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  }
}
EOF

    systemctl restart docker
    sleep 3

    ok "daemon.json written with:"
    info "  log rotation: 20MB × 5 files per container"
    info "  storage:      overlay2 (best performance on modern kernels)"
    info "  BuildKit:     enabled (faster, parallel, cached builds)"
    info "  live-restore: enabled (containers survive daemon restart)"
    info "  ulimits:      nofile=64000 (Node.js-friendly file descriptor limit)"
    info "  metrics-addr: 127.0.0.1:${DOCKER_METRICS_PORT} (Prometheus scrape endpoint — loopback only)"

    if curl -sf "http://localhost:${DOCKER_METRICS_PORT}/metrics" | grep -q "engine_daemon" 2>/dev/null; then
        ok "Docker metrics endpoint live → :${DOCKER_METRICS_PORT}/metrics"
    else
        warn "Docker metrics endpoint not responding yet — may still be starting."
    fi

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  07 — DEPLOY USER → DOCKER GROUP
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

add_user_to_docker_group() {
    section "07" "Docker Group — No-Sudo Access for ${DEPLOY_USER}"

    if [[ "${DEPLOY_USER}" == "root" ]]; then
        warn "Running as root — skipping group addition."
        warn "Run:  usermod -aG docker <your-username>"
        section_end; return
    fi

    if ! id "${DEPLOY_USER}" &>/dev/null; then
        warn "User '${DEPLOY_USER}' not found on this system."
        warn "Run init.sh first to create the deploy user, then re-run this script."
        section_end; return
    fi

    usermod -aG docker "${DEPLOY_USER}"
    ok "User '${DEPLOY_USER}' added to docker group."
    info "Run 'newgrp docker' or re-login to apply group membership."
    info "After that: docker ps  (no sudo needed)"

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  08 — ECOSYSTEM TOOLS (ctop, Lazydocker, Docker Scout)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

install_ecosystem_tools() {
    section "08" "Ecosystem Tools — ctop + Lazydocker + Docker Scout"

    local ARCH
    ARCH=$(dpkg --print-architecture)
    [[ "${ARCH}" == "amd64" ]] && ARCH="amd64" || ARCH="arm64"

    # ── ctop — container resource monitor ─────────────────────────────────────
    info "Installing ctop (live container resource monitor)..."
    local CTOP_VER
    CTOP_VER=$(curl -sf https://api.github.com/repos/bcicen/ctop/releases/latest \
        | jq -r '.tag_name' 2>/dev/null || echo "v0.7.7")
    curl -fsSL \
        "https://github.com/bcicen/ctop/releases/download/${CTOP_VER}/ctop-${CTOP_VER#v}-linux-${ARCH}" \
        -o /usr/local/bin/ctop 2>/dev/null \
        && chmod +x /usr/local/bin/ctop \
        && ok "ctop ${CTOP_VER} installed → /usr/local/bin/ctop" \
        || warn "ctop install skipped (network issue) — install manually from github.com/bcicen/ctop"

    # ── Lazydocker — full terminal UI ─────────────────────────────────────────
    info "Installing Lazydocker (interactive Docker TUI)..."
    curl -fsSL \
        https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh \
        | bash 2>/dev/null \
        && ok "Lazydocker installed." \
        || warn "Lazydocker install skipped — github.com/jesseduffield/lazydocker"

    # ── Docker Scout — vulnerability scanner ──────────────────────────────────
    info "Installing Docker Scout CLI (vulnerability scanner)..."
    curl -fsSL https://raw.githubusercontent.com/docker/scout-cli/main/install.sh \
        | sh -s -- -b /usr/local/bin 2>/dev/null \
        && ok "Docker Scout CLI installed → docker scout quickview <image>" \
        || warn "Docker Scout install skipped — docs.docker.com/scout"

    # ── Bash completion ────────────────────────────────────────────────────────
    info "Enabling bash completion for docker & docker compose..."
    curl -fsSL \
        "https://raw.githubusercontent.com/docker/cli/master/contrib/completion/bash/docker" \
        -o /etc/bash_completion.d/docker 2>/dev/null \
        && ok "Bash completion enabled for docker and docker compose." \
        || warn "Bash completion download skipped (network issue)."

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  09 — CADVISOR — per-container metrics container
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

deploy_cadvisor() {
    section "09" "cAdvisor — Per-Container Metrics (:${CADVISOR_PORT})"

    # Stop + remove existing instance if any
    docker rm -f cadvisor 2>/dev/null || true

    docker run -d \
        --name cadvisor \
        --restart unless-stopped \
        --privileged \
        -p "127.0.0.1:${CADVISOR_PORT}:8080" \
        -v /:/rootfs:ro \
        -v /var/run:/var/run:ro \
        -v /sys:/sys:ro \
        -v /var/lib/docker/:/var/lib/docker:ro \
        -v /dev/disk/:/dev/disk:ro \
        -v /etc/machine-id:/etc/machine-id:ro \
        --device /dev/kmsg \
        --health-cmd='curl -sf http://127.0.0.1:8080/healthz || exit 1' \
        --health-interval=15s \
        --health-timeout=5s \
        --health-retries=3 \
        --health-start-period=20s \
        gcr.io/cadvisor/cadvisor:latest \
        --housekeeping_interval=10s \
        --docker_only=true \
        --store_container_labels=true \
        --disable_metrics=disk,tcp,udp,percpu,sched,process \
        > /dev/null 2>&1 || die "Failed to start cAdvisor container"

    sleep 5
    if docker ps --filter "name=cadvisor" --filter "status=running" | grep -q cadvisor; then
        ok "cAdvisor container running → http://127.0.0.1:${CADVISOR_PORT}/metrics"
        info "Exposes: CPU, RAM, network I/O, disk I/O per container — all labels preserved"
    else
        warn "cAdvisor container did not start cleanly: docker logs cadvisor"
    fi

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  10 — LOKI + PROMTAIL — Docker log aggregation
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

deploy_loki_promtail() {
    if ! $SETUP_LOKI; then
        section "10" "Loki + Promtail"; warn "Skipped (--no-loki)."; section_end; return
    fi

    section "10" "Loki + Promtail — Docker Log Pipeline"

    # ── Detect native Loki (installed by init.sh ≥ v7.0.0) ───────────────────
    # When init.sh has already installed a native Loki service we must NOT deploy
    # an additional Loki Docker container — it would fail to bind port 3100.
    # Instead we route the Docker Promtail container to the native Loki service
    # using host networking so it can reach 127.0.0.1:3100 directly.
    NATIVE_LOKI=false
    if systemctl is-active --quiet loki 2>/dev/null; then
        NATIVE_LOKI=true
        info "Native Loki service detected (init.sh ≥ v7.0.0) — skipping Loki container."
        info "Docker Promtail will push to native Loki on 127.0.0.1:${LOKI_PORT}."
    fi

    mkdir -p "${MONITORING_DIR}"/{loki,promtail,data/loki}
    chmod 777 "${MONITORING_DIR}/data/loki"

    # ── Loki config (only used when deploying the Docker container) ───────────
    cat > "${MONITORING_DIR}/loki/loki-config.yml" <<'LOKICFG'
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory:  /loki/rules
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
  retention_period: 744h       # 31 days
  ingestion_rate_mb: 16
  ingestion_burst_size_mb: 32

compactor:
  working_directory: /loki/compactor
  retention_enabled: true
  delete_request_store: filesystem
LOKICFG

    # ── Promtail config ────────────────────────────────────────────────────────
    # When native Loki is running, Promtail uses --network=host so it can reach
    # 127.0.0.1:3100 directly.  Otherwise it talks to the "loki" container name
    # via the shared Docker monitoring network.
    # NOTE: in host-network mode we use PROMTAIL_DOCKER_STATUS_PORT (9081) to
    # avoid a port conflict with the native Promtail service already bound to 9080.
    local loki_push_url
    local promtail_http_port
    if $NATIVE_LOKI; then
        loki_push_url="http://127.0.0.1:${LOKI_PORT}/loki/api/v1/push"
        promtail_http_port=${PROMTAIL_DOCKER_STATUS_PORT}
    else
        loki_push_url="http://loki:3100/loki/api/v1/push"
        promtail_http_port=${PROMTAIL_STATUS_PORT}
    fi

    cat > "${MONITORING_DIR}/promtail/promtail-config.yml" <<PTCFG
server:
  http_listen_port: ${promtail_http_port}
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: ${loki_push_url}

scrape_configs:

  # ── All Docker container logs ──────────────────────────────────────────────
  - job_name: docker_containers
    static_configs:
      - targets: [localhost]
        labels:
          job:  docker
          host: $(hostname)
          __path__: /var/lib/docker/containers/*/*-json.log

    pipeline_stages:
      - json:
          expressions:
            output: log
            stream: stream
            time:   time
      - docker: {}
      - timestamp:
          source: time
          format: RFC3339Nano
      - labels:
          stream:
          container_id:
      - drop:
          expression: '^\s*$'
          drop_counter_reason: empty_log_line
      - output:
          source: output

  # ── Docker daemon systemd journal ─────────────────────────────────────────
  - job_name: journal_docker
    journal:
      max_age: 12h
      labels:
        job: docker_daemon
      matches: _SYSTEMD_UNIT=docker.service
    relabel_configs:
      - source_labels: [__journal__systemd_unit]
        target_label: unit
      - source_labels: [__journal_priority_keyword]
        target_label: level
PTCFG

    # ── Stop + remove any existing instances ───────────────────────────────────
    docker rm -f promtail promtail-docker 2>/dev/null || true
    if ! $NATIVE_LOKI; then
        docker rm -f loki 2>/dev/null || true
    fi

    # Create shared network for loki ↔ promtail communication (skipped when using host network)
    if ! $NATIVE_LOKI; then
        docker network create monitoring 2>/dev/null || true
    fi

    # ── Deploy Loki (only when native Loki is NOT running) ────────────────────
    if ! $NATIVE_LOKI; then
        docker run -d \
            --name loki \
            --restart unless-stopped \
            --network monitoring \
            -p "127.0.0.1:${LOKI_PORT}:3100" \
            -v "${MONITORING_DIR}/loki/loki-config.yml:/etc/loki/local-config.yaml:ro" \
            -v "${MONITORING_DIR}/data/loki:/loki" \
            --health-cmd='curl -sf http://127.0.0.1:3100/ready || exit 1' \
            --health-interval=10s \
            --health-timeout=5s \
            --health-retries=3 \
            --health-start-period=30s \
            grafana/loki:latest \
            -config.file=/etc/loki/local-config.yaml \
            > /dev/null 2>&1 || die "Failed to start Loki container"

        # ── Wait for Loki ready ────────────────────────────────────────────────────
        info "Waiting for Loki to become ready..."
        local retries=0
        until curl -sf "http://127.0.0.1:${LOKI_PORT}/ready" 2>/dev/null | grep -q "ready" \
            || (( retries++ >= 18 )); do
            sleep 3; printf "."
        done; echo ""

        if curl -sf "http://127.0.0.1:${LOKI_PORT}/ready" 2>/dev/null | grep -q "ready"; then
            ok "Loki is ready → http://127.0.0.1:${LOKI_PORT}"
            info "Log retention: 31 days  |  Storage: ${MONITORING_DIR}/data/loki"
        else
            warn "Loki may still be starting: docker logs loki"
        fi
    else
        ok "Using native Loki service → http://127.0.0.1:${LOKI_PORT}"
    fi

    # ── Deploy Promtail ────────────────────────────────────────────────────────
    # When native Loki is running, use --network=host so Promtail reaches :3100.
    # Use PROMTAIL_DOCKER_STATUS_PORT (9081) as the http_listen_port so it does
    # NOT conflict with the native Promtail service already bound on :9080.
    if $NATIVE_LOKI; then
        docker run -d \
            --name promtail-docker \
            --restart unless-stopped \
            --privileged \
            --network host \
            -v "${MONITORING_DIR}/promtail/promtail-config.yml:/etc/promtail/config.yml:ro" \
            -v /var/lib/docker/containers:/var/lib/docker/containers:ro \
            -v /var/log:/var/log:ro \
            -v /run/log/journal:/run/log/journal:ro \
            -v /etc/machine-id:/etc/machine-id:ro \
            --health-cmd='curl -sf http://127.0.0.1:9081/loki/api/v1/tail || exit 1' \
            --health-interval=15s \
            --health-timeout=5s \
            --health-retries=3 \
            --health-start-period=15s \
            grafana/promtail:latest \
            -config.file=/etc/promtail/config.yml \
            > /dev/null 2>&1 || die "Failed to start Promtail-docker container"
    else
        docker run -d \
            --name promtail \
            --restart unless-stopped \
            --privileged \
            --network monitoring \
            -p "127.0.0.1:${PROMTAIL_STATUS_PORT}:9080" \
            -v "${MONITORING_DIR}/promtail/promtail-config.yml:/etc/promtail/config.yml:ro" \
            -v /var/lib/docker/containers:/var/lib/docker/containers:ro \
            -v /var/log:/var/log:ro \
            -v /run/log/journal:/run/log/journal:ro \
            -v /etc/machine-id:/etc/machine-id:ro \
            --health-cmd='curl -sf http://127.0.0.1:9080/loki/api/v1/tail || exit 1' \
            --health-interval=15s \
            --health-timeout=5s \
            --health-retries=3 \
            --health-start-period=15s \
            grafana/promtail:latest \
            -config.file=/etc/promtail/config.yml \
            > /dev/null 2>&1 || die "Failed to start Promtail container"
    fi

    local promtail_name; $NATIVE_LOKI && promtail_name="promtail-docker" || promtail_name="promtail"
    sleep 4
    if docker ps --filter "name=${promtail_name}" --filter "status=running" | grep -q "${promtail_name}"; then
        ok "Promtail running — collecting logs from all Docker containers."
        info "Reads: /var/lib/docker/containers/*/*-json.log"
        info "Labels: container_name, compose_project, compose_service, stream, host"
    else
        warn "Promtail container issue: docker logs ${promtail_name}"
    fi

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  11 — PATCH PROMETHEUS CONFIG
#  Adds docker_engine + cadvisor scrape jobs.
#  Does NOT add node_exporter — already configured by init.sh.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

patch_prometheus() {
    $SETUP_MON || return

    section "11" "Prometheus — Patching ${PROMETHEUS_CONFIG}"

    # Backup first
    local backup
    backup="${PROMETHEUS_CONFIG}.bak.$(date +%s)"
    cp "${PROMETHEUS_CONFIG}" "${backup}"
    ok "Backup saved: ${backup}"

    local SCRAPE_JOBS='

  # ── Docker daemon engine metrics ─────────────────────────────────────────────
  # Requires: daemon.json "metrics-addr" + "experimental" — configured by docker.sh
  - job_name: '"'"'docker_engine'"'"'
    scrape_interval: 15s
    static_configs:
      - targets: ['"'"'127.0.0.1:9323'"'"']
        labels:
          instance: docker_engine

  # ── cAdvisor — per-container CPU / RAM / net / disk metrics ──────────────────
  - job_name: '"'"'cadvisor'"'"'
    scrape_interval: 10s
    scrape_timeout: 8s
    static_configs:
      - targets: ['"'"'127.0.0.1:8080'"'"']
    metric_relabel_configs:
      # Keep only the most useful container metrics (reduces cardinality)
      - source_labels: [__name__]
        regex: >-
          container_(cpu_usage_seconds_total|memory_usage_bytes|
          memory_working_set_bytes|network_receive_bytes_total|
          network_transmit_bytes_total|fs_reads_bytes_total|
          fs_writes_bytes_total|last_seen|start_time_seconds|
          tasks_state|spec_cpu_quota|spec_memory_limit_bytes|
          oom_events_total)
        action: keep
      # Drop empty/pause containers
      - source_labels: [image]
        regex: '"'"'.*pause.*'"'"'
        action: drop
      # Promote compose labels to metric labels for easy filtering
      - source_labels: [container_label_com_docker_compose_service]
        target_label: compose_service
      - source_labels: [container_label_com_docker_compose_project]
        target_label: compose_project
      - source_labels: [name]
        target_label: container_name'

    # Only add if docker_engine job not already present
    if grep -q "job_name.*docker_engine" "${PROMETHEUS_CONFIG}" 2>/dev/null; then
        warn "Docker scrape jobs already present in prometheus.yml — skipping to avoid duplicates."
    else
        # Ensure scrape_configs: section exists
        if ! grep -q "^scrape_configs:" "${PROMETHEUS_CONFIG}"; then
            echo -e "\nscrape_configs:" >> "${PROMETHEUS_CONFIG}"
        fi
        echo "${SCRAPE_JOBS}" >> "${PROMETHEUS_CONFIG}"
        ok "Appended scrape jobs: docker_engine + cadvisor"
        info "node_exporter job left untouched (already configured by init.sh)"
    fi

    # Validate the config with promtool if available
    if command -v promtool &>/dev/null; then
        if promtool check config "${PROMETHEUS_CONFIG}" &>/dev/null; then
            ok "prometheus.yml syntax validated by promtool."
        else
            warn "prometheus.yml syntax error detected. Restoring backup..."
            cp "${backup}" "${PROMETHEUS_CONFIG}"
            die "Prometheus config invalid. Backup restored: ${backup}"
        fi
    fi

    # Reload Prometheus — try HTTP first (zero downtime), then systemctl
    if curl -sf -X POST "${PROMETHEUS_URL}/-/reload" &>/dev/null; then
        ok "Prometheus reloaded via HTTP API (zero downtime)."
    elif systemctl is-active prometheus &>/dev/null; then
        systemctl reload prometheus 2>/dev/null || systemctl restart prometheus
        ok "Prometheus reloaded via systemctl."
    else
        warn "Could not reload Prometheus automatically."
        warn "Run manually: curl -X POST http://127.0.0.1:9090/-/reload"
    fi

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  12 — GRAFANA DATASOURCE — provision Loki
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

provision_loki_datasource() {
    $SETUP_MON || return
    $SETUP_LOKI || return

    section "12" "Grafana — Loki Datasource Provisioning"

    local DS_DIR="${GRAFANA_PROVISIONING}/datasources"
    mkdir -p "${DS_DIR}"

    # ── CONFLICT RESOLUTION ──────────────────────────────────────────────────
    # Detect if init.sh already provisioned Loki datasource and reuse it
    if [[ -f "${DS_DIR}/loki.yaml" ]]; then
        ok "✓ Loki datasource already provisioned by init.sh — reusing."
        info "  Datasource: ${DS_DIR}/loki.yaml → http://127.0.0.1:${LOKI_PORT}"
        info "  Will not create duplicate loki-docker.yaml"
        section_end; return
    fi

    # Detect if docker.sh already provisioned datasource (idempotent)
    if [[ -f "${DS_DIR}/loki-docker.yaml" ]]; then
        ok "✓ Loki datasource already provisioned by docker.sh — skipping."
        info "  Datasource: ${DS_DIR}/loki-docker.yaml"
        section_end; return
    fi

    # ── CREATE NEW DATASOURCE (first run) ────────────────────────────────────
    cat > "${DS_DIR}/loki-docker.yaml" <<EOF
# Provisioned by docker.sh v${SCRIPT_VERSION}
# NOTE: Uses same Loki endpoint as init.sh — no conflicts
apiVersion: 1

datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://127.0.0.1:${LOKI_PORT}
    uid: Loki
    isDefault: false
    jsonData:
      maxLines: 5000
      timeout:  60
      derivedFields:
        - datasourceUid: Loki
          matcherRegex: "container_id=([\\w]+)"
          name: ContainerID
          url: '\$\${__value.raw}'
    version: 1
    editable: true
EOF
    chown grafana:grafana "${DS_DIR}/loki-docker.yaml" 2>/dev/null || true
    ok "✓ Loki datasource created: ${DS_DIR}/loki-docker.yaml"
    info "  Endpoint: http://127.0.0.1:${LOKI_PORT}  |  UID: Loki"

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  13 — GRAFANA DASHBOARDS — download + provision Docker dashboards
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

provision_dashboards() {
    $SETUP_MON || return

    section "13" "Grafana — Docker Dashboard Provisioning"

    local DASH_DIR="${GRAFANA_DASH_DIR}/docker"
    local PROV_DIR="${GRAFANA_PROVISIONING}/dashboards"
    mkdir -p "${DASH_DIR}" "${PROV_DIR}"

    # ── CONFLICT RESOLUTION ──────────────────────────────────────────────────
    # Verify that init.sh created its dashboard providers first
    local init_providers=0
    [[ -f "${PROV_DIR}/system.yaml" ]] && ((init_providers++))
    [[ -f "${PROV_DIR}/applications.yaml" ]] && ((init_providers++))
    [[ -f "${PROV_DIR}/logs.yaml" ]] && ((init_providers++))
    
    if (( init_providers == 0 )); then
        warn "No dashboard providers found from init.sh (system.yaml, applications.yaml, logs.yaml)"
        warn "docker.sh assumes init.sh has been run first"
        warn "This is not necessarily an error, but verify init.sh provisioning manually"
    else
        ok "✓ Found ${init_providers} dashboard provider(s) from init.sh — will not override"
    fi

    # Detect if docker.sh already provisioned its dashboard provider (idempotent)
    if [[ -f "${PROV_DIR}/docker-dashboards.yaml" ]]; then
        ok "✓ Docker dashboard provider already configured — skipping."
        info "  Provider: ${PROV_DIR}/docker-dashboards.yaml"
        # Still recreate dashboards in case they were deleted
    else
        ok "✓ Creating new Docker dashboard provider"
    fi

    # ── Provision dashboard provider (appends to existing other folders) ───────
    cat > "${PROV_DIR}/docker-dashboards.yaml" <<EOF
# Provisioned by docker.sh v${SCRIPT_VERSION}
# Coexists with init.sh providers: system.yaml, applications.yaml, logs.yaml
apiVersion: 1

providers:
  - name: Docker Monitoring
    orgId: 1
    folder: Docker
    folderUid: docker-monitoring
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: ${DASH_DIR}
EOF
    chown grafana:grafana "${PROV_DIR}/docker-dashboards.yaml" 2>/dev/null || true
    ok "✓ Docker dashboard provider: ${PROV_DIR}/docker-dashboards.yaml"

    # ── 1. Template: Container Metrics & Status ──────────────────────────────
    cat > "${DASH_DIR}/01-template-container-metrics.json" <<'TEMPLATE_METRICS'
{
  "dashboard": {
    "title": "📊 Template — Container Metrics & Status",
    "description": "Use as template: duplicate & set container_name for per-container monitoring",
    "timezone": "browser",
    "templating": {
      "list": [
        {
          "name": "container_name",
          "type": "textbox",
          "label": "Container Name",
          "description": "Set to your Docker container name (e.g., db, cache, web)"
        }
      ]
    },
    "panels": [
      {
        "title": "Container Status",
        "description": "Is this container running?",
        "targets": [{"expr": "container_last_seen{name=~\\\".*\\$\\${container_name}.*\\\"}"}],
        "type": "stat",
        "gridPos": {"x": 0, "y": 0, "w": 6, "h": 3}
      },
      {
        "title": "CPU Usage (%)",
        "targets": [{"expr": "rate(container_cpu_usage_seconds_total{name=~\\\".*\\$\\${container_name}.*\\\"}[1m]) * 100"}],
        "type": "timeseries",
        "gridPos": {"x": 6, "y": 0, "w": 6, "h": 3}
      },
      {
        "title": "Memory Usage (MB)",
        "targets": [{"expr": "container_memory_usage_bytes{name=~\\\".*\\$\\${container_name}.*\\\"} / 1024 / 1024"}],
        "type": "timeseries",
        "gridPos": {"x": 12, "y": 0, "w": 6, "h": 3}
      },
      {
        "title": "Memory Limit (MB)",
        "targets": [{"expr": "container_spec_memory_limit_bytes{name=~\\\".*\\$\\${container_name}.*\\\"} / 1024 / 1024"}],
        "type": "stat",
        "gridPos": {"x": 18, "y": 0, "w": 6, "h": 3}
      },
      {
        "title": "Memory % of Limit",
        "description": "Memory utilization percentage",
        "targets": [{"expr": "(container_memory_usage_bytes{name=~\\\".*\\$\\${container_name}.*\\\"} / container_spec_memory_limit_bytes{name=~\\\".*\\$\\${container_name}.*\\\"}) * 100"}],
        "type": "gauge",
        "gridPos": {"x": 0, "y": 3, "w": 6, "h": 3},
        "fieldConfig": {"defaults": {"unit": "percent", "max": 100, "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "yellow", "value": 70}, {"color": "red", "value": 90}]}}}
      },
      {
        "title": "CPU Quota",
        "targets": [{"expr": "container_spec_cpu_quota{name=~\\\".*\\$\\${container_name}.*\\\"} / 100000"}],
        "type": "stat",
        "gridPos": {"x": 6, "y": 3, "w": 6, "h": 3}
      },
      {
        "title": "Restart Count",
        "description": "Times this container has restarted",
        "targets": [{"expr": "container_oom_events_total{name=~\\\".*\\$\\${container_name}.*\\\"}"}],
        "type": "stat",
        "gridPos": {"x": 12, "y": 3, "w": 6, "h": 3}
      },
      {
        "title": "Uptime",
        "description": "How long container has been running",
        "targets": [{"expr": "time() - container_start_time_seconds{name=~\\\".*\\$\\${container_name}.*\\\"}"}],
        "type": "stat",
        "gridPos": {"x": 18, "y": 3, "w": 6, "h": 3},
        "fieldConfig": {"defaults": {"unit": "s"}}
      },
      {
        "title": "CPU Usage Trend",
        "targets": [{"expr": "rate(container_cpu_usage_seconds_total{name=~\\\".*\\$\\${container_name}.*\\\"}[5m]) * 100"}],
        "type": "timeseries",
        "gridPos": {"x": 0, "y": 6, "w": 12, "h": 8}
      },
      {
        "title": "Memory Usage Trend",
        "targets": [{"expr": "container_memory_usage_bytes{name=~\\\".*\\$\\${container_name}.*\\\"} / 1024 / 1024"}],
        "type": "timeseries",
        "gridPos": {"x": 12, "y": 6, "w": 12, "h": 8}
      }
    ],
    "refresh": "30s",
    "time": {"from": "now-6h", "to": "now"},
    "schemaVersion": 38,
    "style": "dark",
    "version": 1
  }
}
TEMPLATE_METRICS

    # ── 2. Template: Container Logs ──────────────────────────────────────────
    cat > "${DASH_DIR}/02-template-container-logs.json" <<'TEMPLATE_LOGS'
{
  "dashboard": {
    "title": "📋 Template — Container Logs",
    "description": "Use as template: duplicate & set container_name for per-container logs",
    "timezone": "browser",
    "templating": {
      "list": [
        {
          "name": "container_name",
          "type": "textbox",
          "label": "Container Name",
          "description": "Set to your Docker container name"
        }
      ]
    },
    "panels": [
      {
        "title": "Total Logs (24h)",
        "targets": [{"expr": "count by (container_name) ({container_name=\\\"\\$\\${container_name}\\\"})"}],
        "type": "stat",
        "gridPos": {"x": 0, "y": 0, "w": 6, "h": 3}
      },
      {
        "title": "Error Logs (24h)",
        "targets": [{"expr": "count by (container_name) ({container_name=\\\"\\$\\${container_name}\\\" | \\\"error\\\"|\\\"ERROR\\\"|\\\"Exception\\\"})"}],
        "type": "stat",
        "gridPos": {"x": 6, "y": 0, "w": 6, "h": 3},
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "red", "value": 1}]}}}
      },
      {
        "title": "Warning Logs (24h)",
        "targets": [{"expr": "count by (container_name) ({container_name=\\\"\\$\\${container_name}\\\" | \\\"WARN\\\"|\\\"warn\\\"})"}],
        "type": "stat",
        "gridPos": {"x": 12, "y": 0, "w": 6, "h": 3}
      },
      {
        "title": "Last Log Entry",
        "description": "Timestamp of last log",
        "targets": [{"expr": "max by (container_name) ({container_name=\\\"\\$\\${container_name}\\\"})"}],
        "type": "stat",
        "gridPos": {"x": 18, "y": 0, "w": 6, "h": 3}
      },
      {
        "title": "Log Volume Trend",
        "description": "Logs over time for this container",
        "targets": [{"expr": "count by (container_name) ({container_name=\\\"\\$\\${container_name}\\\"})"}],
        "type": "timeseries",
        "gridPos": {"x": 0, "y": 3, "w": 12, "h": 8}
      },
      {
        "title": "Error Rate",
        "targets": [{"expr": "count by (container_name) ({container_name=\\\"\\$\\${container_name}\\\" | \\\"error\\\"|\\\"ERROR\\\"})"}],
        "type": "timeseries",
        "gridPos": {"x": 12, "y": 3, "w": 12, "h": 8}
      },
      {
        "title": "Recent Logs",
        "description": "Latest 100 log lines from this container",
        "targets": [{"expr": "{container_name=\\\"\\$\\${container_name}\\\"}"}],
        "type": "logs",
        "gridPos": {"x": 0, "y": 11, "w": 24, "h": 15}
      }
    ],
    "refresh": "10s",
    "time": {"from": "now-1h", "to": "now"},
    "schemaVersion": 38,
    "style": "dark",
    "version": 1
  }
}
TEMPLATE_LOGS

    # ── 3. Template: Container Network & Disk I/O ────────────────────────────
    cat > "${DASH_DIR}/03-template-container-io.json" <<'TEMPLATE_IO'
{
  "dashboard": {
    "title": "🔄 Template — Container Network & Disk I/O",
    "description": "Use as template: duplicate & set container_name for network/disk monitoring",
    "timezone": "browser",
    "templating": {
      "list": [
        {
          "name": "container_name",
          "type": "textbox",
          "label": "Container Name",
          "description": "Set to your Docker container name"
        }
      ]
    },
    "panels": [
      {
        "title": "Network Received (MB/s)",
        "targets": [{"expr": "rate(container_network_receive_bytes_total{name=~\\\".*\\$\\${container_name}.*\\\"}[1m]) / 1024 / 1024"}],
        "type": "timeseries",
        "gridPos": {"x": 0, "y": 0, "w": 12, "h": 8}
      },
      {
        "title": "Network Transmitted (MB/s)",
        "targets": [{"expr": "rate(container_network_transmit_bytes_total{name=~\\\".*\\$\\${container_name}.*\\\"}[1m]) / 1024 / 1024"}],
        "type": "timeseries",
        "gridPos": {"x": 12, "y": 0, "w": 12, "h": 8}
      },
      {
        "title": "Disk Reads (MB/s)",
        "targets": [{"expr": "rate(container_fs_reads_bytes_total{name=~\\\".*\\$\\${container_name}.*\\\"}[1m]) / 1024 / 1024"}],
        "type": "timeseries",
        "gridPos": {"x": 0, "y": 8, "w": 12, "h": 8}
      },
      {
        "title": "Disk Writes (MB/s)",
        "targets": [{"expr": "rate(container_fs_writes_bytes_total{name=~\\\".*\\$\\${container_name}.*\\\"}[1m]) / 1024 / 1024"}],
        "type": "timeseries",
        "gridPos": {"x": 12, "y": 8, "w": 12, "h": 8}
      },
      {
        "title": "Network Packets In/Out",
        "targets": [{"expr": "rate(container_network_receive_packets_total{name=~\\\".*\\$\\${container_name}.*\\\"}[1m])"}],
        "type": "timeseries",
        "gridPos": {"x": 0, "y": 16, "w": 12, "h": 8}
      },
      {
        "title": "Network Errors",
        "targets": [{"expr": "rate(container_network_receive_errors_total{name=~\\\".*\\$\\${container_name}.*\\\"}[1m])"}],
        "type": "stat",
        "gridPos": {"x": 12, "y": 16, "w": 12, "h": 8},
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "red", "value": 1}]}}}
      }
    ],
    "refresh": "30s",
    "time": {"from": "now-6h", "to": "now"},
    "schemaVersion": 38,
    "style": "dark",
    "version": 1
  }
}
TEMPLATE_IO

    # ── Docker Per-Container Log Analytics Dashboard ──────────────────────────
    # Similar to PM2 analytics but for Docker containers — shows success/error/warning rates
    cat > "${DASH_DIR}/04-docker-per-container-analytics.json" <<'DOCKER_ANALYTICS'
{
  "annotations": { "list": [] },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 1,
  "id": null,
  "links": [],
  "panels": [
    {
      "datasource": { "type": "loki", "uid": "Loki" },
      "fieldConfig": {
        "defaults": { "color": { "mode": "thresholds" }, "mappings": [],
          "thresholds": { "mode": "absolute", "steps": [
            { "color": "green", "value": null },
            { "color": "green", "value": 90 }
          ] },
          "unit": "percent" },
        "overrides": []
      },
      "gridPos": { "h": 4, "w": 6, "x": 0, "y": 0 },
      "id": 1,
      "options": { "colorMode": "background", "graphMode": "area", "justifyMode": "center",
                   "orientation": "auto", "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false },
                   "textMode": "auto", "showPercentage": true },
      "pluginVersion": "10.0.0",
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "100 * (sum(count_over_time({job=\"docker_containers\"}[5m])) - sum(count_over_time({job=\"docker_containers\"} |~ \"ERROR|Exception|WARN|WARNING\"[5m]))) / (sum(count_over_time({job=\"docker_containers\"}[5m])) + 1)",
          "legendFormat": "Success Rate",
          "refId": "A" }
      ],
      "title": "✅ Success Rate",
      "type": "gauge"
    },
    {
      "datasource": { "type": "loki", "uid": "Loki" },
      "fieldConfig": {
        "defaults": { "color": { "mode": "thresholds" }, "mappings": [],
          "thresholds": { "mode": "absolute", "steps": [
            { "color": "red", "value": null },
            { "color": "red", "value": 10 }
          ] },
          "unit": "percent" },
        "overrides": []
      },
      "gridPos": { "h": 4, "w": 6, "x": 6, "y": 0 },
      "id": 2,
      "options": { "colorMode": "background", "graphMode": "area", "justifyMode": "center",
                   "orientation": "auto", "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false },
                   "textMode": "auto", "showPercentage": true },
      "pluginVersion": "10.0.0",
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "100 * sum(count_over_time({job=\"docker_containers\"} |~ \"ERROR|Exception\" [5m])) / (sum(count_over_time({job=\"docker_containers\"}[5m])) + 1)",
          "legendFormat": "Error Rate",
          "refId": "A" }
      ],
      "title": "❌ Error Rate",
      "type": "gauge"
    },
    {
      "datasource": { "type": "loki", "uid": "Loki" },
      "fieldConfig": {
        "defaults": { "color": { "mode": "thresholds" }, "mappings": [],
          "thresholds": { "mode": "absolute", "steps": [
            { "color": "yellow", "value": null },
            { "color": "yellow", "value": 5 }
          ] },
          "unit": "percent" },
        "overrides": []
      },
      "gridPos": { "h": 4, "w": 6, "x": 12, "y": 0 },
      "id": 3,
      "options": { "colorMode": "background", "graphMode": "area", "justifyMode": "center",
                   "orientation": "auto", "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false },
                   "textMode": "auto", "showPercentage": true },
      "pluginVersion": "10.0.0",
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "100 * sum(count_over_time({job=\"docker_containers\"} |~ \"WARN|WARNING\" [5m])) / (sum(count_over_time({job=\"docker_containers\"}[5m])) + 1)",
          "legendFormat": "Warning Rate",
          "refId": "A" }
      ],
      "title": "⚠️ Warning Rate",
      "type": "gauge"
    },
    {
      "datasource": { "type": "loki", "uid": "Loki" },
      "fieldConfig": {
        "defaults": { "color": { "mode": "palette-classic" }, "unit": "short",
          "custom": { "hideFrom": { "legend": false, "tooltip": false, "viz": false } } },
        "overrides": []
      },
      "gridPos": { "h": 4, "w": 6, "x": 18, "y": 0 },
      "id": 4,
      "options": { "legend": { "calcs": [], "displayMode": "list", "placement": "bottom" },
                   "pieType": "donut", "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false },
                   "tooltip": { "mode": "single" } },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "sum(count_over_time({job=\"docker_containers\"}[1m]))",
          "legendFormat": "Log Count",
          "refId": "A" }
      ],
      "title": "📊 Log Distribution",
      "type": "piechart"
    },
    {
      "datasource": { "type": "loki", "uid": "Loki" },
      "fieldConfig": {
        "defaults": { "color": { "mode": "palette-classic" }, "unit": "short",
          "custom": { "lineWidth": 2, "fillOpacity": 10 } },
        "overrides": []
      },
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 4 },
      "id": 5,
      "options": { "legend": { "calcs": ["sum"], "displayMode": "table", "placement": "bottom" },
                   "tooltip": { "mode": "multi" } },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "sum(count_over_time({job=\"docker_containers\"} |~ \"ERROR|Exception\" [5m])) by (container_name)",
          "legendFormat": "{{container_name}}",
          "refId": "A" }
      ],
      "title": "Errors per Container",
      "type": "timeseries"
    },
    {
      "datasource": { "type": "loki", "uid": "Loki" },
      "fieldConfig": {
        "defaults": { "color": { "mode": "palette-classic" }, "unit": "short",
          "custom": { "lineWidth": 2, "fillOpacity": 10 } },
        "overrides": []
      },
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 4 },
      "id": 6,
      "options": { "legend": { "calcs": ["sum"], "displayMode": "table", "placement": "bottom" },
                   "tooltip": { "mode": "multi" } },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "sum(count_over_time({job=\"docker_containers\"} |~ \"WARN|WARNING\" [5m])) by (container_name)",
          "legendFormat": "{{container_name}}",
          "refId": "A" }
      ],
      "title": "Warnings per Container",
      "type": "timeseries"
    },
    {
      "datasource": { "type": "loki", "uid": "Loki" },
      "fieldConfig": {
        "defaults": { "custom": { "showThresholdLabels": false, "showThresholdMarkers": true } },
        "overrides": []
      },
      "gridPos": { "h": 10, "w": 24, "x": 0, "y": 12 },
      "id": 7,
      "options": { "dedupStrategy": "none", "enableLogDetails": true, "prettifyLogMessage": false,
                   "showCommonLabels": false, "showLabels": true, "showTime": true,
                   "sortOrder": "Descending", "wrapLogMessage": true },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "{job=\"docker_containers\"}",
          "legendFormat": "",
          "refId": "A" }
      ],
      "title": "📋 Detailed Docker Container Logs",
      "type": "logs"
    }
  ],
  "refresh": "5s",
  "schemaVersion": 38,
  "tags": ["docker", "containers", "analytics", "loki"],
  "time": { "from": "now-6h", "to": "now" },
  "timepicker": {},
  "timezone": "browser",
  "title": "🐳 Docker Per-Container Log Analytics",
  "description": "Detailed log-based analytics: success/error/warning rates, per-container metrics, full log viewer",
  "uid": "docker-per-container-analytics",
  "version": 1,
  "style": "dark"
}
DOCKER_ANALYTICS

    chown -R grafana:grafana "${DASH_DIR}" 2>/dev/null || true
    chmod 644 "${DASH_DIR}"/*.json 2>/dev/null || true
    
    ok "✓ Dashboard template: Container Metrics & Status"
    ok "✓ Dashboard template: Container Logs"
    ok "✓ Dashboard template: Container Network & Disk I/O"
    ok "✓ Dashboard: 🐳 Docker Per-Container Log Analytics (live data)"
    ok "Saved to: ${DASH_DIR}"
    ok ""
    ok "📌 HOW TO CREATE PER-CONTAINER DASHBOARDS:"
    ok "   1. Duplicate any template dashboard (e.g., 01-template-container-metrics.json)"
    ok "   2. Open the duplicate in Grafana"
    ok "   3. Edit template variable 'container_name' and set to your container name"
    ok "   4. Save with your container name as dashboard title"
    ok "   5. Queries auto-filter to show only that container's data"

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  14 — RELOAD GRAFANA
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

reload_grafana() {
    $SETUP_MON || return

    section "14" "Grafana — Reload Provisioning"

    if systemctl is-active --quiet grafana-server 2>/dev/null; then
        systemctl restart grafana-server
        sleep 3
        if systemctl is-active --quiet grafana-server; then
            ok "Grafana restarted — new datasource + dashboards loaded."
        else
            warn "Grafana failed to restart: journalctl -xu grafana-server"
        fi
    else
        warn "Grafana service not active. Start it: sudo systemctl start grafana-server"
    fi

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  15 — SMOKE TEST + VERIFICATION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

verify_all() {
    section "15" "Smoke Test + Verification"

    # Docker hello-world
    info "Running Docker smoke test (hello-world container)..."
    if docker run --rm hello-world 2>&1 | grep -q "Hello from Docker"; then
        ok "Docker smoke test PASSED — containers run successfully."
    else
        warn "Smoke test result unclear. Check: docker run --rm hello-world"
    fi

    echo ""

    # Helper: check endpoint and print result
    _chk_ep() {
        local label="$1" url="$2" pattern="${3:-.}"
        if curl -sf "${url}" 2>/dev/null | grep -q "${pattern}"; then
            echo -e "  ${TICK}  ${WHT}${BOLD}${label}${R}  ${GRY}→  ${url}${R}"
        else
            echo -e "  ${WARN_IC}  ${YLW}${label}${R}  ${GRY}→  ${url}  (not ready yet)${R}"
        fi
    }
    # Helper: check container state
    _chk_ct() {
        local name="$1"
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
            local status
            status=$(docker ps --format '{{.Status}}' --filter "name=^${name}$" 2>/dev/null)
            echo -e "  ${TICK}  ${WHT}${BOLD}${name}${R}  container  ${GRY}${status}${R}"
        else
            echo -e "  ${WARN_IC}  ${YLW}${name}${R}  container  ${GRY}NOT RUNNING${R}"
        fi
    }
    # Helper: check systemd service
    _chk_svc() {
        local name="$1" label="$2"
        if systemctl is-active --quiet "${name}" 2>/dev/null; then
            echo -e "  ${TICK}  ${WHT}${BOLD}${label}${R}  systemd service  ${GRN}active${R}"
        else
            echo -e "  ${WARN_IC}  ${YLW}${label}${R}  systemd service  ${GRY}inactive${R}"
        fi
    }

    echo -e "  ${BLU}${BOLD}Docker Engine${R}"
    _chk_ep  "Docker Metrics"       "http://127.0.0.1:${DOCKER_METRICS_PORT}/metrics" "engine_daemon"
    _chk_svc "docker"               "Docker daemon"

    echo ""
    echo -e "  ${BLU}${BOLD}Monitoring Containers${R}"
    _chk_ct  "cadvisor"
    _chk_ep  "cAdvisor Metrics"     "http://127.0.0.1:${CADVISOR_PORT}/metrics"       "container_cpu"
    if $SETUP_LOKI; then
        if $NATIVE_LOKI; then
            _chk_svc "loki"          "Loki (native systemd)"
            _chk_ep  "Loki Ready"    "http://127.0.0.1:${LOKI_PORT}/ready"                        "ready"
            _chk_ct  "promtail-docker"
            _chk_ep  "Promtail-docker Status"  "http://127.0.0.1:${PROMTAIL_DOCKER_STATUS_PORT}/ready"  "."
        else
            _chk_ct  "loki"
            _chk_ep  "Loki Ready"       "http://127.0.0.1:${LOKI_PORT}/ready"             "ready"
            _chk_ct  "promtail"
            _chk_ep  "Promtail Status"  "http://127.0.0.1:${PROMTAIL_STATUS_PORT}/ready"  "."
        fi
    fi

    echo ""
    echo -e "  ${BLU}${BOLD}init.sh Components (unchanged)${R}"
    _chk_svc "node_exporter"  "node_exporter"
    _chk_svc "prometheus"     "Prometheus"
    _chk_ep  "Prometheus"     "${PROMETHEUS_URL}/-/healthy"  "Prometheus"
    _chk_svc "grafana-server" "Grafana"
    _chk_ep  "Grafana"        "${GRAFANA_URL}/api/health"    "ok"

    echo ""
    echo -e "  ${BLU}${BOLD}Ecosystem Tools${R}"
    command -v ctop        &>/dev/null && echo -e "  ${TICK}  ctop"        || echo -e "  ${WARN_IC}  ctop — not found"
    command -v lazydocker  &>/dev/null && echo -e "  ${TICK}  lazydocker"  || echo -e "  ${WARN_IC}  lazydocker — not found"
    command -v docker-scout &>/dev/null || docker scout version &>/dev/null 2>&1 \
        && echo -e "  ${TICK}  docker scout" || echo -e "  ${WARN_IC}  docker scout — not found"

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  16 — SUMMARY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

print_summary() {
    echo ""
    echo -e "${BLU}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${BLU}${BOLD}║${R}${GRN}${BOLD}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  ✔  docker.sh Complete — Docker CE + Full Monitoring Integration"
    echo -e "${BLU}${BOLD}  ╠${HR2}╣${R}"

    _row() { printf "  ${BLU}${BOLD}║${R}  ${GRY}%-22s${R}  ${WHT}${BOLD}%-50s${R}  ${BLU}${BOLD}║${R}\n" "$1" "$2"; }
    _sep() { echo -e "  ${BLU}${BOLD}╠${HR2}╣${R}"; }
    _hdr() { printf "  ${BLU}${BOLD}║${R}  ${CYN}${BOLD}%-74s${R}  ${BLU}${BOLD}║${R}\n" "$1"; }

    _hdr "Docker Stack"
    _sep
    _row "Docker Engine"    "$(docker --version 2>/dev/null || echo 'installed')"
    _row "Docker Compose"   "$(docker compose version 2>/dev/null || echo 'installed')"
    _row "Buildx"           "$(docker buildx version 2>/dev/null | head -1 || echo 'installed')"
    _row "Deploy User"      "${DEPLOY_USER}  (member of docker group)"
    _row "Daemon Config"    "/etc/docker/daemon.json  (BuildKit + log rotation)"
    _row "Metrics Endpoint" "http://127.0.0.1:${DOCKER_METRICS_PORT}/metrics"

    _sep
    _hdr "Monitoring — Integrated with init.sh Prometheus + Grafana"
    _sep
    _row "cAdvisor"         "Container CPU/RAM/net/disk → :${CADVISOR_PORT}"
    _row "Loki"             "Docker log storage → :${LOKI_PORT}  (31-day retention)"
    _row "Promtail"         "Reads all container logs → ships to Loki"
    _row "Prometheus"       "Scraping docker_engine + cadvisor  (node_exporter unchanged)"
    _row "Grafana"          "SSH tunnel → http://localhost:3001  (Docker folder added)"
    _row "Dashboards"       "5 Docker dashboards in Grafana → Docker folder"

    _sep
    _hdr "🔭  Access Grafana Dashboards (SSH Tunnel — same as init.sh)"
    _sep
    printf "  ${BLU}${BOLD}║${R}  ${GRN}${BOLD}%-74s${R}  ${BLU}${BOLD}║${R}\n" \
        "ssh -L 3001:localhost:3001 ${DEPLOY_USER}@<server-ip>"
    printf "  ${BLU}${BOLD}║${R}  ${WHT}%-74s${R}  ${BLU}${BOLD}║${R}\n" \
        "Then open: http://localhost:3001  →  Dashboards  →  Docker"

    _sep
    _hdr "🐳  Docker Quick Reference"
    _sep
    local cmds=(
        "docker ps                        list running containers"
        "docker compose up -d             start services from compose file"
        "docker stats                     live CPU/RAM per container"
        "docker logs -f <name>            follow container logs"
        "docker exec -it <name> bash      shell into container"
        "docker buildx build -t app .     build with BuildKit"
        "docker scout quickview <image>   vulnerability scan"
        "ctop                             live container resource monitor"
        "lazydocker                       interactive Docker TUI"
        "docker system prune -af          free all unused disk"
    )
    for c in "${cmds[@]}"; do
        printf "  ${BLU}${BOLD}║${R}  ${CYN}›${R}  ${WHT}%-70s${R}  ${BLU}${BOLD}║${R}\n" "$c"
    done

    _sep
    _hdr "📋  LogQL Queries — Grafana Explore → Loki"
    _sep
    local logql=(
        "{job=\"docker\"}                       all container logs"
        "{container_name=\"myapp\"}             single container"
        "{job=\"docker\"} |= \"error\"           filter errors"
        "{compose_project=\"myapp\"}            all services in a compose project"
        "{job=\"docker\", stream=\"stderr\"}     stderr only"
    )
    for q in "${logql[@]}"; do
        printf "  ${BLU}${BOLD}║${R}  ${GRN}·${R}  ${WHT}%-70s${R}  ${BLU}${BOLD}║${R}\n" "$q"
    done

    _sep
    printf  "  ${BLU}${BOLD}║${R}${GRY}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  Log: ${LOG_FILE}"
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

    _log INFO "=== docker.sh v${SCRIPT_VERSION} started. User=${DEPLOY_USER} ==="

    preflight                   # 01 — checks, OS detect, verify init.sh components
    remove_old_docker           # 02 — purge legacy docker packages
    install_prerequisites       # 03 — curl, gnupg, jq, lsb-release, etc.
    add_docker_repo             # 04 — official Docker APT repo + GPG key
    install_docker_ce           # 05 — docker-ce, cli, containerd, buildx, compose-plugin
    configure_daemon            # 06 — daemon.json: BuildKit + log rotation + metrics
    add_user_to_docker_group    # 07 — usermod -aG docker $DEPLOY_USER
    install_ecosystem_tools     # 08 — ctop, lazydocker, docker scout, bash-completion
    deploy_cadvisor             # 09 — cAdvisor container (127.0.0.1:8080)
    deploy_loki_promtail        # 10 — Loki + Promtail containers for log pipeline
    patch_prometheus            # 11 — append docker_engine + cadvisor to prometheus.yml
    provision_loki_datasource   # 12 — write Loki datasource to Grafana provisioning
    provision_dashboards        # 13 — download + provision 5 Docker dashboards
    reload_grafana              # 14 — restart grafana-server to apply provisioning
    verify_all                  # 15 — smoke test + endpoint checks
    print_summary               # 16 — full summary + quick reference

    _log INFO "=== docker.sh complete. User=${DEPLOY_USER} ==="
}

main "$@"
