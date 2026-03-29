# PM2 Enhanced Logging Guide

**Status**: ✅ **Fully Automatic** — Logs created automatically for **any** PM2 app with no extra config needed

---

## ✅ Fully Automatic — What Happens When init.sh Runs

When you run the `init.sh` provisioning script, **everything for PM2 logging is set up automatically**:

| Component | What Gets Set Up | Auto? |
|-----------|-----------------|-------|
| **Log rotation** | pm2-logrotate module installed | ✅ Yes |
| **Log format** | Timestamps (YYYY-MM-DD HH:mm:ss Z) | ✅ Yes |
| **Logs directory** | `~/.pm2/logs/` created | ✅ Yes |
| **Helper commands** | `pstart`, `plog_app`, `plog_errors` | ✅ Yes |
| **Grafana integration** | Logs sent to Loki automatically | ✅ Yes |
| **Global defaults** | Set for ALL apps | ✅ Yes |

**Result**: From the moment PM2 is installed, **every app you start gets detailed logging automatically** — no configuration required!

---

## 🚀 First 30 Seconds — Start an App

```bash
# Done! Logs appear automatically with timestamps + separati on
pstart app.js --name myapp

# View logs
plog_app myapp

# Save for reboot
pm2 save
```

**That's it!** Your app now has:
- ✅ Output logs at `~/.pm2/logs/myapp-out.log`
- ✅ Error logs at `~/.pm2/logs/myapp-error.log`  
- ✅ Timestamps on every line
- ✅ Auto-rotation (50MB files, 10 retained)
- ✅ Grafana visibility

---

## ✅ What's Automatic (No Setup Required)

**When you run init.sh, these are set up automatically:**

1. ✅ **Log rotation module** — `pm2-logrotate` installed (50MB files, 10-file retention)
2. ✅ **Timestamps enabled** — Every log line has `YYYY-MM-DD HH:mm:ss Z` format
3. ✅ **Global logging defaults** — Applied to ALL pm2 apps
4. ✅ **Logs directory** — Created at `~/.pm2/logs/` with proper permissions
5. ✅ **Helper commands** — `pstart`, `plog_app`, `plog_errors`, `plog_size` all ready to use

**Result**: When you start any PM2 app, it **automatically gets separate output + error logs** without any extra work!

---

## 🚀 Quickest Way to Start Apps (Fully Automatic)

### Option 1: Simple App Start (RECOMMENDED)

```bash
# Start with auto-logging — no config needed!
pstart app.js

# Or with app name
pstart app.js --name myapp

# With arguments
pstart app.js --name api -- --port 3000
```

✅ **Fully automatic** — Logs created at:
- `~/.pm2/logs/myapp-out.log` — Normal output
- `~/.pm2/logs/myapp-error.log` — Errors only

### Option 2: Ecosystem Config (Multiple Apps)

If you have **multiple related apps**, use ecosystem config:

```bash
# Copy template
cp ~/.pm2/ecosystem.template.js ecosystem.config.js

# Edit it
nano ecosystem.config.js

# Start all at once
pm2 start ecosystem.config.js
```

---

## 📝 What Gets Logged Automatically

When you start **any app** with `pstart` or `pm2 start`:

| Log File | Contains | Auto-Created |
|----------|----------|--------------|
| `app-name-out.log` | Normal console.log output | ✅ Yes |
| `app-name-error.log` | Errors, exceptions, warnings | ✅ Yes |
| `app-name-combined.log` | Both (for Grafana) | ✅ Yes |

**Timestamps added automatically**:
```
2026-03-30 14:23:45 +0000 Server listening on port 3000
2026-03-30 14:23:47 +0000 Database connected
2026-03-30 14:25:00 +0000 [ERROR] Connection failed
```

---

## 🎯 View Your Logs

Once an app is running with logs:

