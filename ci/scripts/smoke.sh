#!/usr/bin/env bash
# Post-deployment verification through nginx, from the Jenkins container
# (Jenkins shares the "ontrack-shared" network with each stack's nginx).
#
# usage: smoke.sh <staging|production> <newman folder: Smoke|CRUD|all>
set -euo pipefail

ENV_NAME="$1"
FOLDER="${2:-Smoke}"
BASE_URL="http://ontrack-${ENV_NAME}"
mkdir -p reports

echo "==> Waiting for ${BASE_URL}/api/settings"
for i in $(seq 1 30); do
  if curl -fsS -o /dev/null "${BASE_URL}/api/settings"; then
    echo "    healthy after $((i * 5))s"
    break
  fi
  [ "$i" -eq 30 ] && { echo "!! ${ENV_NAME} did not become healthy"; exit 1; }
  sleep 5
done

echo "==> Newman: folder '${FOLDER}' against ${BASE_URL}"
FOLDER_ARGS=()
[ "$FOLDER" != "all" ] && FOLDER_ARGS=(--folder "$FOLDER")

newman run ci/newman/ontrack.postman_collection.json \
  "${FOLDER_ARGS[@]}" \
  --env-var "baseUrl=${BASE_URL}" \
  --env-var "username=${ONTRACK_TEST_USER:-aadmin}" \
  --env-var "password=${ONTRACK_TEST_PASSWORD:-password}" \
  --reporters cli,junit \
  --reporter-junit-export "reports/newman-${ENV_NAME}.xml"
