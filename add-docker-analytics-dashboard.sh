#!/bin/bash
# [LEGACY] Add Docker Per-Container Log Analytics Dashboard to existing Grafana installation
# NOTE: The default production stack now uses Cockpit (:9090) and VictoriaMetrics (:8428).
# This script is retained for backward compatibility with legacy Grafana deployments.

set -euo pipefail

if ! command -v grafana-server &>/dev/null && [[ ! -d "/var/lib/grafana" ]]; then
    echo "Notice: Grafana is not installed on this server."
    echo "The production server monitoring architecture uses Cockpit (:9090) and VictoriaMetrics (:8428)."
    echo "This script is retained for legacy Grafana deployments only."
    exit 0
fi

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

# ─────────────────────────────────────────────────────────────────────────────
# Create Per-Container Template Dashboard
# ─────────────────────────────────────────────────────────────────────────────

TEMPLATE_PATH="/var/lib/grafana/dashboards/docker/05-template-per-container-analytics.json"

echo ""
echo "Creating per-container template dashboard..."

cat > "$TEMPLATE_PATH" <<'CONTAINER_TEMPLATE'
{
  "annotations": { "list": [] },
  "editable": true,
  "description": "Template: Duplicate this dashboard and set container_name variable for each container",
  "fiscalYearStartMonth": 0,
  "graphTooltip": 1,
  "id": null,
  "links": [],
  "templating": {
    "list": [
      {
        "name": "container_name",
        "type": "textbox",
        "label": "📦 Container Name",
        "description": "Set to your Docker container name (e.g., nginx, postgres, redis)",
        "value": "nginx",
        "current": { "text": "nginx", "value": "nginx" },
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
          "expr": "100 * (sum(count_over_time({container_name=\"${container_name}\"}[5m])) - sum(count_over_time({container_name=\"${container_name}\"} |~ \"ERROR|Exception|WARN|WARNING\"[5m]))) / (sum(count_over_time({container_name=\"${container_name}\"}[5m])) + 1)",
          "legendFormat": "Success",
          "refId": "A" }
      ],
      "title": "✅ Success Rate — ${container_name}",
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
          "expr": "100 * sum(count_over_time({container_name=\"${container_name}\"} |~ \"ERROR|Exception\" [5m])) / (sum(count_over_time({container_name=\"${container_name}\"}[5m])) + 1)",
          "legendFormat": "Errors",
          "refId": "A" }
      ],
      "title": "❌ Error Rate — ${container_name}",
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
          "expr": "100 * sum(count_over_time({container_name=\"${container_name}\"} |~ \"WARN|WARNING\" [5m])) / (sum(count_over_time({container_name=\"${container_name}\"}[5m])) + 1)",
          "legendFormat": "Warnings",
          "refId": "A" }
      ],
      "title": "⚠️ Warning Rate — ${container_name}",
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
          "expr": "sum(count_over_time({container_name=\"${container_name}\"}[5m]))",
          "legendFormat": "Total Logs",
          "refId": "A" }
      ],
      "title": "📊 Log Count (5m) — ${container_name}",
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
          "expr": "sum(count_over_time({container_name=\"${container_name}\"} |~ \"ERROR|Exception\" [5m]))",
          "legendFormat": "Error Count",
          "refId": "A" }
      ],
      "title": "❌ Error Trend — ${container_name}",
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
          "expr": "sum(count_over_time({container_name=\"${container_name}\"} |~ \"WARN|WARNING\" [5m]))",
          "legendFormat": "Warning Count",
          "refId": "A" }
      ],
      "title": "⚠️ Warning Trend — ${container_name}",
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
          "expr": "{container_name=\"${container_name}\"}",
          "legendFormat": "",
          "refId": "A" }
      ],
      "title": "📋 Container Logs — ${container_name}",
      "type": "logs"
    }
  ],
  "refresh": "5s",
  "schemaVersion": 38,
  "tags": ["docker", "container", "analytics", "template", "loki"],
  "time": { "from": "now-6h", "to": "now" },
  "timepicker": {},
  "timezone": "browser",
  "title": "🐳 Template — Per-Container Analytics",
  "uid": "docker-template-per-container",
  "version": 1,
  "style": "dark"
}
CONTAINER_TEMPLATE

chmod 644 "$TEMPLATE_PATH"
chown grafana:grafana "$TEMPLATE_PATH" 2>/dev/null || true

echo "✅ Template dashboard created: $TEMPLATE_PATH"

echo ""
echo "Restarting Grafana to pick up the new dashboards..."

# Restart Grafana to load the new dashboard provisioning
systemctl restart grafana-server 2>/dev/null || sudo systemctl restart grafana-server

sleep 3


echo "✅ Done! Your Docker dashboards are ready."
echo ""
echo "📊 Open Grafana and navigate to Docker folder:"
echo ""
echo "   🐳 Docker Per-Container Log Analytics"
echo "      → Aggregated metrics (all containers)"
echo "      → Success/Error/Warning rates across all containers"
echo "      → Per-container error/warning trends"
echo "      → Full logs viewer with container labels"
echo ""
echo "   🐳 Template — Per-Container Analytics"
echo "      → Duplicate this dashboard for EACH container"
echo "      → Set 'container_name' variable to your container name"
echo "      → Get detailed per-container metrics"
echo "      → Examples:"
echo "         • Duplicate for 'nginx' → rename to '📦 nginx Analytics'"
echo "         • Duplicate for 'postgres' → rename to '📦 postgres Analytics'"
echo "         • Duplicate for 'redis' → rename to '📦 redis Analytics'"
echo ""
echo "ℹ️  To duplicate a dashboard in Grafana:"
echo "   • Open the template dashboard"
echo "   • Press 'D' then 'D' (keyboard shortcut)"
echo "   • OR: Use dashboard menu (⋮) → 'Make a copy'"
echo ""
