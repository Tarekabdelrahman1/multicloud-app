import asyncio
import secrets
import time
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from typing import Any

import httpx
import redis.asyncio as redis
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response
from jose import JWTError, jwt
from pydantic import BaseModel
from pydantic_settings import BaseSettings, SettingsConfigDict

from common.http import add_http_middleware, configure_logging


class Settings(BaseSettings):
    model_config = SettingsConfigDict(case_sensitive=False)
    service_name: str = "api-gateway"
    redis_url: str = "redis://redis:6379/0"
    jwt_secret: str = "change-me"
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 60
    admin_username: str = "admin"
    admin_password: str = "change-me"
    rate_limit_per_minute: int = 120
    device_service_url: str = "http://device-service:8080"
    inventory_service_url: str = "http://inventory-service:8080"
    workflow_service_url: str = "http://workflow-service:8080"
    notification_service_url: str = "http://notification-service:8080"
    audit_service_url: str = "http://audit-service:8080"


settings = Settings()
configure_logging()

SERVICE_MAP = {
    "devices": settings.device_service_url,
    "inventory": settings.inventory_service_url,
    "workflows": settings.workflow_service_url,
    "notifications": settings.notification_service_url,
    "audit": settings.audit_service_url,
}


class LoginRequest(BaseModel):
    username: str
    password: str


def create_access_token(subject: str) -> str:
    expires = datetime.now(UTC) + timedelta(minutes=settings.access_token_minutes)
    return jwt.encode(
        {"sub": subject, "role": "admin", "exp": expires},
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )


def decode_token(token: str) -> dict[str, Any]:
    try:
        return jwt.decode(
            token, settings.jwt_secret, algorithms=[settings.jwt_algorithm]
        )
    except JWTError as exc:
        raise HTTPException(status_code=401, detail="Invalid or expired token") from exc


def require_auth(request: Request) -> dict[str, Any]:
    scheme, _, token = request.headers.get("authorization", "").partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Bearer token is required")
    return decode_token(token)


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.http = httpx.AsyncClient(timeout=httpx.Timeout(30.0, connect=5.0))
    app.state.redis = redis.from_url(settings.redis_url, decode_responses=True)
    yield
    await app.state.http.aclose()
    await app.state.redis.aclose()


app = FastAPI(title="Telecom Platform API Gateway", version="3.0.0", lifespan=lifespan)
add_http_middleware(app, settings.service_name)


@app.middleware("http")
async def rate_limit(request: Request, call_next):
    if request.url.path.startswith("/health"):
        return await call_next(request)
    client_ip = request.client.host if request.client else "unknown"
    key = f"rate-limit:{client_ip}:{int(time.time() // 60)}"
    try:
        count = await request.app.state.redis.incr(key)
        if count == 1:
            await request.app.state.redis.expire(key, 70)
        if count > settings.rate_limit_per_minute:
            return JSONResponse(
                status_code=429,
                content={"detail": "Rate limit exceeded"},
                headers={"retry-after": "60"},
            )
    except Exception:
        pass
    return await call_next(request)


@app.get("/health/live")
def live():
    return {"status": "alive", "service": settings.service_name}


@app.get("/health/ready")
async def ready(request: Request):
    checks: dict[str, str] = {}
    try:
        await request.app.state.redis.ping()
        checks["redis"] = "ready"
    except Exception:
        checks["redis"] = "not_ready"

    async def check(name: str, url: str) -> tuple[str, str]:
        try:
            response = await request.app.state.http.get(f"{url}/health/live")
            return name, "ready" if response.is_success else "not_ready"
        except Exception:
            return name, "not_ready"

    checks.update(
        await asyncio.gather(*(check(name, url) for name, url in SERVICE_MAP.items()))
    )
    ok = all(value == "ready" for value in checks.values())
    return JSONResponse(
        status_code=200 if ok else 503,
        content={"status": "ready" if ok else "not_ready", "checks": checks},
    )


@app.post("/auth/login")
def login(payload: LoginRequest):
    valid = secrets.compare_digest(payload.username, settings.admin_username)
    valid = valid and secrets.compare_digest(
        payload.password, settings.admin_password
    )
    if not valid:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return {
        "access_token": create_access_token(payload.username),
        "token_type": "bearer",
        "expires_in": settings.access_token_minutes * 60,
    }


METHODS = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]


@app.api_route("/api/v1/{service}", methods=METHODS)
@app.api_route("/api/v1/{service}/{path:path}", methods=METHODS)
async def proxy(service: str, request: Request, path: str = ""):
    require_auth(request)
    base_url = SERVICE_MAP.get(service)
    if not base_url:
        raise HTTPException(status_code=404, detail="Unknown service route")
    suffix = f"/api/v1/{service}" + (f"/{path}" if path else "")
    headers = {
        key: value
        for key, value in request.headers.items()
        if key.lower() not in {"host", "content-length"}
    }
    headers["x-request-id"] = getattr(request.state, "request_id", "")
    try:
        upstream = await request.app.state.http.request(
            request.method,
            f"{base_url}{suffix}",
            params=request.query_params,
            content=await request.body(),
            headers=headers,
        )
    except httpx.RequestError as exc:
        raise HTTPException(status_code=502, detail=f"Upstream unavailable: {service}") from exc
    excluded = {
        "content-encoding",
        "transfer-encoding",
        "connection",
        "content-length",
    }
    return Response(
        content=upstream.content,
        status_code=upstream.status_code,
        headers={
            key: value
            for key, value in upstream.headers.items()
            if key.lower() not in excluded
        },
        media_type=upstream.headers.get("content-type"),
    )
