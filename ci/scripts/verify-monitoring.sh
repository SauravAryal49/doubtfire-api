#!/usr/bin/env bash
# Verify the monitoring stack is really watching production, then mark the
# deployment on the Grafana dashboard. Needs GF_ADMIN_PASSWORD, APP_VERSION.
set -euo pipefail
PROM=http://prometheus:9090
GRAFANA=http://grafana:3000
mkdir -p reports/monitoring

echo "==> Reloading Prometheus rules"
curl -fsS -X POST "$PROM/-/reload" || true

echo "==> Waiting for scrape targets to be UP"
for i in $(seq 1 24); do
  curl -fsS "$PROM/api/v1/targets" > reports/monitoring/targets.json
  DOWN=$(jq -r '[.data.activeTargets[] | select(.health != "up") | .labels.job + " " + (.labels.instance // "")] | .[]' reports/monitoring/targets.json)
  TOTAL=$(jq '.data.activeTargets | length' reports/monitoring/targets.json)
  if [ -z "$DOWN" ] && [ "$TOTAL" -gt 0 ]; then
    echo "    all ${TOTAL} targets up"
    break
  fi
  [ "$i" -eq 24 ] && { echo "!! targets still down:"; echo "$DOWN"; exit 1; }
  sleep 5
done
jq -r '.data.activeTargets[] | "    \(.labels.job)\t\(.labels.instance)\t\(.health)"' reports/monitoring/targets.json

echo "==> Alert rules loaded"
curl -fsS "$PROM/api/v1/rules" | tee reports/monitoring/rules.json \
  | jq -r '.data.groups[] | .name as $g | .rules[] | "    [\($g)] \(.name): \(.state)"'

echo "==> Live production metrics"
q() { curl -fsS --get "$PROM/api/v1/query" --data-urlencode "query=$1" | jq -r '.data.result[0].value[1] // "n/a"'; }
echo "    up:              $(q 'probe_success{env="production"}')"
echo "    response time s: $(q 'probe_duration_seconds{env="production"}')"
echo "    requests/s:      $(q 'sum(rate(nginx_http_requests_total[1m]))')"

FIRING=$(curl -fsS "$PROM/api/v1/alerts" | jq -r '[.data.alerts[] | select(.state=="firing") | .labels.alertname] | join(", ")')
echo "    firing alerts:   ${FIRING:-none}"
if echo "$FIRING" | grep -q "OnTrackDown"; then
  echo "!! Production is DOWN right after release"
  exit 1
fi

echo "==> Adding deployment annotation to Grafana"
jq -n --arg t "Deployed OnTrack v${APP_VERSION} (Jenkins #${BUILD_NUMBER})" \
  '{tags: ["deploy", "ontrack"], text: $t}' \
| curl -fsS -u "admin:${GF_ADMIN_PASSWORD}" -H "Content-Type: application/json" \
    -X POST "$GRAFANA/api/annotations" -d @- || echo "   (annotation failed - Grafana still starting?)"
echo
echo "Dashboard: http://localhost:3000/d/ontrack-overview"