```bash
# View last 100 lines (one app only)
plog_app myapp

# View errors only
plog_errors myapp

# View all errors across all apps
plog_errors

# Check log file sizes
plog_size

# Live streaming of all apps mixed
logs

# Traditional pm2 status
pstatus
```

---

## ⚙️ What Happens Behind the Scenes

When you use `pstart app.js`:

1. Detects app name from filename or `--name` flag
2. Creates `~/.pm2/logs/` directory if it doesn't exist
3. Sets `--output ~/.pm2/logs/app-name-out.log`
4. Sets `--error ~/.pm2/logs/app-name-error.log`
5. Enables `--log-date-format 'YYYY-MM-DD HH:mm:ss Z'`
6. Starts the app with PM2
7. Logs automatically sent to Grafana/Loki

**Zero config needed** — Just run and logs appear!

---

## 📊 Real-World Examples

### Single App

```bash
# Start your API server
pstart app.js --name api

# Logs appear at:
# ~/.pm2/logs/api-out.log
# ~/.pm2/logs/api-error.log

# View them
plog_app api
```

### Multiple Apps (Independent)

```bash
# App 1: Main API
pstart api.js --name api -- --port 3000

# App 2: Background worker
pstart worker.js --name worker -- --concurrency 5

# App 3: WebSocket
pstart socket.js --name websocket -- --port 4000

# Each has separate logs:
# ~/.pm2/logs/api-out.log (+ error)
# ~/.pm2/logs/worker-out.log (+ error)
# ~/.pm2/logs/websocket-out.log (+ error)

# View separately
plog_app api
plog_app worker
plog_app websocket

# Or see all logs mixed
logs
```

### Multiple Apps (Organized)

If you have **many related apps**, use ecosystem config:

```bash
cp ~/.pm2/ecosystem.template.js ecosystem.config.js
# Edit to customize your 3+ apps with different ports/settings
nano ecosystem.config.js

pm2 start ecosystem.config.js
pm2 save  # Survive reboots
```

---

## 🔄 Automatic Log Rotation

**Already configured** — No manual setup needed!

| Setting | Value |
|---------|-------|
| **Max file size** | 50MB (rotates early) |
| **Daily rotation** | 00:00 UTC (configurable) |
| **Files kept** | 10 old versions |
| **Compression** | Auto `.gz` old files |
| **Total retention** | ~500MB of logs |

**Example rotation**:
```
api-out.log              (current - today)
api-out.log.1.gz         (yesterday)
api-out.log.2.gz         (2 days ago)
...
api-out.log.10.gz        (10 days ago - oldest kept)
```

**Manual cleanup** (if needed):
```bash
plog_clear app-name     # Clear one app's logs
plog_clear all          # Clear all logs
```

---

## 📊 Available Commands

| Command | Purpose | Auto? |
|---------|---------|-------|
| `pstart app.js` | **Start with auto-logging** | ✅ Yes |
| `pstart app.js --name api` | Start with custom name | ✅ Yes |
| `plog_app myapp` | View one app's logs | ✅ Yes |
| `plog_errors` | View all errors | ✅ Yes |
| `plog_errors myapp` | View one app's errors | ✅ Yes |
| `plog_size` | Check log sizes | ✅ Yes |
| `logs` | Live mix of all apps | ✅ Yes |
| `pstatus` | App status | ✅ Yes |
| `psave` | Save state for reboot | ✅ Yes |

---

## 🎯 Common Workflows

### Start & Monitor One App

```bash
# Start app
pstart myapp.js --name myapp

# Check it's running
pstatus

# View its logs
plog_app myapp

# View only its errors
plog_errors myapp

# Watch logs live
pm2 logs myapp

# Monitor CPU/RAM
pmonit
```

### Start Multiple Apps & Monitor Together

```bash
# Start app 1
pstart api.js --name api

# Start app 2
pstart worker.js --name worker

# Start app 3
pstart websocket.js --name websocket

# See all 3 running
pstatus

# View collectively
logs                # All logs mixed
plog_errors         # All errors
plog_size           # Total size

# Or individually
plog_app api
plog_app worker
plog_app websocket
```

