#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================================
# MULTICLOUD Telecom Platform — Backend/Kubernetes Finalizer
#
# Run from the devops-portfolio repository root:
#   chmod +x 01-finalize-backend-k8s.sh
#   ./01-finalize-backend-k8s.sh
#
# Useful overrides:
#   IMAGE_TAG=phase3-complete ./01-finalize-backend-k8s.sh
#   ROTATE_GATEWAY_AUTH=1 ./01-finalize-backend-k8s.sh
#   GET_CREDENTIALS=0 ./01-finalize-backend-k8s.sh
#   APPLY=0 ./01-finalize-backend-k8s.sh
#
# What it does:
#   - Removes database/RabbitMQ URLs from Deployment YAML files.
#   - Creates platform-runtime-urls from the existing platform-secret.
#   - Creates or rotates API Gateway admin/JWT credentials securely.
#   - Rewrites all backend Deployments and Services consistently.
#   - Adds workflow worker, notification consumer, and audit consumer.
#   - Adds API Gateway BackendConfig + NEG configuration.
#   - Applies and validates the backend on GKE.
# ============================================================================

PROJECT_ID="${PROJECT_ID:-devops-project-503113}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
GKE_CLUSTER="${GKE_CLUSTER:-dev-gke}"
NAMESPACE="${NAMESPACE:-telecom-platform}"
AR_REPOSITORY="${AR_REPOSITORY:-dev-docker}"
IMAGE_TAG="${IMAGE_TAG:-phase3-complete}"
GET_CREDENTIALS="${GET_CREDENTIALS:-1}"
APPLY="${APPLY:-1}"
ROTATE_GATEWAY_AUTH="${ROTATE_GATEWAY_AUTH:-0}"
EXECUTION_MODE="${EXECUTION_MODE:-mock}"

REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPOSITORY}"
STAMP="$(date +%Y%m%d-%H%M%S)"

log()  { printf '\033[1;34m[backend]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "Required command is missing: $1"
}

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
[[ -n "${ROOT:-}" ]] || die "Run this script from devops-portfolio or one of its subdirectories."
cd "$ROOT"

BACKUP_ROOT="$ROOT/.k8s-finalizer-backups/$STAMP"
mkdir -p "$BACKUP_ROOT"

backup_dir() {
  local relative="$1"
  local source="$ROOT/$relative"
  [[ -e "$source" ]] || return 0
  mkdir -p "$BACKUP_ROOT/$(dirname "$relative")"
  cp -a "$source" "$BACKUP_ROOT/$relative"
  log "Backed up $relative"
}

write_file() {
  local target="$1"
  mkdir -p "$(dirname "$target")"
  cat > "$target"
  log "Wrote ${target#"$ROOT/"}"
}

for path in \
  k8s/apps/device-service \
  k8s/apps/inventory-service \
  k8s/apps/workflow-service \
  k8s/apps/notification-service \
  k8s/apps/audit-service \
  k8s/apps/api-gateway \
  k8s/apps/background-workers \
  k8s/ingress/api-gateway-backend-config.yaml
do
  backup_dir "$path"
done

need kubectl
need base64
need python3
need openssl

if [[ "$GET_CREDENTIALS" == "1" ]]; then
  need gcloud
  log "Loading credentials for $GKE_CLUSTER in $ZONE"
  gcloud container clusters get-credentials "$GKE_CLUSTER" \
    --zone "$ZONE" \
    --project "$PROJECT_ID"
fi

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 \
  || die "Namespace $NAMESPACE does not exist."

kubectl -n "$NAMESPACE" get secret platform-secret >/dev/null 2>&1 \
  || die "Secret platform-secret does not exist in $NAMESPACE."

secret_value() {
  local key="$1"
  local encoded
  encoded="$(kubectl -n "$NAMESPACE" get secret platform-secret \
    -o "jsonpath={.data.${key}}")"
  [[ -n "$encoded" ]] || die "platform-secret is missing $key"
  printf '%s' "$encoded" | base64 --decode
}

urlencode() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=""))
PY
}

