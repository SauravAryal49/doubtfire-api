#!/usr/bin/env bash
# Tag the released commit and publish a GitHub Release.
# Needs GH_USER / GH_TOKEN (Jenkins "github-pat" credential), APP_VERSION, IMAGE_NAME.
set -euo pipefail

TAG="v${APP_VERSION}"
REPO_SLUG=$(git config --get remote.origin.url | sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##')

echo "==> Tagging ${REPO_SLUG} at $(git rev-parse --short HEAD) as ${TAG}"
git -c user.name="Jenkins" -c user.email="jenkins@localhost" \
  tag -a "$TAG" -m "OnTrack ${TAG} - Jenkins build ${BUILD_NUMBER}, image ${IMAGE_NAME}:${APP_VERSION}"
git push "https://${GH_USER}:${GH_TOKEN}@github.com/${REPO_SLUG}.git" "$TAG"

BODY=$(cat <<EOF
Released automatically by Jenkins build [#${BUILD_NUMBER}](${BUILD_URL}).

- Docker image: \`${IMAGE_NAME}:${APP_VERSION}\` (also tagged \`prod\`)
- Commit: ${GIT_COMMIT}
- Passed: unit + integration tests, SonarQube quality gate, security gate, staging CRUD tests, production smoke tests
EOF
)

echo "==> Creating GitHub Release ${TAG}"
jq -n --arg tag "$TAG" --arg body "$BODY" \
  '{tag_name: $tag, name: ("OnTrack " + $tag), body: $body, generate_release_notes: true}' \
| curl -fsS -X POST \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO_SLUG}/releases" \
    -d @- | jq -r '.html_url' | tee reports/release-url.txt
