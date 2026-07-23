from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query
from sqlalchemy import select

from common.http import add_http_middleware, configure_logging
from .domain import AuditEvent, AuditRead, Base, SessionLocal, engine, settings

configure_logging()


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(engine)
    yield


app = FastAPI(title="Audit Service", version="3.0.0", lifespan=lifespan)
add_http_middleware(app, settings.service_name)


@app.get("/health/live")
def live():
    return {"status": "alive", "service": settings.service_name}


@app.get("/health/ready")
def ready():
    try:
        with engine.connect() as connection:
            connection.exec_driver_sql("SELECT 1")
        return {"status": "ready"}
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Database not ready") from exc


@app.get("/api/v1/audit", response_model=list[AuditRead])
def list_events(limit: int = Query(100, ge=1, le=500), offset: int = Query(0, ge=0)):
    with SessionLocal() as db:
        return list(db.scalars(select(AuditEvent).order_by(AuditEvent.occurred_at.desc()).offset(offset).limit(limit)))