create_runtime_url_secret() {
  local pg_user pg_password pg_db rabbit_user rabbit_password
  local pg_user_enc pg_password_enc pg_db_enc rabbit_user_enc rabbit_password_enc
  local database_url rabbitmq_url tmp

  pg_user="$(secret_value POSTGRES_USER)"
  pg_password="$(secret_value POSTGRES_PASSWORD)"
  pg_db="$(secret_value POSTGRES_DB)"
  rabbit_user="$(secret_value RABBITMQ_USER)"
  rabbit_password="$(secret_value RABBITMQ_PASSWORD)"

  pg_user_enc="$(urlencode "$pg_user")"
  pg_password_enc="$(urlencode "$pg_password")"
  pg_db_enc="$(urlencode "$pg_db")"
  rabbit_user_enc="$(urlencode "$rabbit_user")"
  rabbit_password_enc="$(urlencode "$rabbit_password")"

  database_url="postgresql+psycopg://${pg_user_enc}:${pg_password_enc}@postgres:5432/${pg_db_enc}"
  rabbitmq_url="amqp://${rabbit_user_enc}:${rabbit_password_enc}@rabbitmq:5672/"

  tmp="$(mktemp)"
  chmod 600 "$tmp"
  trap 'rm -f "$tmp"' RETURN
  {
    printf 'DATABASE_URL=%s\n' "$database_url"
    printf 'RABBITMQ_URL=%s\n' "$rabbitmq_url"
  } > "$tmp"

  kubectl create secret generic platform-runtime-urls \
    -n "$NAMESPACE" \
    --from-env-file="$tmp" \
    --dry-run=client -o yaml | kubectl apply -f -

  rm -f "$tmp"
  trap - RETURN
  ok "Created/updated platform-runtime-urls without writing credentials to Git."
}

