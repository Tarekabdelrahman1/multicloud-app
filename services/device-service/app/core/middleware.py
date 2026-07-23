import logging
from time import perf_counter
from uuid import uuid4

from fastapi import Request, Response
from starlette.middleware.base import RequestResponseEndpoint

logger = logging.getLogger("device_service.http")


async def request_context_middleware(
    request: Request,
    call_next: RequestResponseEndpoint,
) -> Response:
    request_id = request.headers.get("X-Request-ID", str(uuid4()))
    started_at = perf_counter()

    try:
        response = await call_next(request)
    except Exception:
        logger.exception(
            "http_request_failed",
            extra={
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
                "duration_ms": round((perf_counter() - started_at) * 1000, 2),
            },
        )
        raise

    response.headers["X-Request-ID"] = request_id

    logger.info(
        "http_request_completed",
        extra={
            "request_id": request_id,
            "method": request.method,
            "path": request.url.path,
            "status_code": response.status_code,
            "duration_ms": round((perf_counter() - started_at) * 1000, 2),
        },
    )

    return response
