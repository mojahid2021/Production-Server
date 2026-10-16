# Cockpit + VictoriaMetrics Hybrid Monitoring Verification Guide

This guide helps verify that **Cockpit** (host management, hardware charts, systemd units, Docker, and journald logs) and **VictoriaMetrics Single** (PM2 application time-series metrics, Docker daemon metrics, and VMUI) are collecting and serving data correctly.

---

## 1. Quick Status Check

Run the built-in CLI status utility from anywhere on the server:

```bash
server_status
```

Or verify individual endpoints directly:

```bash
# Check all endpoints
curl -sf http://127.0.0.1:8428/health            # VictoriaMetrics TSDB
curl -sf http://127.0.0.1:9209/metrics | head    # PM2 exporter
systemctl is-active cockpit.socket               # Cockpit Web Console
```

---

## 2. Architecture Overview

### Host & System Management Layer (Cockpit)
- **Cockpit Socket** (`127.0.0.1:9090`):
  - Socket-activated (`cockpit.socket`) — consumes **0 MB RAM** when idle.
  - Native Linux integration: monitors CPU, RAM, disk I/O, network, user sessions directly via `/proc` and `/sys`.
  - Interactive web terminal with full `sudo` privilege escalation.
  - Direct integration with `systemd` (start/stop/restart PM2, Nginx, Docker).
  - Direct integration with `systemd-journald` (search, filter by priority and unit).
  - Docker container management (via `cockpit-podman`).

### Application Time-Series Observability Layer (VictoriaMetrics)
- **VictoriaMetrics Single** (`127.0.0.1:8428`):
  - Ultra-efficient single Go binary (48 MB RAM cap).
  - 15-day time-series retention with Gorilla compression.
  - Scrapes `pm2-prometheus-exporter` (`127.0.0.1:9209`) on relaxed 30s interval.
  - Scrapes `docker_engine` (`127.0.0.1:9323`) on relaxed 30s interval.
  - Built-in **VMUI** query and graph explorer at `http://127.0.0.1:8428/vmui`.

---

## 3. Step-by-Step Verification

### Step 1: Verify Systemd Services
Check that all monitoring services are enabled and active:

```bash
# Cockpit socket (must be active/listening)
systemctl status cockpit.socket

# VictoriaMetrics time-series engine
systemctl status victoriametrics
```

### Step 2: Verify VictoriaMetrics Scrape Targets
Verify that VictoriaMetrics is successfully scraping all configured targets:

```bash
# Query active targets via VictoriaMetrics API
curl -s http://127.0.0.1:8428/api/v1/targets | jq .

# Verify PM2 metrics exist in TSDB
curl -s 'http://127.0.0.1:8428/api/v1/query?query=pm2_process_cpu_usage_ratio' | jq .

# Verify node metrics exist in TSDB
curl -s 'http://127.0.0.1:8428/api/v1/query?query=node_cpu_seconds_total' | jq .
```

### Step 3: Access Cockpit Web Console
Cockpit binds to `127.0.0.1:9090` for maximum security. Connect using an SSH tunnel:

```bash
# Run on your local computer
ssh -L 9090:localhost:9090 deploy_user@<server-ip>
```

Then open `http://localhost:9090` in your browser:
- Log in with your `deploy_user` (or `root`) and server password.
- Navigate to **Overview**: real-time CPU, RAM, disk I/O, network traffic.
- Navigate to **Logs**: filter journald logs by severity, application unit, or keyword.
- Navigate to **Services**: start, stop, or restart PM2, Nginx, or Docker.
- Navigate to **Containers**: view running containers, CPU/RAM stats, and logs.
- Navigate to **Terminal**: browser-based root terminal.

### Step 4: Access VictoriaMetrics VMUI
Connect to the VictoriaMetrics VMUI explorer:

```bash
# Run on your local computer
ssh -L 8428:localhost:8428 deploy_user@<server-ip>
```

Then open `http://localhost:8428/vmui` in your browser:
- Test queries:
  - `pm2_process_memory_usage_bytes` (process RAM)
  - `pm2_process_cpu_usage_ratio` (process CPU %)
  - `pm2_process_restart_count` (crash/restart events)
  - `container_cpu_usage_seconds_total` (Docker container CPU)

---

## 4. Troubleshooting Guide

### Issue: Cockpit Web Console Won't Connect
1. Verify `cockpit.socket` is listening:
   ```bash
   ss -tlpn | grep 9090
   ```
2. Check Cockpit logs:
   ```bash
   journalctl -u cockpit -n 30
   ```
3. Restart Cockpit socket:
   ```bash
   sudo systemctl restart cockpit.socket
   ```

### Issue: VictoriaMetrics Not Scraping PM2
1. Verify PM2 exporter is running:
   ```bash
   curl -sf http://127.0.0.1:9209/metrics | grep pm2
   ```
2. If not running, reinstall PM2 exporter:
   ```bash
   su - deploy_user -c 'pm2 install pm2-prometheus-exporter'
   su - deploy_user -c 'pm2 set pm2-prometheus-exporter:port 9209'
   su - deploy_user -c 'pm2 save'
   ```
3. Check VictoriaMetrics scrape configuration:
   ```bash
   cat /etc/victoriametrics/scrape.yml
   sudo systemctl restart victoriametrics
   ```

### Issue: Reclaiming Memory from Old Stack
If you previously ran the legacy Prometheus/Grafana/Loki/ClickHouse stack, confirm that all old services are stopped:

```bash
sudo systemctl disable --now grafana-server prometheus loki promtail clickhouse-server 2>/dev/null || true
sudo rm -rf /var/lib/prometheus /var/lib/loki /var/lib/clickhouse 2>/dev/null || true
```

---

## 5. Port Reference Table

| Service | Port | Endpoint | Description |
| :--- | :--- | :--- | :--- |
| **Cockpit** | `9090` | `/` | Web Console, host management, journald logs (0 MB idle) |
| **VictoriaMetrics** | `8428` | `/vmui`, `/health`, `/api/v1` | Time-series TSDB & PromQL visualizer (48 MB cap) |
| **PM2 Exporter** | `9209` | `/metrics` | PM2 Node.js process metrics |
| **Docker Daemon** | `9323` | `/metrics` | Docker engine internal metrics (native, 0 containers) |
| **cAdvisor** | `8080` | `/metrics`, `/healthz` | Per-container metrics (optional via `--with-cadvisor`) |
