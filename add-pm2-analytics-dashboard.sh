#!/bin/bash
# [LEGACY] Add PM2 Per-Process Analytics Dashboard to existing Grafana installation
# NOTE: The default production stack now uses Cockpit (:9090) and VictoriaMetrics (:8428).
# This script is retained for backward compatibility with legacy Grafana deployments.

set -euo pipefail

if ! command -v grafana-server &>/dev/null && [[ ! -d "/var/lib/grafana" ]]; then
    echo "Notice: Grafana is not installed on this server."
    echo "The production server monitoring architecture uses Cockpit (:9090) and VictoriaMetrics (:8428)."
    echo "This script is retained for legacy Grafana deployments only."
    exit 0
fi

DASHBOARD_PATH="/var/lib/grafana/dashboards/applications/04-pm2-per-process-analytics.json"

echo "Adding PM2 Per-Process Analytics Dashboard to Grafana..."

# Create the dashboard file
cat > "$DASHBOARD_PATH" <<'PERPROCASH'
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
          "expr": "100 * (sum(count_over_time({job=\"pm2\"}[5m])) - sum(count_over_time({job=\"pm2\"} |~ \"ERROR|Exception|WARN|WARNING\"[5m]))) / (sum(count_over_time({job=\"pm2\"}[5m])) + 1)",
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
          "expr": "100 * sum(count_over_time({job=\"pm2\"} |~ \"ERROR|Exception\" [5m])) / (sum(count_over_time({job=\"pm2\"}[5m])) + 1)",
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
          "expr": "100 * sum(count_over_time({job=\"pm2\"} |~ \"WARN|WARNING\" [5m])) / (sum(count_over_time({job=\"pm2\"}[5m])) + 1)",
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
          "expr": "sum(count_over_time({job=\"pm2\"}[1m]))",
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
          "expr": "sum(count_over_time({job=\"pm2\"} |~ \"ERROR|Exception\" [5m])) by (name)",
          "legendFormat": "{{name}}",
          "refId": "A" }
      ],
      "title": "Errors per Process",
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
          "expr": "sum(count_over_time({job=\"pm2\"} |~ \"WARN|WARNING\" [5m])) by (name)",
          "legendFormat": "{{name}}",
          "refId": "A" }
      ],
      "title": "Warnings per Process",
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
                   "showCommonLabels": false, "showLabels": false, "showTime": true,
                   "sortOrder": "Descending", "wrapLogMessage": true },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "{job=\"pm2\"}",
          "legendFormat": "",
          "refId": "A" }
      ],
      "title": "📋 Detailed PM2 Process Logs",
      "type": "logs"
    }
  ],
  "refresh": "5s",
  "schemaVersion": 38,
  "tags": ["pm2", "processes", "analytics"],
  "time": { "from": "now-6h", "to": "now" },
  "timepicker": {},
  "timezone": "browser",
  "title": "🔍 PM2 Per-Process Analytics",
  "description": "Detailed log-based analytics: success/error/warning rates, per-process metrics, full log viewer",
  "uid": "pm2-per-process-analytics",
  "version": 1,
  "style": "dark"
}
PERPROCASH

# Set proper permissions
chmod 644 "$DASHBOARD_PATH"
chown grafana:grafana "$DASHBOARD_PATH" 2>/dev/null || true

echo "✅ Dashboard file created: $DASHBOARD_PATH"

# ─────────────────────────────────────────────────────────────────────────────
# Create Per-Process Template Dashboard
# ─────────────────────────────────────────────────────────────────────────────

TEMPLATE_PATH="/var/lib/grafana/dashboards/applications/05-template-pm2-per-process-analytics.json"

echo ""
echo "Creating per-process template dashboard..."

