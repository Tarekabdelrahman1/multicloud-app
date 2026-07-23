from fastapi import FastAPI

from app.api.routes.domain import router as domain_router
from app.api.routes.health import router as health_router
from app.core.config import get_settings

settings = get_settings()

app = FastAPI(
    title="Telecom Audit Service",
    version=settings.service_version,
)

app.include_router(health_router)
app.include_router(domain_router, prefix=settings.api_v1_prefix)


@app.get("/", include_in_schema=False)
def root() -> dict[str, str]:
    return {
        "service": settings.service_name,
        "version": settings.service_version,
        "docs": "/docs",
    }
