from fastapi import APIRouter

from app.core.config import get_settings

router = APIRouter(tags=["health"])
settings = get_settings()


@router.get("/health/live")
def live() -> dict[str, str]:
    return {
        "status": "healthy",
        "service": settings.service_name,
        "version": settings.service_version,
    }


@router.get("/health/ready")
def ready() -> dict[str, str]:
    return {
        "status": "ready",
        "service": settings.service_name,
        "version": settings.service_version,
    }
