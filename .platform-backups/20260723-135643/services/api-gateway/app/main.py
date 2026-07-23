from functools import lru_cache

import httpx
from fastapi import FastAPI, HTTPException, Request, Response
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    service_name: str = "api-gateway"
    service_version: str = "1.0.0"

    device_service_url: str = "http://device-service:8080"
    inventory_service_url: str = "http://inventory-service:8080"
    workflow_service_url: str = "http://workflow-service:8080"
    notification_service_url: str = "http://notification-service:8080"
    audit_service_url: str = "http://audit-service:8080"

    model_config = SettingsConfigDict(case_sensitive=False, extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()

app = FastAPI(
    title="Telecom API Gateway",
    version=settings.service_version,
)


SERVICE_MAP = {
    "devices": settings.device_service_url,
    "inventory": settings.inventory_service_url,
    "workflows": settings.workflow_service_url,
    "notifications": settings.notification_service_url,
    "audit-events": settings.audit_service_url,
}


@app.get("/health/live")
def live() -> dict[str, str]:
    return {
        "status": "healthy",
        "service": settings.service_name,
        "version": settings.service_version,
    }


@app.get("/health/ready")
async def ready() -> dict[str, object]:
    results: dict[str, str] = {}
    async with httpx.AsyncClient(timeout=3.0) as client:
        for service_name, base_url in SERVICE_MAP.items():
            try:
                response = await client.get(f"{base_url}/health/ready")
                results[service_name] = "ready" if response.is_success else "not_ready"
            except httpx.HTTPError:
                results[service_name] = "unreachable"

    overall = "ready" if all(value == "ready" for value in results.values()) else "degraded"
    return {"status": overall, "services": results}


@app.api_route(
    "/api/v1/{service}/{path:path}",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
)
async def proxy(service: str, path: str, request: Request) -> Response:
    base_url = SERVICE_MAP.get(service)
    if base_url is None:
        raise HTTPException(status_code=404, detail="Unknown service")

    target_path = f"/api/v1/{service}"
    if path:
        target_path += f"/{path}"

    body = await request.body()
    headers = {
        key: value
        for key, value in request.headers.items()
        if key.lower() not in {"host", "content-length"}
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            upstream = await client.request(
                method=request.method,
                url=f"{base_url}{target_path}",
                params=request.query_params,
                content=body,
                headers=headers,
            )
        except httpx.HTTPError as exc:
            raise HTTPException(status_code=502, detail="Upstream service unavailable") from exc

    excluded_headers = {"content-encoding", "transfer-encoding", "connection"}
    response_headers = {
        key: value
        for key, value in upstream.headers.items()
        if key.lower() not in excluded_headers
    }

    return Response(
        content=upstream.content,
        status_code=upstream.status_code,
        headers=response_headers,
        media_type=upstream.headers.get("content-type"),
    )
