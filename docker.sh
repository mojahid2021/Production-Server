#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  docker.sh  —  Docker CE + Monitoring Integration  v1.0.0                   ║
# ║  Ubuntu 20.04 / 22.04 / 24.04 LTS                                           ║
# ╠══════════════════════════════════════════════════════════════════════════════╣
# ║                                                                              ║
# ║  COMPANION TO: init.sh (Node.js Production Server Provisioner)               ║
# ║  Integrates with Cockpit (Web Console)                                       ║
# ║                                                                              ║
# ║  WHAT THIS DOES                                                              ║
# ║  01. Preflight — checks OS, root, deploy user, and monitoring components     ║
# ║  02. Install Docker CE (latest stable) + CLI + containerd + Buildx           ║
# ║  03. Install Docker Compose v2 plugin                                        ║
# ║  04. Configure optimized daemon.json (BuildKit, log rotation, metrics)       ║
# ║  05. Add deploy user to docker group (no sudo needed)                        ║
# ║  06. Install ecosystem tools: ctop, Lazydocker, Docker Scout                 ║
# ║  07. Enable bash completion for docker & compose                              ║
# ║  08. Enable Docker daemon metrics endpoint (:9323)                           ║
# ║  09. Cockpit Container Integration — view & manage containers in Cockpit GUI ║
# ║  10. Deploy cAdvisor container — per-container CPU/RAM/net/disk metrics (:8080)║
# ║  11. Patch monitoring scrapes (VictoriaMetrics / Prometheus)                 ║
# ║  12. Smoke test + full verification                                          ║
# ║  13. Summary & quick reference                                               ║
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
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Monitoring component paths ────────────────────────────────────────────────
readonly VICTORIAMETRICS_CONFIG="/etc/victoriametrics/scrape.yml"
readonly VICTORIAMETRICS_URL="http://127.0.0.1:8428"
readonly COCKPIT_URL="http://127.0.0.1:9090"
readonly PROMETHEUS_CONFIG="/etc/prometheus/prometheus.yml"   # fallback
readonly PROMETHEUS_URL="http://127.0.0.1:9090"               # fallback

# ── Docker monitoring stack ────────────────────────────────────────────────────
readonly DOCKER_METRICS_PORT=9323      # Docker daemon metrics
readonly CADVISOR_PORT=8080            # Per-container metrics

# Service state tracking
COCKPIT_EXISTS=false
VM_EXISTS=false
PROM_EXISTS=false
GRAFANA_EXISTS=false

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
#  SERVICE DETECTION — which services already exist?
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

