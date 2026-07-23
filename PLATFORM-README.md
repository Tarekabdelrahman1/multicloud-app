# Telecom Platform — Phase 3

This phase adds PostgreSQL persistence, RabbitMQ event flow, workers/consumers,
Redis rate limiting, JWT gateway login, shared request IDs, and a smoke test.

## Start

```bash
cp .env.platform.example .env.platform
nano .env.platform
docker compose --env-file .env.platform -f docker-compose.platform.yml up --build -d
```

Gateway: `http://localhost:8080`
RabbitMQ UI: `http://localhost:15672`

Direct debug ports: Inventory `8081`, Workflow `8082`, Notification `8083`,
Audit `8084`, Device `8085`.

## Test

```bash
set -a; source .env.platform; set +a
./scripts/platform-smoke-test.sh
```

## Safety boundary

Workflow execution remains `mock`. It changes workflow state and publishes
events, but it does not connect to a router or execute Nokia commands.

## Still required before production

- Alembic migrations for the four new databases; they currently use `create_all`.
- Device Service transactional outbox and RabbitMQ event publishing.
- Secret Manager/Vault, real user storage, password hashing, refresh tokens, full RBAC.
- TLS/mTLS, Prometheus, OpenTelemetry, Loki, dashboards, alerts, and SLOs.
- Integration/contract/failure tests.
- Kubernetes, Helm, Argo CD, and CI/CD.
