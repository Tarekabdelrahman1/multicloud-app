from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query
from sqlalchemy import select

from common.http import add_http_middleware, configure_logging
from .domain import Base, Notification, NotificationCreate, NotificationRead, SessionLocal, engine, settings

configure_logging()


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(engine)
    yield


app = FastAPI(title="Notification Service", version="3.0.0", lifespan=lifespan)
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


@app.get("/api/v1/notifications", response_model=list[NotificationRead])
def list_notifications(limit: int = Query(100, ge=1, le=500), offset: int = Query(0, ge=0)):
    with SessionLocal() as db:
        return list(db.scalars(select(Notification).order_by(Notification.created_at.desc()).offset(offset).limit(limit)))


@app.post("/api/v1/notifications", response_model=NotificationRead, status_code=201)
def create_notification(payload: NotificationCreate):
    with SessionLocal() as db:
        notification = Notification(**payload.model_dump(), status="sent")
        db.add(notification)
        db.commit()
        db.refresh(notification)
        return notification
