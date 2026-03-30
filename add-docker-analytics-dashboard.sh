#!/bin/bash
# Add Docker Per-Container Log Analytics Dashboard to existing Grafana installation
# Run this on your production server to add the new dashboard without rerunning docker.sh

set -euo pipefail

DASHBOARD_PATH="/var/lib/grafana/dashboards/docker/04-docker-per-container-analytics.json"

echo "Adding Docker Per-Container Log Analytics Dashboard to Grafana..."

# Create directory if it doesn't exist
mkdir -p "$(dirname "$DASHBOARD_PATH")"

# Create the dashboard file
cat > "$DASHBOARD_PATH" <<'DOCKER_ANALYTICS'
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
echo "   Applications → 🐳 Docker Per-Container Log Analytics"
echo ""
echo "📝 The dashboard shows:"
echo "   • Success/Error/Warning rates across all containers"
echo "   • Per-container error and warning trends"
echo "   • Detailed logs with container labels"
echo ""
