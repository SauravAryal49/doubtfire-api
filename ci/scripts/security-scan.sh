#!/usr/bin/env bash
# Security stage: SAST (Brakeman), dependency + OS CVEs (Trivy image),
# IaC misconfiguration (Trivy config) and secrets (Gitleaks).
#
# Reports -> reports/security/. Gate (when SECURITY_GATE=true):
#   * any High-confidence Brakeman warning not in config/brakeman.ignore
#   * any CRITICAL CVE with a fix available not in .trivyignore
#   * any secret not in .gitleaksignore
set -uo pipefail

IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
OUT=reports/security
TRIVY_CACHE="${JENKINS_HOME:-$HOME}/.cache/trivy"
mkdir -p "$OUT"
FAIL=0

echo "==> [1/4] Brakeman (Rails static analysis) inside the built image"
docker run --rm --entrypoint "" "$IMAGE" bash -c \
  "gem install brakeman --no-document -q >/dev/null 2>&1 && brakeman -q --no-pager --no-exit-on-warn --no-exit-on-error -f json" \
  > "$OUT/brakeman.json"
BRAKEMAN_HIGH=$(jq '[.warnings[] | select(.confidence == "High")] | length' "$OUT/brakeman.json")
BRAKEMAN_ALL=$(jq '.warnings | length' "$OUT/brakeman.json")
echo "    Brakeman: ${BRAKEMAN_ALL} warnings, ${BRAKEMAN_HIGH} high confidence"
[ "$BRAKEMAN_HIGH" -gt 0 ] && { echo "!! Brakeman gate failed"; FAIL=1; }

echo "==> [2/4] Trivy image scan (OS packages + Ruby gems)"
trivy image --cache-dir "$TRIVY_CACHE" --timeout 20m --scanners vuln \
  --format json -o "$OUT/trivy-image.json" "$IMAGE"
trivy image --cache-dir "$TRIVY_CACHE" --skip-db-update --scanners vuln \
  --severity HIGH,CRITICAL --format table -o "$OUT/trivy-image.txt" "$IMAGE"
jq -r '[.Results[]?.Vulnerabilities[]?] | group_by(.Severity)
       | map("\(.[0].Severity): \(length)") | .[]' "$OUT/trivy-image.json" | tee "$OUT/trivy-severity-counts.txt"
echo "    Gate check: CRITICAL with a fix available, not in .trivyignore:"
if ! trivy image --cache-dir "$TRIVY_CACHE" --skip-db-update --scanners vuln -q \
      --severity CRITICAL --ignore-unfixed --ignorefile .trivyignore --exit-code 1 \
      --format table "$IMAGE" | tee "$OUT/trivy-gate.txt"; then
  echo "!! Trivy gate failed: fixable CRITICAL vulnerabilities (see trivy-image.txt)"
  FAIL=1
fi

echo "==> [3/4] Trivy config scan (Dockerfiles, compose)"
trivy config --cache-dir "$TRIVY_CACHE" --format json -o "$OUT/trivy-config.json" . || true
trivy config --cache-dir "$TRIVY_CACHE" --severity HIGH,CRITICAL -o "$OUT/trivy-config.txt" . || true

echo "==> [4/4] Gitleaks (secrets in code and git history)"
gitleaks detect --source . --redact --no-banner \
  --report-format sarif --report-path "$OUT/gitleaks.sarif" --exit-code 0
if ! gitleaks detect --source . --redact --no-banner --exit-code 1 > "$OUT/gitleaks.txt" 2>&1; then
  echo "!! Gitleaks gate failed: untriaged secrets (see gitleaks.txt / .gitleaksignore)"
  FAIL=1
fi

{
  echo "# Security summary - build ${BUILD_NUMBER} (${IMAGE})"
  echo "Brakeman warnings: ${BRAKEMAN_ALL} (high confidence: ${BRAKEMAN_HIGH})"
  echo "Trivy image findings by severity:"; cat "$OUT/trivy-severity-counts.txt"
  echo "Gitleaks findings: $(jq '[.runs[].results[]] | length' "$OUT/gitleaks.sarif")"
} | tee "$OUT/summary.txt"

if [ "${SECURITY_GATE:-true}" = "true" ] && [ "$FAIL" -ne 0 ]; then
  echo "!! Security gate FAILED"
  exit 1
fi
echo "==> Security stage complete (gate: ${SECURITY_GATE:-true})"
