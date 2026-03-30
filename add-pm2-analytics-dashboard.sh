#!/bin/bash
# Add PM2 Per-Process Analytics Dashboard to existing Grafana installation
# Run this on your production server to add the new dashboard without rerunning init.sh

set -euo pipefail

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
echo ""
echo "Restarting Grafana to pick up the new dashboard..."

# Restart Grafana to load the new dashboard provisioning
systemctl restart grafana-server 2>/dev/null || sudo systemctl restart grafana-server

sleep 3

echo "✅ Done! Your new dashboard is ready."
echo ""
echo "📊 Open Grafana and navigate to:"
echo "   Applications → 🔍 PM2 Per-Process Analytics"
echo ""
echo "🚀 Start a PM2 app to see real data:"
echo "   pm2 start app.js --name 'my-app'"
echo "   pm2 save"