cat > "$TEMPLATE_PATH" <<'PM2_TEMPLATE'
{
  "annotations": { "list": [] },
  "editable": true,
  "description": "Template: Duplicate this dashboard and set process_name variable for each PM2 app",
  "fiscalYearStartMonth": 0,
  "graphTooltip": 1,
  "id": null,
  "links": [],
  "templating": {
    "list": [
      {
        "name": "process_name",
        "type": "textbox",
        "label": "⚙️ Process Name",
        "description": "Set to your PM2 process name (e.g., api-server, worker, scheduler)",
        "value": "api-server",
        "current": { "text": "api-server", "value": "api-server" },
        "hide": 0
      }
    ]
  },
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
                   "textMode": "auto" },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "100 * (sum(count_over_time({job=\"pm2\", name=\"${process_name}\"}[5m])) - sum(count_over_time({job=\"pm2\", name=\"${process_name}\"} |~ \"ERROR|Exception|WARN|WARNING\"[5m]))) / (sum(count_over_time({job=\"pm2\", name=\"${process_name}\"}[5m])) + 1)",
          "legendFormat": "Success",
          "refId": "A" }
      ],
      "title": "✅ Success Rate — ${process_name}",
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
                   "textMode": "auto" },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "100 * sum(count_over_time({job=\"pm2\", name=\"${process_name}\"} |~ \"ERROR|Exception\" [5m])) / (sum(count_over_time({job=\"pm2\", name=\"${process_name}\"}[5m])) + 1)",
          "legendFormat": "Errors",
          "refId": "A" }
      ],
      "title": "❌ Error Rate — ${process_name}",
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
                   "textMode": "auto" },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "100 * sum(count_over_time({job=\"pm2\", name=\"${process_name}\"} |~ \"WARN|WARNING\" [5m])) / (sum(count_over_time({job=\"pm2\", name=\"${process_name}\"}[5m])) + 1)",
          "legendFormat": "Warnings",
          "refId": "A" }
      ],
      "title": "⚠️ Warning Rate — ${process_name}",
      "type": "gauge"
    },
    {
      "datasource": { "type": "loki", "uid": "Loki" },
      "fieldConfig": {
        "defaults": { "color": { "mode": "palette-classic" }, "unit": "short" },
        "overrides": []
      },
      "gridPos": { "h": 4, "w": 6, "x": 18, "y": 0 },
      "id": 4,
      "options": { "legend": { "calcs": ["sum"], "displayMode": "list", "placement": "bottom" },
                   "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false },
                   "tooltip": { "mode": "single" } },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "sum(count_over_time({job=\"pm2\", name=\"${process_name}\"}[5m]))",
          "legendFormat": "Total Logs",
          "refId": "A" }
      ],
      "title": "📊 Log Count (5m) — ${process_name}",
      "type": "stat"
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
      "options": { "legend": { "calcs": ["sum", "mean"], "displayMode": "table", "placement": "bottom" },
                   "tooltip": { "mode": "multi" } },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "sum(count_over_time({job=\"pm2\", name=\"${process_name}\"} |~ \"ERROR|Exception\" [5m]))",
          "legendFormat": "Error Count",
          "refId": "A" }
      ],
      "title": "❌ Error Trend — ${process_name}",
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
      "options": { "legend": { "calcs": ["sum", "mean"], "displayMode": "table", "placement": "bottom" },
                   "tooltip": { "mode": "multi" } },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "sum(count_over_time({job=\"pm2\", name=\"${process_name}\"} |~ \"WARN|WARNING\" [5m]))",
          "legendFormat": "Warning Count",
          "refId": "A" }
      ],
      "title": "⚠️ Warning Trend — ${process_name}",
      "type": "timeseries"
    },
    {
      "datasource": { "type": "loki", "uid": "Loki" },
      "fieldConfig": {
        "defaults": { "custom": { "showThresholdLabels": false, "showThresholdMarkers": true } },
        "overrides": []
      },
      "gridPos": { "h": 12, "w": 24, "x": 0, "y": 12 },
      "id": 7,
      "options": { "dedupStrategy": "none", "enableLogDetails": true, "prettifyLogMessage": true,
                   "showCommonLabels": true, "showLabels": true, "showTime": true,
                   "sortOrder": "Descending", "wrapLogMessage": true },
      "targets": [
        { "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "{job=\"pm2\", name=\"${process_name}\"}",
          "legendFormat": "",
          "refId": "A" }
      ],
      "title": "📋 Process Logs — ${process_name}",
      "type": "logs"
    }
  ],
  "refresh": "5s",
  "schemaVersion": 38,
  "tags": ["pm2", "process", "analytics", "template", "loki"],
  "time": { "from": "now-6h", "to": "now" },
  "timepicker": {},
  "timezone": "browser",
  "title": "🔍 Template — Per-Process Analytics",
  "uid": "pm2-template-per-process",
  "version": 1,
  "style": "dark"
}
PM2_TEMPLATE

chmod 644 "$TEMPLATE_PATH"
chown grafana:grafana "$TEMPLATE_PATH" 2>/dev/null || true

echo "✅ Template dashboard created: $TEMPLATE_PATH"

echo ""
echo "Restarting Grafana to pick up the new dashboards..."

# Restart Grafana to load the new dashboard provisioning
systemctl restart grafana-server 2>/dev/null || sudo systemctl restart grafana-server

sleep 3


echo "✅ Done! Your PM2 dashboards are ready."
echo ""
echo "📊 Open Grafana and navigate to Applications folder:"
echo ""
echo "   🔍 PM2 Per-Process Analytics"
echo "      → Aggregated metrics (all PM2 apps)"
echo "      → Success/Error/Warning rates across all processes"
echo "      → Per-process error/warning trends"
echo "      → Full logs viewer with process names"
echo ""
echo "   🔍 Template — Per-Process Analytics"
echo "      → Duplicate this dashboard for EACH PM2 app"
echo "      → Set 'process_name' variable to your app name"
echo "      → Get detailed per-process metrics"
echo "      → Examples:"
echo "         • Duplicate for 'api-server' → rename to '⚙️ api-server Analytics'"
echo "         • Duplicate for 'worker' → rename to '⚙️ worker Analytics'"
echo "         • Duplicate for 'scheduler' → rename to '⚙️ scheduler Analytics'"
echo ""
echo "ℹ️  To duplicate a dashboard in Grafana:"
echo "   • Open the template dashboard"
echo "   • Press 'D' then 'D' (keyboard shortcut)"
echo "   • OR: Use dashboard menu (⋮) → 'Make a copy'"
echo ""
echo "🚀 Start a PM2 app to see real data:"
echo "   pm2 start app.js --name 'my-app'"
echo "   pm2 save"
