#!/usr/bin/env bash
# Merge the unit + integration SimpleCov results into one report
# (HTML, Cobertura XML for Jenkins, .resultset.json for SonarQube).
set -euo pipefail

IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
NAME="ontrack-coverage-${BUILD_NUMBER}"
rm -rf reports/coverage && mkdir -p reports/coverage

CID=$(docker create --name "$NAME" -e CI=true --entrypoint "" "$IMAGE" \
      bundle exec ruby ci/scripts/collate_coverage.rb)
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT

for suite in unit integration; do
  f="reports/$suite/coverage/.resultset.json"
  if [ -f "$f" ]; then
    docker cp "$f" "$CID:/tmp/$suite.resultset.json"
  fi
done

docker start -a "$CID"
docker cp "$CID:/doubtfire/coverage/." reports/coverage

# Paths inside the image are /doubtfire/...; rewrite them to the Jenkins
# workspace so SonarQube and the Coverage plugin can match source files.
sed -i "s#/doubtfire/#${WORKSPACE}/#g" reports/coverage/.resultset.json reports/coverage/coverage.xml
sed -i "s#<source>/doubtfire</source>#<source>${WORKSPACE}</source>#g" reports/coverage/coverage.xml
echo "Merged coverage written to reports/coverage"
