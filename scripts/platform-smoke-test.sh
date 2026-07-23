#!/usr/bin/env bash
set -Eeuo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
USERNAME="${GATEWAY_ADMIN_USERNAME:-admin}"
PASSWORD="${GATEWAY_ADMIN_PASSWORD:-change-this-password}"

json_field() {
  python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"
}

for _ in $(seq 1 60); do
  curl -fsS "$BASE_URL/health/live" >/dev/null 2>&1 && break
  sleep 2
done

LOGIN="$(curl -fsS -X POST "$BASE_URL/auth/login" \
  -H 'content-type: application/json' \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")"
TOKEN="$(printf '%s' "$LOGIN" | json_field access_token)"
AUTH=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

echo "Creating low-stock inventory..."
curl -fsS -X POST "$BASE_URL/api/v1/inventory" "${AUTH[@]}" \
  -d '{"name":"Nokia 100G SFP","category":"optic","quantity":2,"low_stock_threshold":5,"location":"Cairo Warehouse"}'
printf '\n'

echo "Creating mock workflow..."
WORKFLOW="$(curl -fsS -X POST "$BASE_URL/api/v1/workflows" "${AUTH[@]}" \
  -d '{"name":"Backup Cairo Router","action":"backup_config","parameters":{"destination":"gcs","format":"md-cli"}}')"
WORKFLOW_ID="$(printf '%s' "$WORKFLOW" | json_field id)"
printf '%s\n' "$WORKFLOW"

echo "Queuing workflow $WORKFLOW_ID..."
curl -fsS -X POST "$BASE_URL/api/v1/workflows/$WORKFLOW_ID/run" "${AUTH[@]}"
printf '\n'
sleep 4

echo "Workflow result:"
curl -fsS "$BASE_URL/api/v1/workflows/$WORKFLOW_ID" "${AUTH[@]}"
printf '\n\nNotifications:\n'
curl -fsS "$BASE_URL/api/v1/notifications" "${AUTH[@]}"
printf '\n\nAudit events:\n'
curl -fsS "$BASE_URL/api/v1/audit" "${AUTH[@]}"
printf '\n'
