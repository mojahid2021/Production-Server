# Cockpit Web Console & Node.js (PM2) GUI Verification Guide

This guide helps verify that **Cockpit Web Console** (host management, hardware charts, systemd units, Docker, and journald logs) and the custom **Native Node.js (PM2) GUI Extension** are functioning properly with **zero idle memory overhead**.

---

## 1. Quick Status Check

Run the built-in CLI status utility from anywhere on the server:

```bash
server_status
```

Or verify individual components directly:

```bash
# Check Cockpit socket (must be active/listening)
systemctl is-active cockpit.socket

# Verify PM2 admin bridge returns valid JSON
/usr/local/bin/pm2-admin json

# Check PM2 CLI status
pstatus
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
  - Docker container management (via `cockpit-podman` when `docker.sh` is run).

### Application Management Layer (Cockpit Node.js PM2 Extension)
- **Native Extension Package** (`/usr/share/cockpit/node-pm2/`):
  - Consumes **0 MB RAM** when idle (no persistent Node/Go daemon running in background).
  - Built with PatternFly UI styles matching native Cockpit aesthetics.
  - Uses `cockpit.js` to execute `/usr/local/bin/pm2-admin` on the host on demand.
  - Features 4 live stat cards: **Online Apps**, **Restarts**, **Total App Memory**, and **Average CPU**.
  - Interactive application table with one-click actions: **Restart**, **Stop**, **Start**, and **View Logs** (modal tailing 100 lines).
  - Global controls for **Restart All** and **Save State** (`pm2 save`).
  - Auto-refreshes state every 3 seconds while viewing the page.

---

## 3. Step-by-Step Verification

### Step 1: Verify Systemd Socket
Check that the Cockpit socket is enabled and listening strictly on localhost:

```bash
# Check socket status
systemctl status cockpit.socket

# Confirm it is listening strictly on 127.0.0.1:9090
ss -tlpn | grep 9090
```

Expected output:
```
LISTEN 0 128 127.0.0.1:9090 0.0.0.0:*
```

### Step 2: Verify PM2 Admin Bridge
Test that the CLI bridge can communicate with PM2 under the deploy user:

```bash
# Test JSON output
/usr/local/bin/pm2-admin json
```

You should see a JSON array representing your PM2 processes (or `[]` if no applications have been started yet).

### Step 3: Access Cockpit Web Console
Cockpit binds to `127.0.0.1:9090` for maximum security. Connect using an encrypted SSH port-forwarding tunnel:

```bash
# Run on your local computer/laptop:
ssh -L 9090:127.0.0.1:9090 deploy_user@<server-ip>
```

Then open `https://localhost:9090` in your web browser:
1. Accept the self-signed TLS certificate warning (expected for localhost connection).
2. Log in with your `deploy_user` (or `root`) and server password.
3. Verify the navigation sidebar contains:
   - **Overview**: Real-time CPU, RAM, disk I/O, network traffic.
   - **Node.js (PM2)**: Dedicated app manager tab.
   - **Logs**: Filter journald logs by severity, application unit, or keyword.
   - **Services**: Start, stop, or restart PM2, Nginx, or Docker.
   - **Containers**: View running containers, CPU/RAM stats, and logs (if `docker.sh` is installed).
   - **Terminal**: Browser-based terminal with sudo access.

### Step 4: Verify Node.js (PM2) GUI Tab
Click on **Node.js (PM2)** in Cockpit's left sidebar:
1. Verify summary cards load:
   - **Online Apps**
   - **Total Restarts**
   - **Memory Usage**
   - **Average CPU**
2. Deploy or start a sample application to test:
   ```bash
   # Start a quick test app
   pm2 start "node -e 'setInterval(() => console.log(new Date().toISOString(), \"Heartbeat\"), 3000)'" --name demo-app
   pm2 save
   ```
3. In the Cockpit UI:
   - Observe `demo-app` appearing with a green **online** badge.
   - Click **View Logs** to view live streaming stdout/stderr in the modal dialog.
   - Click **Restart** or **Stop** and observe the status update in real time.

---

## 4. Troubleshooting Guide

### Issue: Cockpit Web Console Won't Connect
1. Verify `cockpit.socket` is listening:
   ```bash
   ss -tlpn | grep 9090
   ```
2. Check Cockpit journal logs:
   ```bash
   journalctl -u cockpit -n 30 --no-pager
   ```
3. Restart Cockpit socket:
   ```bash
   sudo systemctl restart cockpit.socket
   ```

### Issue: "Node.js (PM2)" Tab Shows "No applications currently managed"
1. Verify an application is running in PM2:
   ```bash
   pstatus
   ```
2. If your app is running as deploy user, ensure `/usr/local/bin/pm2-admin json` can see it:
   ```bash
   sudo /usr/local/bin/pm2-admin json
   ```
3. Verify `/etc/production-server.conf` specifies the correct `DEPLOY_USER`:
   ```bash
   cat /etc/production-server.conf
   ```

### Issue: Reclaiming Memory from Old Monitoring Daemons
If the server previously had Prometheus, Grafana, Loki, ClickHouse, or VictoriaMetrics installed:

```bash
sudo systemctl disable --now grafana-server prometheus loki promtail clickhouse-server victoriametrics 2>/dev/null || true
sudo rm -f /etc/systemd/system/prometheus.service /etc/systemd/system/loki.service /etc/systemd/system/promtail.service /etc/systemd/system/victoriametrics.service
sudo rm -rf /var/lib/prometheus /var/lib/loki /var/lib/clickhouse /var/lib/victoria-metrics /etc/victoriametrics 2>/dev/null || true
sudo systemctl daemon-reload
```

---

## 5. Port Reference Table

| Service | Port | Endpoint | Description | Idle RAM |
| :--- | :--- | :--- | :--- | :---: |
| **Cockpit Web Console** | `9090` | `https://localhost:9090` | Web Console, host metrics, PM2 GUI, journald logs | **0 MB** (socket-activated) |
| **Docker Daemon** | `9323` | `127.0.0.1:9323` | Native Docker engine internal metrics (via `docker.sh`) | **0 MB** (built into dockerd) |
| **cAdvisor** (Optional) | `8080` | `127.0.0.1:8080` | Optional per-container metrics (`docker.sh --with-cadvisor`) | ~25 MB |
