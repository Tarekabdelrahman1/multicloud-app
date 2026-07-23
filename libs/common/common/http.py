import json
import logging
import time
from uuid import uuid4

from fastapi import FastAPI, Request


def configure_logging() -> None:
    logging.basicConfig(level=logging.INFO, format="%(message)s")


def add_http_middleware(app: FastAPI, service_name: str) -> None:
    logger = logging.getLogger(service_name)

    @app.middleware("http")
    async def request_context(request: Request, call_next):
        request_id = request.headers.get("x-request-id") or str(uuid4())
        request.state.request_id = request_id
        started = time.perf_counter()

        try:
            response = await call_next(request)
        except Exception:
            logger.exception(
                json.dumps(
                    {
                        "event": "request_failed",
                        "service": service_name,
                        "request_id": request_id,
                        "method": request.method,
                        "path": request.url.path,
                    }
                )
            )
            raise

        duration_ms = round((time.perf_counter() - started) * 1000, 2)
        response.headers["x-request-id"] = request_id
        logger.info(
            json.dumps(
                {
                    "event": "request_completed",
                    "service": service_name,
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": response.status_code,
                    "duration_ms": duration_ms,
                }
            )
        )
        return response
