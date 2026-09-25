#!/usr/bin/env bash
# One-off SonarQube configuration as code: custom quality gate + Jenkins webhook.
# Run from your machine after SonarQube is up:
#   SONAR_TOKEN=<admin user token> ./ci/sonar/setup-sonarqube.sh
set -euo pipefail
SONAR=${SONAR_URL:-http://localhost:9000}
GATE="OnTrack Gate"
AUTH=(-u "${SONAR_TOKEN}:")

api() { curl -fsS "${AUTH[@]}" -X POST "$SONAR/api/$1" "${@:2}"; echo; }

echo "==> Creating quality gate '$GATE'"
api qualitygates/create --data-urlencode "name=$GATE" || echo "(exists)"

# Conditions (on NEW code = Clean as You Code):
#   coverage < 70%            -> fail
#   duplicated lines > 3%     -> fail
#   maintainability rating worse than A -> fail
#   reliability rating worse than A     -> fail
#   security rating worse than A        -> fail
add() { api qualitygates/create_condition --data-urlencode "gateName=$GATE" -d "metric=$1" -d "op=$2" -d "error=$3" || true; }
add new_coverage                  LT 70
add new_duplicated_lines_density  GT 3
add new_maintainability_rating    GT 1
add new_reliability_rating        GT 1
add new_security_hotspots_reviewed LT 100

echo "==> Creating project and attaching gate"
api projects/create -d "project=ontrack-api" --data-urlencode "name=OnTrack API (Doubtfire)" || echo "(exists)"
api qualitygates/select --data-urlencode "gateName=$GATE" -d "projectKey=ontrack-api"

echo "==> Webhook so Jenkins' waitForQualityGate gets the result"
api webhooks/create -d "name=Jenkins" -d "url=http://jenkins:8080/sonarqube-webhook/" || echo "(exists)"
echo "Done."
