#!/usr/bin/env bash
set -Eeuo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"

check() {
  local path="$1"
  local description="$2"
  if curl -fsS "$BASE_URL$path" >/dev/null; then
    printf 'PASS  %s\n' "$description"
  else
    printf 'FAIL  %s (%s%s)\n' "$description" "$BASE_URL" "$path" >&2
    exit 1
  fi
}

check "/frontend-health" "Frontend Nginx health endpoint"
check "/" "Single-page application"
check "/health/live" "API Gateway proxy"
printf '\nFRONTEND SMOKE TEST: PASSED\n'
