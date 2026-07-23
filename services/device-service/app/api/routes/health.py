from fastapi import APIRouter
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.core.config import get_settings
from app.db.dependencies import DbSession
from app.schemas.health import HealthResponse

router = APIRouter(tags=["health"])
settings = get_settings()


@router.get("/health/live", response_model=HealthResponse)
def liveness() -> HealthResponse:
    return HealthResponse(
        status="healthy",
        service=settings.service_name,
        version=settings.service_version,
    )


@router.get("/health/ready", response_model=HealthResponse)
def readiness(database_session: DbSession):
    try:
        database_session.execute(text("SELECT 1"))
    except SQLAlchemyError:
        return JSONResponse(
            status_code=503,
            content={
                "status": "not_ready",
                "service": settings.service_name,
                "version": settings.service_version,
            },
        )

    return HealthResponse(
        status="ready",
        service=settings.service_name,
        version=settings.service_version,
    )
