#!/usr/bin/env bash
# Run one OnTrack test suite inside the image built by this pipeline, against
# its own throwaway MariaDB + Redis, then copy JUnit + coverage reports out.
#
# usage: run-tests.sh <suite-name> "<test paths>"
#   e.g. run-tests.sh unit "test/models test/mailers"
set -euo pipefail

SUITE="$1"
PATHS="$2"
IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
PROJECT="ontrack-test-${SUITE}-${BUILD_NUMBER}"
RUNNER="${PROJECT}-runner"
COMPOSE=(docker compose -p "$PROJECT" -f ci/compose/test.yml)
export IMAGE

cleanup() {
  docker rm -f "$RUNNER" >/dev/null 2>&1 || true
  "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> [$SUITE] starting MariaDB + Redis"
"${COMPOSE[@]}" up -d --wait mariadb redis

echo "==> [$SUITE] seeding test DB and running: rails test $PATHS"
set +e
"${COMPOSE[@]}" run -T --name "$RUNNER" -e TEST_SUITE="$SUITE" tests \
  bash -c "bundle exec rake db:populate && TERM=xterm bundle exec rails test $PATHS"
STATUS=$?
set -e

echo "==> [$SUITE] collecting reports"
mkdir -p "reports/$SUITE"
docker cp "$RUNNER:/doubtfire/test-reports/." "reports/$SUITE/junit"    || echo "no junit reports"
docker cp "$RUNNER:/doubtfire/coverage/."     "reports/$SUITE/coverage" || echo "no coverage"

echo "==> [$SUITE] finished with exit code $STATUS"
exit $STATUS
