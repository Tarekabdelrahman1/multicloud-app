import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.api.router import api_router
from app.api.routes.health import router as health_router
from app.core.config import get_settings
from app.core.exceptions import AppError, app_error_handler
from app.core.logging import configure_logging
from app.core.middleware import request_context_middleware

settings = get_settings()
configure_logging()
logger = logging.getLogger("device_service.lifecycle")


@asynccontextmanager
async def lifespan(_application: FastAPI) -> AsyncIterator[None]:
    logger.info("service_started")
    yield
    logger.info("service_stopped")


app = FastAPI(
    title="Telecom Device Service",
    description="Device inventory API for the Telecom Service Management Platform.",
    version=settings.service_version,
    docs_url="/docs" if settings.docs_enabled else None,
    redoc_url="/redoc" if settings.docs_enabled else None,
    openapi_url="/openapi.json" if settings.docs_enabled else None,
    lifespan=lifespan,
)

app.middleware("http")(request_context_middleware)
app.add_exception_handler(AppError, app_error_handler)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(
    _request: Request,
    exc: RequestValidationError,
) -> JSONResponse:
    return JSONResponse(
        status_code=422,
        content={
            "error": {
                "code": "validation_error",
                "message": "The request contains invalid data.",
                "details": jsonable_encoder(exc.errors()),
            }
        },
    )


@app.get("/", include_in_schema=False)
def root() -> dict[str, str]:
    return {
        "service": settings.service_name,
        "version": settings.service_version,
        "docs": "/docs",
    }


app.include_router(health_router)
app.include_router(api_router, prefix=settings.api_v1_prefix)
