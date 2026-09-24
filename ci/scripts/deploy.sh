#!/usr/bin/env bash
# Deploy (or roll back) an OnTrack environment with Docker Compose.
#
# usage:
#   deploy.sh <staging|production> <image>     deploy that image
#   deploy.sh <staging|production> --rollback  redeploy the previous image
#
# Needs SECRETS_FILE (Jenkins "Secret file" credential) in the environment.
set -euo pipefail

ENV_NAME="$1"
TARGET="$2"
PROJECT="ontrack-${ENV_NAME}"
STATE_DIR="${JENKINS_HOME:-$HOME}/ontrack-deploy-state"
PREV_FILE="${STATE_DIR}/${ENV_NAME}.previous"
CURR_FILE="${STATE_DIR}/${ENV_NAME}.current"
mkdir -p "$STATE_DIR" reports

: "${SECRETS_FILE:?SECRETS_FILE must be set (withCredentials file binding)}"

compose() {
  docker compose -p "$PROJECT" -f ci/compose/app.yml \
    --env-file "ci/env/${ENV_NAME}.env" --env-file "$SECRETS_FILE" "$@"
}

if [ "$TARGET" = "--rollback" ]; then
  if [ ! -s "$PREV_FILE" ]; then
    echo "!! No previous ${ENV_NAME} release recorded - nothing to roll back to."
    exit 1
  fi
  IMAGE="$(cat "$PREV_FILE")"
  echo "==> ROLLBACK ${ENV_NAME} to ${IMAGE}"
else
  IMAGE="$TARGET"
  # Remember what is running now so we can roll back to it
  if [ -s "$CURR_FILE" ]; then
    cp "$CURR_FILE" "$PREV_FILE"
  fi
  echo "==> DEPLOY ${ENV_NAME}: ${IMAGE} (previous: $(cat "$PREV_FILE" 2>/dev/null || echo none))"
fi

export ENV_NAME IMAGE SECRETS_FILE

echo "==> Validating compose configuration (infrastructure as code)"
compose config --quiet

echo "==> Applying stack"
compose up -d --build --remove-orphans --wait --wait-timeout 420

echo "==> Infrastructure checks"
compose ps
UNHEALTHY=$(compose ps --format '{{.Service}} {{.Health}}' | awk '$2!="" && $2!="healthy"{print $1}')
if [ -n "$UNHEALTHY" ]; then
  echo "!! Unhealthy services: $UNHEALTHY"
  compose logs --tail 80 api || true
  exit 1
fi
compose exec -T db healthcheck.sh --connect --innodb_initialized
compose exec -T redis redis-cli ping

echo "$IMAGE" > "$CURR_FILE"
echo "$IMAGE" > "reports/${ENV_NAME}-deployed-image.txt"
echo "==> ${ENV_NAME} is running ${IMAGE}"
