# Telecom Device Service

Professional inventory microservice for the Telecom Service Management Platform.

## Features

- FastAPI REST API
- PostgreSQL persistence
- SQLAlchemy 2.x
- Alembic migrations
- Device CRUD and validation
- Liveness and readiness endpoints
- Structured JSON logs
- Request IDs
- Automated tests
- Multi-stage non-root container
- Docker Compose local environment

## Run locally

```bash
docker compose up --build -d
docker compose ps
```

Swagger UI:

```text
http://localhost:8080/docs
```

Health checks:

```bash
curl http://localhost:8080/health/live
curl http://localhost:8080/health/ready
```

Create a device:

```bash
curl -X POST http://localhost:8080/api/v1/devices \
  -H 'Content-Type: application/json' \
  -d '{
    "hostname": "cairo-core-01",
    "management_ip": "10.10.0.11",
    "vendor": "nokia",
    "model": "7750 SR-1",
    "site": "Cairo-Core",
    "software_version": "24.7.R1",
    "status": "active"
  }'
```

List devices:

```bash
curl http://localhost:8080/api/v1/devices
```

Stop:

```bash
docker compose down
```
