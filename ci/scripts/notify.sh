#!/usr/bin/env bash
# Post a pipeline status message to Discord. usage: notify.sh <status>
# Needs DISCORD_WEBHOOK_URL (Jenkins "discord-webhook" secret text).
set -euo pipefail
STATUS="$1"
case "$STATUS" in
  SUCCESS) COLOR=3066993 ;;
  FAILURE) COLOR=15158332 ;;
  *)       COLOR=15844367 ;;
esac
jq -n --arg title "OnTrack pipeline ${STATUS}: ${JOB_NAME} #${BUILD_NUMBER}" \
      --arg url "$BUILD_URL" \
      --arg desc "Version ${APP_VERSION:-?} | branch ${BRANCH_NAME:-?} | commit ${GIT_COMMIT:0:7}" \
      --argjson color "$COLOR" \
  '{embeds: [{title: $title, url: $url, description: $desc, color: $color}]}' \
| curl -fsS -H "Content-Type: application/json" -d @- "$DISCORD_WEBHOOK_URL" || echo "notification failed (ignored)"
