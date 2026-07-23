# Telecom Service Management Platform

## Services

- API Gateway
- Device Service
- Inventory Service
- Workflow Service
- Notification Service
- Audit Service
- PostgreSQL
- Redis
- RabbitMQ

## Start the platform

Stop the old standalone Device Service first if it uses port 8080:

```bash
cd services/device-service
docker compose down
cd ../..
```

Start the full platform:

```bash
docker compose -f docker-compose.platform.yml up --build -d
docker compose -f docker-compose.platform.yml ps
```

Open:

```text
http://localhost:8080/docs
```

Gateway readiness:

```bash
curl http://localhost:8080/health/ready
```

Examples:

```bash
curl http://localhost:8080/api/v1/devices
curl http://localhost:8080/api/v1/inventory
curl http://localhost:8080/api/v1/workflows
curl http://localhost:8080/api/v1/notifications
curl http://localhost:8080/api/v1/audit-events
```

RabbitMQ management:

```text
http://localhost:15672
```

Username/password:

```text
guest / guest
```

## Important

The new services are runnable Phase-2 MVP scaffolds. Their current domain data is
stored in memory and is lost when containers restart. The Device Service remains
PostgreSQL-backed. The next phase should add PostgreSQL repositories, RabbitMQ
publishers/consumers, authentication, tracing, metrics, and Kubernetes manifests.
