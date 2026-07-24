# Telecom Operations Frontend

A production-built React/TypeScript single-page application served by unprivileged
Nginx. Nginx proxies browser calls to the API Gateway, keeping the microservices
private and avoiding browser CORS configuration.

## Local development

```bash
npm install
npm run dev
```

The Vite development proxy expects the gateway at `http://localhost:8080`.

## Container

```bash
docker build -t telecom-frontend .
docker run --rm -p 3000:8080 \
  -e API_GATEWAY_UPSTREAM=host.docker.internal:8080 \
  telecom-frontend
```

## Kubernetes image

```text
us-central1-docker.pkg.dev/devops-project-503113/dev-docker/frontend:frontend-v1
```