### Debug a Crashing App

```bash
# Check status
pstatus

# View just that app's recent logs
plog_app crashing-app

# View only errors
plog_errors crashing-app

# Watch it live
tail -f ~/.pm2/logs/crashing-app-error.log

# Fix the code, then
pm2 restart crashing-app
```

---

## 📋 Log File Locations

```
~/.pm2/logs/
├── app1-out.log           (standard output/console.log)
├── app1-error.log         (errors/exceptions)
├── app1-combined.log      (both — for aggregation)
│
├── app2-out.log
├── app2-error.log
├── app2-combined.log
│
└── ... (one set per app)
```

**Old (rotated) logs**:
```
app1-out.log.1.gz
app1-out.log.2.gz
```

---

## Grafana Integration (Automatic)

All logs are **automatically sent to Grafana** via Loki.

### Access Grafana

```bash
# SSH tunnel to Grafana
ssh -L 3001:localhost:3001 username@server

# Open browser to http://localhost:3001
# Login: admin / admin (change password immediately!)
```

### Query PM2 Logs in Grafana

1. Go to **Explore** tab
2. Select **Loki** data source
3. Run query:

```
# All PM2 logs
{job="pm2"}

# Specific app
{job="pm2", app="myapp"}

# Just errors
{job="pm2"} | json | level="error"
```

---

## 📋 Setup Summary

### Automatic (No Work Needed)

✅ PM2 installed  
✅ Log rotation configured  
✅ Logging format set  
✅ Helper commands created  
✅ Grafana integration ready  

### Your First App (30 seconds)

```bash
pstart my-app.js --name my-app
plog_app my-app           # View logs immediately
pm2 save                  # Survive reboot
```

**Done!** App is running with:
- ✅ Separate output + error logs
- ✅ Timestamps on every line  
- ✅ Auto-rotation (50MB/day)
- ✅ Grafana integration
- ✅ Error filtering available

---

## Log Format Examples

### With Timestamps (Detailed)

When `log_date_format` is set, each line has timestamp:

```
2026-03-30 14:23:45 +0000 Server listening on port 3000
2026-03-30 14:23:47 +0000 Database connected successfully
2026-03-30 14:24:01 +0000 GET /api/users - 200 - 1.23ms
2026-03-30 14:24:15 +0000 POST /api/users - 201 - created
2026-03-30 14:25:00 +0000 [ERROR] Failed to fetch user: Connection timeout
```

### Error-Only Logs

api-server-error.log contains **only** error/warning lines:

```
2026-03-30 14:25:00 +0000 [ERROR] Failed to fetch user: Connection timeout
2026-03-30 14:26:12 +0000 [WARN] Memory usage at 85%
2026-03-30 14:27:34 +0000 [ERROR] Database connection lost
2026-03-30 14:28:01 +0000 [ERROR] Unhandled promise rejection
```

---

## Available Aliases & Commands

| Command | Purpose |
|---------|---------|
| `logs` | Live mix of all app logs |
| `plog_app <name>` | Last 100 lines for ONE app |
| `plog_errors [name]` | Show ERROR lines (all apps or one) |
| `plog_size` | Check log file sizes & total |
| `plog_clear [name]` | Clear logs manually |
| `pstatus` | List all running apps |
| `pmonit` | Live CPU/RAM monitor |
| `prestart` | Restart all apps |
| `psave` | Save PM2 state for reboot |

---

## Multiple Apps Example

If you have 3 apps configured:

```javascript
// ecosystem.config.js
apps: [
  { name: 'api-server', ... },          // ← Separate logs
  { name: 'worker-jobs', ... },         // ← Separate logs
  { name: 'realtime-service', ... }     // ← Separate logs
]
```

Then you can:

