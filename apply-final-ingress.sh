#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================================
# MULTICLOUD Telecom Platform — Final Ingress
#
# Routes through ONE Google Cloud Load Balancer:
#   /                 -> frontend
#   /frontend-health  -> frontend
#   /auth/*           -> api-gateway
#   /api/*            -> api-gateway
#   /health/*         -> api-gateway
# ============================================================================

NAMESPACE="${NAMESPACE:-telecom-platform}"
INGRESS_NAME="${INGRESS_NAME:-telecom-ingress}"
WAIT_SECONDS="${WAIT_SECONDS:-900}"

log()  { printf '\033[1;34m[ingress]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

find_repo_root() {
  local current="$PWD"
  while [[ "$current" != "/" ]]; do
    if [[ -d "$current/services" ]] && [[ -d "$current/k8s" ]]; then
      printf '%s\n' "$current"
      return 0
    fi
    current="$(dirname "$current")"
  done
  return 1
}

ROOT="$(find_repo_root || true)"
[[ -n "${ROOT:-}" ]] || die "Run from devops-portfolio or one of its subdirectories."
cd "$ROOT"

command -v kubectl >/dev/null 2>&1 || die "kubectl is required."

kubectl -n "$NAMESPACE" get svc frontend >/dev/null 2>&1 \
  || die "frontend Service was not found. Run the adjusted frontend bootstrap first."
kubectl -n "$NAMESPACE" get svc api-gateway >/dev/null 2>&1 \
  || die "api-gateway Service was not found."

mkdir -p "$ROOT/k8s/ingress"

cat > "$ROOT/k8s/ingress/ingress.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $INGRESS_NAME
  namespace: $NAMESPACE
  annotations:
    kubernetes.io/ingress.class: "gce"
spec:
  defaultBackend:
    service:
      name: frontend
      port:
        number: 80
  rules:
    - http:
        paths:
          - path: /auth
            pathType: Prefix
            backend:
              service:
                name: api-gateway
                port:
                  number: 80
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api-gateway
                port:
                  number: 80
          - path: /health
            pathType: Prefix
            backend:
              service:
                name: api-gateway
                port:
                  number: 80
          - path: /frontend-health
            pathType: Exact
            backend:
              service:
                name: frontend
                port:
                  number: 80
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend
                port:
                  number: 80
EOF

log "Applying final Ingress routing"
kubectl apply -f "$ROOT/k8s/ingress/ingress.yaml"

start="$(date +%s)"
address=""
while true; do
  address="$(kubectl -n "$NAMESPACE" get ingress "$INGRESS_NAME" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"

  backends="$(kubectl -n "$NAMESPACE" get ingress "$INGRESS_NAME" \
    -o jsonpath='{.metadata.annotations.ingress\.kubernetes\.io/backends}' \
    2>/dev/null || true)"

  [[ -n "$address" ]] && printf 'External IP: %s | Backends: %s\n' "$address" "${backends:-reconciling}"

  healthy_count="$(printf '%s' "$backends" | grep -o '"HEALTHY"' | wc -l | tr -d ' ' || true)"
  if [[ -n "$address" ]] \
     && [[ "$healthy_count" -ge 2 ]] \
     && [[ "$backends" != *'"UNHEALTHY"'* ]]; then
    break
  fi

  now="$(date +%s)"
  if (( now - start >= WAIT_SECONDS )); then
    warn "Timed out waiting for healthy backends."
    kubectl -n "$NAMESPACE" describe ingress "$INGRESS_NAME" || true
    exit 1
  fi

  sleep 10
done

ok "Ingress has an external IP and at least one healthy backend."
kubectl -n "$NAMESPACE" describe ingress "$INGRESS_NAME"

if command -v curl >/dev/null 2>&1; then
  log "Testing frontend health"
  curl -fsS "http://$address/frontend-health"
  echo

  log "Testing API Gateway through the same Load Balancer"
  curl -fsS "http://$address/health/live"
  echo

  log "Testing the React entry page"
  curl -fsSI "http://$address/" | head
fi

cat <<SUMMARY

==============================================================================
FINAL INGRESS COMPLETE
==============================================================================

Open:
  http://$address

Routing:
  /                 -> frontend
  /frontend-health  -> frontend
  /auth/*           -> api-gateway
  /api/*            -> api-gateway
  /health/*         -> api-gateway

This keeps:
  - One public IP
  - One Google Cloud Load Balancer
  - Private internal microservices
  - Same-origin browser requests without CORS configuration
==============================================================================
SUMMARY

