#!/usr/bin/env bash
# Incident simulation for the demo: trigger a real alert, wait for it to fire,
# recover, and wait for it to resolve.
#
# usage: simulate-incident.sh <outage|load|cpu>
set -euo pipefail
KIND="$1"
PROM=http://prometheus:9090
API=ontrack-production-api-1

alert_state() {  # prints firing / pending / inactive
  curl -fsS "$PROM/api/v1/alerts" \
    | jq -r --arg a "$1" '[.data.alerts[] | select(.labels.alertname==$a) | .state] | if length==0 then "inactive" else (if index("firing") then "firing" else "pending" end) end'
}

wait_for() {  # wait_for <alert> <state> <timeout-seconds>
  local alert=$1 want=$2 limit=$3 waited=0
  echo "    waiting for ${alert} -> ${want} (max ${limit}s)"
  while [ "$(alert_state "$alert")" != "$want" ]; do
    sleep 10; waited=$((waited + 10))
    echo "      ${waited}s: ${alert} is $(alert_state "$alert")"
    [ "$waited" -ge "$limit" ] && { echo "!! timed out"; return 1; }
  done
  echo "    ${alert} is ${want} after ${waited}s"
}

case "$KIND" in
  outage)
    echo "==> INCIDENT: stopping production API container"
    docker stop "$API"
    wait_for OnTrackDown firing 240
    echo "==> RECOVERY: starting API again"
    docker start "$API"
    wait_for OnTrackDown inactive 480
    ;;
  load)
    echo "==> INCIDENT: flooding production with requests (simulated DDoS, 3 min)"
    docker run -d --rm --name ontrack-load --network ontrack-shared httpd:2.4-alpine \
      ab -t 180 -n 10000000 -c 60 -s 10 http://ontrack-production/api/settings
    wait_for PossibleDDoS firing 180
    echo "==> nginx rate limiting (HTTP 429) during attack:"
    docker logs --tail 5 ontrack-production-nginx-1 2>&1 | grep -c ' 429 ' || true
    docker stop ontrack-load >/dev/null 2>&1 || true
    wait_for PossibleDDoS inactive 300
    ;;
  cpu)
    echo "==> INCIDENT: burning CPU inside the API container for 4 minutes"
    docker exec -d "$API" bash -c 'for i in 1 2; do timeout 240 sh -c "while :; do :; done" & done; wait'
    wait_for ContainerHighCPU firing 240
    wait_for ContainerHighCPU inactive 360
    ;;
  *)
    echo "unknown incident: $KIND (use outage|load|cpu)"; exit 2 ;;
esac
echo "==> Incident '${KIND}' simulated: alert fired, notification sent, service recovered."