```bash
# See output from api-server only (no mixing with other apps)
plog_app api-server

# See errors from worker-jobs only
plog_errors worker-jobs

# View all errors across all 3 apps
plog_errors

# See which logs exist
ls -lh ~/.pm2/logs/
```

Output:
```
-rw-r--r-- 1 user user  12M Mar 30 14:25 api-server-out.log
-rw-r--r-- 1 user user 4.2M Mar 30 14:25 api-server-error.log
-rw-r--r-- 1 user user 8.5M Mar 30 14:25 worker-jobs-out.log
-rw-r--r-- 1 user user  2.1M Mar 30 14:25 worker-jobs-error.log
-rw-r--r-- 1 user user 1.5M Mar 30 14:25 realtime-service-out.log
-rw-r--r-- 1 user user  512K Mar 30 14:25 realtime-service-error.log
```

---

## Log Rotation Details

### Automatic Rotation Settings

Configuration file: `/home/<username>/.pm2/conf.js` (auto-managed)

Current settings:
- **max_size**: 50MB per file
- **retain**: 10 rotated files kept
- **compress**: Gzip compression enabled
- **cron**: Daily at 00:00 UTC (configurable)
- **dateFormat**: `YYYY-MM-DD_HH-mm-ss` for rotated file names

### Rotation Example

After daily rotation, your logs look like:

```
api-server-out.log              (current, today's logs)
api-server-out.log.1.gz         (yesterday)
api-server-out.log.2.gz         (2 days ago)
api-server-out.log.3.gz         (3 days ago)
...
api-server-out.log.10.gz        (10 days ago - oldest kept)
```

Old files beyond 10 days are deleted automatically.

### Manual Rotation Trigger

Force rotation immediately:
```bash
pm2 update pm2-logrotate  # Just updated, trigger rotation
```

---

## Monitoring & Analysis

### Find Specific Errors

```bash
# Find all "Connection timeout" errors
grep "Connection timeout" ~/.pm2/logs/*-error.log

# Find errors from past 1 hour
find ~/.pm2/logs -name "*-error.log" -mmin -60 -exec grep "ERROR" {} +

# Count total errors
grep -c "ERROR" ~/.pm2/logs/*-error.log 2>/dev/null | grep -v ":0$"
```

### Watch Logs in Real-Time (One App)

```bash
# Follow error logs as they happen
tail -f ~/.pm2/logs/api-server-error.log

# Follow output logs
tail -f ~/.pm2/logs/api-server-out.log

# Use tail with filtering
tail -f ~/.pm2/logs/api-server-out.log | grep "GET\|POST"
```

### Search Logs by Date

```bash
# Logs from March 30 at 14:00
grep "2026-03-30 14:" ~/.pm2/logs/api-server-out.log

# Logs from 14:00 to 14:30
grep "2026-03-30 14:[012][0-9]" ~/.pm2/logs/api-server-out.log
```

---

## Grafana Integration

All PM2 logs are automatically sent to Loki (log aggregation backend).

### View in Grafana

1. Open Grafana: `http://localhost:3001` (admin/admin)
2. Go to **Explore** → Select **Loki** as data source
3. Run queries:

```
# All PM2 logs
{job="pm2"}

# Specific app
{job="pm2", filename="api-server-combined.log"}

# Just errors
{job="pm2", filename="api-server-error.log"}

# Search for keyword
{job="pm2"} |= "database error"
```

---

## Troubleshooting

### Logs Not Appearing

```bash
# Check if PM2 apps are running
pm2 status

# Check if output file is writable
ls -la ~/.pm2/logs/

# Check if logs are being written
wc -l ~/.pm2/logs/*-out.log

# Check PM2 itself
pm2 log  # System PM2 logs
```

### Logs Growing Too Fast

Adjust rotation in PM2 (requires restart):

```bash
pm2 set pm2-logrotate:max_size 20M   # Reduce to 20MB
pm2 set pm2-logrotate:retain 5       # Keep only 5 files
pm2 save
pm2 restart all
```

### Finding Old Logs