create_gateway_auth_secret() {
  if kubectl -n "$NAMESPACE" get secret api-gateway-auth >/dev/null 2>&1 \
     && [[ "$ROTATE_GATEWAY_AUTH" != "1" ]]; then
    ok "api-gateway-auth already exists; keeping current credentials."
    return 0
  fi

  local username password confirmation jwt_secret tmp
  read -rp "API Gateway admin username [admin]: " username
  username="${username:-admin}"

  while true; do
    read -rsp "Strong API Gateway admin password: " password
    echo
    [[ ${#password} -ge 12 ]] || {
      warn "Use at least 12 characters."
      continue
    }
    read -rsp "Confirm admin password: " confirmation
    echo
    [[ "$password" == "$confirmation" ]] || {
      warn "Passwords do not match."
      continue
    }
    break
  done

  jwt_secret="$(openssl rand -hex 32)"
  tmp="$(mktemp)"
  chmod 600 "$tmp"
  trap 'rm -f "$tmp"' RETURN
  {
    printf 'ADMIN_USERNAME=%s\n' "$username"
    printf 'ADMIN_PASSWORD=%s\n' "$password"
    printf 'JWT_SECRET=%s\n' "$jwt_secret"
  } > "$tmp"

  kubectl create secret generic api-gateway-auth \
    -n "$NAMESPACE" \
    --from-env-file="$tmp" \
    --dry-run=client -o yaml | kubectl apply -f -

  rm -f "$tmp"
  trap - RETURN
  unset password confirmation jwt_secret
  ok "Created/rotated api-gateway-auth. Save the password in your password manager."
}

write_standard_service() {
  local name="$1"
  local port="${2:-8080}"
  local target="${3:-8080}"

  write_file "$ROOT/k8s/apps/$name/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: $name
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: $name
    app.kubernetes.io/part-of: telecom-platform
spec:
  type: ClusterIP
  selector:
    app: $name
  ports:
    - name: http
      port: $port
      targetPort: $target
      protocol: TCP
EOF
}

write_standard_deployment() {
  local name="$1"
  local image="$2"

  write_file "$ROOT/k8s/apps/$name/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $name
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: $name
    app.kubernetes.io/part-of: telecom-platform
spec:
  replicas: 1
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      app: $name
  template:
    metadata:
      labels:
        app: $name
        app.kubernetes.io/name: $name
        app.kubernetes.io/part-of: telecom-platform
    spec:
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: 20
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: $name
          image: $REGISTRY/$image:$IMAGE_TAG
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          envFrom:
            - configMapRef:
                name: platform-config
            - secretRef:
                name: platform-secret
            - secretRef:
                name: platform-runtime-urls
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          readinessProbe:
            tcpSocket:
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          livenessProbe:
            tcpSocket:
              port: http
            initialDelaySeconds: 15
            periodSeconds: 20
            timeoutSeconds: 3
            failureThreshold: 3
EOF

  write_file "$ROOT/k8s/apps/$name/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
EOF
}

write_standard_deployment device-service device-service
write_standard_service device-service

write_standard_deployment inventory-service inventory-service
write_standard_service inventory-service

write_standard_deployment workflow-service workflow-service
write_standard_service workflow-service

write_standard_deployment notification-service notification-service
write_standard_service notification-service

write_standard_deployment audit-service audit-service
write_standard_service audit-service

write_file "$ROOT/k8s/apps/api-gateway/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: api-gateway
    app.kubernetes.io/part-of: telecom-platform
spec:
  replicas: 2
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
        app.kubernetes.io/name: api-gateway
        app.kubernetes.io/part-of: telecom-platform
    spec:
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: 20
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: api-gateway
          image: $REGISTRY/api-gateway:$IMAGE_TAG
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          envFrom:
            - secretRef:
                name: api-gateway-auth
          env:
            - name: REDIS_URL
              value: redis://redis:6379/0
            - name: DEVICE_SERVICE_URL
              value: http://device-service:8080
            - name: INVENTORY_SERVICE_URL
              value: http://inventory-service:8080
            - name: WORKFLOW_SERVICE_URL
              value: http://workflow-service:8080
            - name: NOTIFICATION_SERVICE_URL
              value: http://notification-service:8080
            - name: AUDIT_SERVICE_URL
              value: http://audit-service:8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          startupProbe:
            httpGet:
              path: /health/live
              port: http
            periodSeconds: 2
            timeoutSeconds: 2
            failureThreshold: 30
          readinessProbe:
            httpGet:
              path: /health/live
              port: http
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /health/live
              port: http
            periodSeconds: 15
            timeoutSeconds: 3
            failureThreshold: 3
EOF

write_file "$ROOT/k8s/apps/api-gateway/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: api-gateway
    app.kubernetes.io/part-of: telecom-platform
  annotations:
    cloud.google.com/neg: '{"ingress": true}'
    cloud.google.com/backend-config: '{"default":"api-gateway-backend-config"}'
spec:
  type: ClusterIP
  selector:
    app: api-gateway
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
EOF

write_file "$ROOT/k8s/apps/api-gateway/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
EOF

write_file "$ROOT/k8s/ingress/api-gateway-backend-config.yaml" <<EOF
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: api-gateway-backend-config
  namespace: $NAMESPACE
spec:
  healthCheck:
    type: HTTP
    requestPath: /health/live
    port: 8080
    checkIntervalSec: 10
    timeoutSec: 5
    healthyThreshold: 1
    unhealthyThreshold: 3
EOF

write_file "$ROOT/k8s/apps/background-workers/workflow-worker.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workflow-worker
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: workflow-worker
    app.kubernetes.io/part-of: telecom-platform
spec:
  replicas: 1
  selector:
    matchLabels:
      app: workflow-worker
  template:
    metadata:
      labels:
        app: workflow-worker
        app.kubernetes.io/name: workflow-worker
        app.kubernetes.io/part-of: telecom-platform
    spec:
      automountServiceAccountToken: false
      containers:
        - name: workflow-worker
          image: $REGISTRY/workflow-service:$IMAGE_TAG
          imagePullPolicy: IfNotPresent
          command: ["python", "-m", "app.worker"]
          envFrom:
            - configMapRef:
                name: platform-config
            - secretRef:
                name: platform-secret
            - secretRef:
                name: platform-runtime-urls
          env:
            - name: EXECUTION_MODE
              value: "$EXECUTION_MODE"
            - name: PYTHONUNBUFFERED
              value: "1"
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 300m
              memory: 256Mi
EOF

write_file "$ROOT/k8s/apps/background-workers/notification-consumer.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notification-consumer
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: notification-consumer
    app.kubernetes.io/part-of: telecom-platform
spec:
  replicas: 1
  selector:
    matchLabels:
      app: notification-consumer
  template:
    metadata:
      labels:
        app: notification-consumer
        app.kubernetes.io/name: notification-consumer
        app.kubernetes.io/part-of: telecom-platform
    spec:
      automountServiceAccountToken: false
      containers:
        - name: notification-consumer
          image: $REGISTRY/notification-service:$IMAGE_TAG
          imagePullPolicy: IfNotPresent
          command: ["python", "-m", "app.consumer"]
          envFrom:
            - configMapRef:
                name: platform-config
            - secretRef:
                name: platform-secret
            - secretRef:
                name: platform-runtime-urls
          env:
            - name: PYTHONUNBUFFERED
              value: "1"
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 300m
              memory: 256Mi
EOF

write_file "$ROOT/k8s/apps/background-workers/audit-consumer.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: audit-consumer
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: audit-consumer
    app.kubernetes.io/part-of: telecom-platform
spec:
  replicas: 1
  selector:
    matchLabels:
      app: audit-consumer
  template:
    metadata:
      labels:
        app: audit-consumer
        app.kubernetes.io/name: audit-consumer
        app.kubernetes.io/part-of: telecom-platform
    spec:
      automountServiceAccountToken: false
      containers:
        - name: audit-consumer
          image: $REGISTRY/audit-service:$IMAGE_TAG
          imagePullPolicy: IfNotPresent
          command: ["python", "-m", "app.consumer"]
          envFrom:
            - configMapRef:
                name: platform-config
            - secretRef:
                name: platform-secret
            - secretRef:
                name: platform-runtime-urls
          env:
            - name: PYTHONUNBUFFERED
              value: "1"
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 300m
              memory: 256Mi
EOF

write_file "$ROOT/k8s/apps/background-workers/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - workflow-worker.yaml
  - notification-consumer.yaml
  - audit-consumer.yaml
EOF

for dir in \
  device-service \
  inventory-service \
  workflow-service \
  notification-service \
  audit-service \
  api-gateway \
  background-workers
do
  kubectl kustomize "$ROOT/k8s/apps/$dir" >/dev/null \
    || die "Kustomize validation failed for $dir"
done
ok "All generated backend manifests passed client-side Kustomize validation."

if [[ "$APPLY" != "1" ]]; then
  warn "APPLY=0: files were generated but nothing was applied."
  exit 0
fi

create_runtime_url_secret
create_gateway_auth_secret

log "Applying API Gateway BackendConfig"
kubectl apply -f "$ROOT/k8s/ingress/api-gateway-backend-config.yaml"

for dir in \
  device-service \
  inventory-service \
  workflow-service \
  notification-service \
  audit-service \
  api-gateway \
  background-workers
do
  log "Applying $dir"
  kubectl apply -k "$ROOT/k8s/apps/$dir"
done

for deployment in \
  device-service \
  inventory-service \
  workflow-service \
  notification-service \
  audit-service \
  api-gateway \
  workflow-worker \
  notification-consumer \
  audit-consumer
do
  log "Waiting for deployment/$deployment"
  kubectl -n "$NAMESPACE" rollout status deployment/"$deployment" --timeout=240s
done

log "Testing API Gateway from inside the cluster"
kubectl run backend-finalizer-curl \
  -n "$NAMESPACE" \
  --rm -i \
  --restart=Never \
  --image=curlimages/curl \
  -- curl -fsS http://api-gateway/health/live
echo

ok "Backend finalization completed."

cat <<SUMMARY

==============================================================================
BACKEND FINALIZATION COMPLETE
==============================================================================

Generated/updated:
  k8s/apps/device-service
  k8s/apps/inventory-service
  k8s/apps/workflow-service
  k8s/apps/notification-service
  k8s/apps/audit-service
  k8s/apps/api-gateway
  k8s/apps/background-workers
  k8s/ingress/api-gateway-backend-config.yaml

Runtime secrets:
  platform-runtime-urls
  api-gateway-auth

Important:
  - Database and RabbitMQ URLs are no longer stored in Deployment YAML files.
  - Existing platform-secret values were used to create encoded runtime URLs.
  - The API Gateway now has two replicas and HTTP health probes.
  - Background worker/consumer processes are deployed.
  - EXECUTION_MODE is currently: $EXECUTION_MODE

Backup:
  ${BACKUP_ROOT#"$ROOT/"}

Next:
  Run 02-bootstrap-frontend-k8s-adjusted.sh, then
  run 03-apply-final-ingress.sh.
==============================================================================
SUMMARY