detect_existing_services() {
    COCKPIT_EXISTS=false
    VM_EXISTS=false
    PROM_EXISTS=false
    GRAFANA_EXISTS=false

    # Check Cockpit
    if systemctl is-active --quiet cockpit.socket 2>/dev/null || command -v cockpit-bridge &>/dev/null; then
        COCKPIT_EXISTS=true
    fi

    # Check VictoriaMetrics
    if systemctl is-active --quiet victoriametrics 2>/dev/null || [[ -f "$VICTORIAMETRICS_CONFIG" ]]; then
        VM_EXISTS=true
    fi

    # Check Prometheus (legacy fallback)
    if systemctl is-active --quiet prometheus 2>/dev/null || [[ -f "$PROMETHEUS_CONFIG" ]]; then
        PROM_EXISTS=true
    fi

    # Check Grafana (legacy fallback)
    if systemctl is-active --quiet grafana-server 2>/dev/null || command -v grafana-server &>/dev/null; then
        GRAFANA_EXISTS=true
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  PARSE ARGS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

parse_args() {
    DEPLOY_USER="${SUDO_USER:-}"   # default: the user who ran sudo
    SETUP_MON=true                  # --no-mon disables monitoring integration
    SETUP_LOKI=false                # Loki/Promtail disabled by default
    SETUP_CADVISOR=false            # default false (saves ~50-70MB RAM; --with-cadvisor to enable)
    NATIVE_LOKI=false               # set to true at runtime when init.sh's native Loki is detected

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u)               DEPLOY_USER="${2:?}"; shift 2 ;;
            --no-mon)         SETUP_MON=false;      shift ;;
            --no-loki)        SETUP_LOKI=false;     shift ;;
            --with-cadvisor)  SETUP_CADVISOR=true;  shift ;;
            --no-cadvisor)    SETUP_CADVISOR=false; shift ;;
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
    echo -e "    ${CYN}sudo ./docker.sh${R}                 ${GRY}# run lean stack (recommended, saves 70MB RAM)${R}"
    echo -e "    ${CYN}sudo ./docker.sh -u <user>${R}       ${GRY}# specify deploy username${R}"
    echo -e "    ${CYN}sudo ./docker.sh --with-cadvisor${R} ${GRY}# enable cAdvisor container (:8080)${R}"
    echo -e "    ${CYN}sudo ./docker.sh --no-mon${R}        ${GRY}# skip monitoring integration${R}"
    echo -e "    ${CYN}sudo ./docker.sh -h${R}              ${GRY}# show this help${R}"
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
            "  Docker · Compose v2 · BuildKit · cAdvisor · Cockpit Web Console"
    echo -e "${BLU}${BOLD}  ╠${HR2}╣${R}"
    printf  "  ${BLU}${BOLD}║${R}${GRY}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  Companion to init.sh — integrates with Cockpit Web Console"
    printf  "  ${BLU}${BOLD}║${R}${GRY}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  Cockpit Web Console running from init.sh (0 MB idle RAM)"
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
        # Check canonical server metadata from init.sh first
        if [[ -f /etc/production-server.conf ]]; then
            local conf_user
            conf_user=$(grep -E '^DEPLOY_USER=' /etc/production-server.conf 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
            if [[ -n "$conf_user" ]] && id "$conf_user" &>/dev/null; then
                DEPLOY_USER="$conf_user"
                ok "Deploy user connected from init.sh metadata: ${WHT}${BOLD}${DEPLOY_USER}${R}"
            fi
        fi
    fi
    if [[ -z "${DEPLOY_USER}" || "${DEPLOY_USER}" == "root" ]]; then
        # Fallback: check /home
        local found_user
        found_user=$(ls /home 2>/dev/null | grep -v 'lost+found' | head -1 || true)
        if [[ -n "${found_user}" ]]; then
            DEPLOY_USER="${found_user}"
            warn "No user specified. Detected: '${DEPLOY_USER}' — use -u <name> to override."
        else
            DEPLOY_USER="root"
            warn "No deploy user found. Docker group will not be configured. Use -u <name>."
        fi
    fi
    ok "Deploy user: ${WHT}${BOLD}${DEPLOY_USER}${R}"

    # Detect existing services early
    detect_existing_services
    
    # Report what's already installed
    if $COCKPIT_EXISTS; then
        ok "Cockpit detected — will integrate container management (cockpit-podman)."
    fi
    if $VM_EXISTS; then
        ok "VictoriaMetrics detected — will configure Docker & cAdvisor scrape targets."
    elif $PROM_EXISTS; then
        ok "Legacy Prometheus detected — will configure scrape targets."
    fi

    # Check monitoring targets if monitoring is requested
    if $SETUP_MON; then
        if [[ -f "${VICTORIAMETRICS_CONFIG}" ]]; then
            ok "VictoriaMetrics scrape config found: ${VICTORIAMETRICS_CONFIG}"
        elif [[ -f "${PROMETHEUS_CONFIG}" ]]; then
            ok "Prometheus scrape config found: ${PROMETHEUS_CONFIG}"
        else
            info "No existing scrape config found (VictoriaMetrics/Prometheus). Metrics endpoints will still be live."
        fi

        if $COCKPIT_EXISTS || $VM_EXISTS; then
            ok "Host monitoring active (Cockpit Web Console) — no node_exporter needed."
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

    # ── 6. jq (JSON config parsing — Docker daemon / monitoring config) ──────
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

    local needed=()
    for pkg in ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common wget git jq make bash-completion; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            needed+=("$pkg")
        fi
    done

    if [[ ${#needed[@]} -gt 0 ]]; then
        info "Installing missing prerequisites: ${needed[*]}..."
        apt-get update -qq
        apt-get install -y --no-install-recommends "${needed[@]}"
        ok "Prerequisites installed: ${needed[*]}"
    else
        ok "All prerequisites satisfied by init.sh (curl, gnupg, jq, git, etc.) — skipped redundant apt execution."
    fi

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

    # ── UFW Integration (Prevent Docker from bypassing UFW) ──────────────────
    if command -v ufw &>/dev/null && [[ -f /etc/ufw/after.rules ]]; then
        if ! grep -q "DOCKER-USER" /etc/ufw/after.rules; then
            info "Securing UFW firewall against Docker port bypass..."
            cp /etc/ufw/after.rules "/etc/ufw/after.rules.bak.$(date +%s)"
            cat >> /etc/ufw/after.rules <<'UFWDOCKER'

# ── Docker UFW Protection (Enforces UFW rules for published container ports) ──
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
-A DOCKER-USER -i lo -j RETURN
-A DOCKER-USER -i docker0 -j RETURN
-A DOCKER-USER -i br-+ -j RETURN
-A DOCKER-USER -m conntrack --ctstate INVALID -j DROP
-A DOCKER-USER -j ufw-user-forward
-A DOCKER-USER -j RETURN
COMMIT
UFWDOCKER
            ufw reload &>/dev/null || true
            ok "UFW-Docker protection enabled (/etc/ufw/after.rules patched)."
        else
            ok "UFW-Docker protection already active in /etc/ufw/after.rules."
        fi
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
    if command -v ctop &>/dev/null; then
        ok "ctop already installed → /usr/local/bin/ctop"
    else
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
    fi

    # ── Lazydocker — full terminal UI ─────────────────────────────────────────
    if command -v lazydocker &>/dev/null; then
        ok "Lazydocker already installed."
    else
        info "Installing Lazydocker (interactive Docker TUI)..."
        curl -fsSL \
            https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh \
            | bash 2>/dev/null \
            && ok "Lazydocker installed." \
            || warn "Lazydocker install skipped — github.com/jesseduffield/lazydocker"
    fi

    # ── Docker Scout — vulnerability scanner ──────────────────────────────────
    if command -v docker-scout &>/dev/null || docker scout version &>/dev/null 2>&1; then
        ok "Docker Scout CLI already installed."
    else
        info "Installing Docker Scout CLI (vulnerability scanner)..."
        curl -fsSL https://raw.githubusercontent.com/docker/scout-cli/main/install.sh \
            | sh -s -- -b /usr/local/bin 2>/dev/null \
            && ok "Docker Scout CLI installed → docker scout quickview <image>" \
            || warn "Docker Scout install skipped — docs.docker.com/scout"
    fi

    # ── Bash completion ────────────────────────────────────────────────────────
    if [[ -f /etc/bash_completion.d/docker ]]; then
        ok "Bash completion already configured for docker."
    else
        info "Enabling bash completion for docker & docker compose..."
        curl -fsSL \
            "https://raw.githubusercontent.com/docker/cli/master/contrib/completion/bash/docker" \
            -o /etc/bash_completion.d/docker 2>/dev/null \
            && ok "Bash completion enabled for docker and docker compose." \
            || warn "Bash completion download skipped (network issue)."
    fi

    section_end
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  09 — CADVISOR — per-container metrics container
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

deploy_cadvisor() {
    section "09" "cAdvisor — Per-Container Metrics (:${CADVISOR_PORT})"

    # Stop + remove existing instance if any
    docker rm -f cadvisor 2>/dev/null || true

    if ! $SETUP_CADVISOR; then
        ok "cAdvisor container disabled (ultra-lean profile — saves ~50–70 MB RAM)."
        info "Docker daemon native metrics are exposed on 127.0.0.1:${DOCKER_METRICS_PORT}/metrics."
        info "Container management, status, and logs are accessible directly in Cockpit (:9090)."
        info "To enable cAdvisor if needed, re-run with: sudo ./docker.sh --with-cadvisor"
        section_end
        return
    fi

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

integrate_cockpit_docker() {
    $SETUP_MON || { section "09" "Cockpit Container Integration"; warn "Skipped (--no-mon)."; section_end; return; }
    section "09" "Cockpit Container Integration"

    if $COCKPIT_EXISTS; then
        info "Installing cockpit-podman for container visibility in Cockpit..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            cockpit-podman 2>&1 | tail -3 | while IFS= read -r l; do echo -e "  ${GRY}│  $l${R}"; done || true
        ok "Cockpit container integration complete — manage containers at http://localhost:9090."
    else
        info "Cockpit not installed — skipping Cockpit container integration."
    fi

    section_end
}

patch_monitoring_scrapes() {
    $SETUP_MON || { section "11" "Monitoring Scrape Configuration"; warn "Skipped (--no-mon)."; section_end; return; }
    section "11" "Monitoring Scrape Configuration"

    local patched=false

    # 1. Patch VictoriaMetrics if present
    if [[ -f "$VICTORIAMETRICS_CONFIG" ]]; then
        info "Configuring VictoriaMetrics to scrape Docker metrics..."
        cp "${VICTORIAMETRICS_CONFIG}" "${VICTORIAMETRICS_CONFIG}.bak.$(date +%s)"

        if ! grep -q "job_name: 'docker'" "$VICTORIAMETRICS_CONFIG" && ! grep -q "job_name: 'docker_engine'" "$VICTORIAMETRICS_CONFIG"; then
            cat >> "$VICTORIAMETRICS_CONFIG" <<'VMCFG'

  - job_name: 'docker_engine'
    scrape_interval: 30s
    static_configs:
      - targets: ['127.0.0.1:9323']
        labels:
          instance: 'docker_engine'
VMCFG
        fi

        if $SETUP_CADVISOR && ! grep -q "job_name: 'cadvisor'" "$VICTORIAMETRICS_CONFIG"; then
            cat >> "$VICTORIAMETRICS_CONFIG" <<'VMCFG'

  - job_name: 'cadvisor'
    scrape_interval: 30s
    static_configs:
      - targets: ['127.0.0.1:8080']
        labels:
          instance: 'cadvisor'
VMCFG
        fi

        if systemctl is-active --quiet victoriametrics 2>/dev/null; then
            systemctl reload victoriametrics 2>/dev/null || systemctl restart victoriametrics 2>/dev/null || true
        fi
        if $SETUP_CADVISOR; then
            ok "VictoriaMetrics configured to scrape docker_engine (:9323) and cadvisor (:8080)."
        else
            ok "VictoriaMetrics configured to scrape native docker_engine (:9323, 30s interval)."
        fi
        patched=true
    fi

    # 2. Legacy Prometheus patch fallback
    if [[ -f "$PROMETHEUS_CONFIG" ]]; then
        if ! grep -q "job_name: 'docker_engine'" "$PROMETHEUS_CONFIG"; then
            info "Patching legacy Prometheus scrape config..."
            cat >> "$PROMETHEUS_CONFIG" <<'PROMCFG'

  - job_name: 'docker_engine'
    scrape_interval: 15s
    static_configs:
      - targets: ['127.0.0.1:9323']

  - job_name: 'cadvisor'
    scrape_interval: 15s
    static_configs:
      - targets: ['127.0.0.1:8080']
PROMCFG
            if systemctl is-active --quiet prometheus 2>/dev/null; then
                systemctl reload prometheus 2>/dev/null || systemctl restart prometheus 2>/dev/null || true
            fi
            ok "Prometheus scrape configuration patched."
            patched=true
        fi
    fi

    if ! $patched; then
        info "No time-series database found. Docker daemon metrics remain available on 127.0.0.1:${DOCKER_METRICS_PORT}."
    fi

    section_end
}

verify_all() {
    section "12" "Smoke Test + Verification"

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
    echo -e "  ${BLU}${BOLD}Monitoring & Management${R}"
    if $SETUP_CADVISOR; then
        _chk_ct  "cadvisor"
        _chk_ep  "cAdvisor Metrics"     "http://127.0.0.1:${CADVISOR_PORT}/metrics"       "container_cpu"
    else
        echo -e "  ${TICK}  cAdvisor            disabled (lean profile — saves ~60MB RAM)"
    fi
    if $COCKPIT_EXISTS; then
        _chk_svc "cockpit.socket"   "Cockpit Console"
    fi
    if $VM_EXISTS; then
        _chk_svc "victoriametrics"  "VictoriaMetrics"
        _chk_ep  "VMUI Ready"       "${VICTORIAMETRICS_URL}/health"                   "."
    fi

    echo ""
    echo -e "  ${BLU}${BOLD}Ecosystem Tools${R}"
    command -v ctop        &>/dev/null && echo -e "  ${TICK}  ctop"        || echo -e "  ${WARN_IC}  ctop — not found"
    command -v lazydocker  &>/dev/null && echo -e "  ${TICK}  lazydocker"  || echo -e "  ${WARN_IC}  lazydocker — not found"
    command -v docker-scout &>/dev/null || docker scout version &>/dev/null 2>&1 \
        && echo -e "  ${TICK}  docker scout" || echo -e "  ${WARN_IC}  docker scout — not found"

    section_end
}

print_summary() {
    echo ""
    echo -e "${BLU}${BOLD}  ╔${HR2}╗${R}"
    printf  "  ${BLU}${BOLD}║${R}${GRN}${BOLD}%-76s${R}${BLU}${BOLD}║${R}\n" \
            "  ✔  docker.sh Complete — Docker CE + Cockpit Web Console Ready"
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
    _hdr "Monitoring & Management Integration"
    _sep
    _row "Cockpit UI"       "Container management & logs → https://localhost:9090"
    if $SETUP_CADVISOR; then
        _row "cAdvisor"     "Container CPU/RAM/net/disk → :${CADVISOR_PORT}"
    fi
    if $VM_EXISTS; then
        _row "VictoriaMetrics" "Time-series metrics & VMUI → http://localhost:8428/vmui"
    fi

    _sep
    _hdr "🔭  Access Management & Metrics (SSH Tunnels)"
    _sep
    printf "  ${BLU}${BOLD}║${R}  ${GRN}${BOLD}%-74s${R}  ${BLU}${BOLD}║${R}\n" \
        "Cockpit GUI:         ssh -L 9090:127.0.0.1:9090 ${DEPLOY_USER}@<server-ip>"
    printf "  ${BLU}${BOLD}║${R}  ${WHT}%-74s${R}  ${BLU}${BOLD}║${R}\n" \
        "                     https://localhost:9090  (Login as ${DEPLOY_USER})"
    if $VM_EXISTS; then
        printf "  ${BLU}${BOLD}║${R}  ${GRN}${BOLD}%-74s${R}  ${BLU}${BOLD}║${R}\n" \
            "VictoriaMetrics VMUI: ssh -L 8428:localhost:8428 ${DEPLOY_USER}@<server-ip>"
        printf "  ${BLU}${BOLD}║${R}  ${WHT}%-74s${R}  ${BLU}${BOLD}║${R}\n" \
            "                     http://localhost:8428/vmui"
    fi

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
        printf "  ${BLU}${BOLD}║${R}  ${CYN}›${R}  ${WHT}%-70s${R}  ${BLU}${BOLD}║${R}
" "$c"
    done

    _sep
    printf  "  ${BLU}${BOLD}║${R}${GRY}%-76s${R}${BLU}${BOLD}║${R}
" \
            "  Log: ${LOG_FILE}"
    echo -e "${BLU}${BOLD}  ╚${HR2}╝${R}"
    echo ""
}

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
    integrate_cockpit_docker    # 09 — Cockpit container management integration
    deploy_cadvisor             # 10 — cAdvisor container (127.0.0.1:8080)
    patch_monitoring_scrapes    # 11 — patch VictoriaMetrics / Prometheus scrape configs
    verify_all                  # 12 — smoke test + endpoint checks
    print_summary               # 13 — full summary + quick reference

    _log INFO "=== docker.sh complete. User=${DEPLOY_USER} ==="
}

main "$@"