```bash
# List all compressed logs by date
ls -ltrh ~/.pm2/logs/*.log*.gz | head -20

# Find logs older than 7 days (to delete)
find ~/.pm2/logs -name "*.log.*.gz" -mtime +7 -ls

# Delete logs manually (if rotation fails)
# rm ~/.pm2/logs/*.log.*.gz  # Remove old compressed
# rm ~/.pm2/logs/*.log.10    # Remove beyond retention
```

---

## Environment-Specific Logging

### Development (DEBUG level)

```javascript
{
  name: 'api-dev',
  env: {
    NODE_ENV: 'development',
    LOG_LEVEL: 'debug'  // Verbose logging
  }
}
```

### Production (INFO level)

```javascript
{
  name: 'api-prod',
  env: {
    NODE_ENV: 'production',
    LOG_LEVEL: 'info'   // Less verbose
  }
}
```

Your app should read `process.env.LOG_LEVEL` and adjust logging verbosity:

```javascript
const logger = require('winston');

const logLevel = process.env.LOG_LEVEL || 'info';
logger.level = logLevel;

logger.info('App started');  // Always shown in INFO level
logger.debug('Debug info');  // Only shown in DEBUG level
```

---

## File Permissions

PM2 logs are readable by:
- **Owner**: Read/Write (`600`)
- **Group**: Read-only
- **Others**: No access

Check permissions:
```bash
ls -la ~/.pm2/logs/
# -rw------- 1 username username 12M Mar 30 ...
```

To allow Promtail to read PM2 logs:
```bash
# Already configured by init.sh — Promtail user has ACL access
getfacl ~/.pm2/logs/
```

---

## Best Practices

### 1. Use Descriptive App Names

```javascript
// Good — clear what each app does
{ name: 'api-server' }
{ name: 'background-worker' }
{ name: 'realtime-websocket' }

// Avoid — unclear
{ name: 'app1' }
{ name: 'app2' }
```

### 2. Set LOG_LEVEL via Environment

```javascript
{
  name: 'api',
  env: {
    LOG_LEVEL: process.env.LOG_LEVEL || 'info'
  }
}
```

### 3. Use Error Files for Alerting

Monitor error files only:
```bash
# Check if errors appeared in last 5 minutes
if [[ -n "$(find ~/.pm2/logs -name '*-error.log' -mmin -5)" ]]; then
  echo "Recent errors detected!"
fi
```

### 4. Archive Old Logs

```bash
# Deploy: Keep last 30 days only
find ~/.pm2/logs -name "*.log.*.gz" -mtime +30 -delete
```

### 5. Rotate on Size & Time

Already configured! But you can adjust:
```bash
pm2 set pm2-logrotate:cron '0 2 * * *'  # 2 AM instead of midnight
```

---

## Summary

| Feature | Status | Notes |
|---------|--------|-------|
| Per-app logs | ✅ | Separate output + error files |
| Timestamps | ✅ | `YYYY-MM-DD HH:mm:ss Z` format |
| Auto-rotation | ✅ | 50MB size or daily (whichever first) |
| Error separation | ✅ | Errors in dedicated `-error.log` files |
| Retention | ✅ | 10 old files kept + compressed |
| Grafana integration | ✅ | All logs sent to Loki automatically |
| CLI aliases | ✅ | `plog_*` commands for easy access |
| Log aggregation | ✅ | `{job="pm2"}` in Grafana Loki |

---

## Quick Reference

```bash
# View live logs
logs

# View one app's last 100 lines
plog_app api-server

# View errors only
plog_errors

# Check log sizes
plog_size

# Configure new app
cp ~/.pm2/ecosystem.template.js ecosystem.config.js
nano ecosystem.config.js
pm2 start ecosystem.config.js

# Check status
pm2 status

# Save for reboot
pm2 save
```

---

**Created**: 2026-03-30  
**Version**: 1.0  
**Enhancement Status**: ✅ Complete  
