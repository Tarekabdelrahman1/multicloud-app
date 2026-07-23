from contextlib import asynccontextmanager
from datetime import UTC, datetime
from uuid import UUID, uuid4

from fastapi import FastAPI, HTTPException, Query, Request, Response, status
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import DateTime, Integer, String, create_engine, select
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

from common.events import EventEnvelope, EventPublisher
from common.http import add_http_middleware, configure_logging


class Settings(BaseSettings):
    model_config = SettingsConfigDict(case_sensitive=False)
    service_name: str = "inventory-service"
    database_url: str = "postgresql+psycopg://platform:platform_password@postgres:5432/inventory_db"
    rabbitmq_url: str = "amqp://platform:platform_password@rabbitmq:5672/"


settings = Settings()
configure_logging()
engine = create_engine(settings.database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


class InventoryItem(Base):
    __tablename__ = "inventory_items"
    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    category: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    quantity: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    low_stock_threshold: Mapped[int] = mapped_column(Integer, nullable=False, default=5)
    location: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(UTC))
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        onupdate=lambda: datetime.now(UTC),
    )


class InventoryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    category: str = Field(min_length=1, max_length=100)
    quantity: int = Field(ge=0)
    low_stock_threshold: int = Field(default=5, ge=0)
    location: str = Field(min_length=1, max_length=255)


class InventoryUpdate(BaseModel):
    name: str | None = None
    category: str | None = None
    quantity: int | None = Field(default=None, ge=0)
    low_stock_threshold: int | None = Field(default=None, ge=0)
    location: str | None = None


class InventoryRead(BaseModel):
    id: UUID
    name: str
    category: str
    quantity: int
    low_stock_threshold: int
    location: str
    created_at: datetime
    updated_at: datetime
    model_config = {"from_attributes": True}


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(engine)
    app.state.publisher = EventPublisher(settings.rabbitmq_url)
    await app.state.publisher.start()
    yield
    await app.state.publisher.close()


app = FastAPI(title="Inventory Service", version="3.0.0", lifespan=lifespan)
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


@app.get("/api/v1/inventory", response_model=list[InventoryRead])
def list_inventory(limit: int = Query(100, ge=1, le=500), offset: int = Query(0, ge=0)):
    with SessionLocal() as db:
        return list(db.scalars(select(InventoryItem).order_by(InventoryItem.name).offset(offset).limit(limit)))


@app.get("/api/v1/inventory/{item_id}", response_model=InventoryRead)
def get_inventory(item_id: UUID):
    with SessionLocal() as db:
        item = db.get(InventoryItem, item_id)
        if not item:
            raise HTTPException(status_code=404, detail="Inventory item not found")
        return item


@app.post("/api/v1/inventory", response_model=InventoryRead, status_code=201)
async def create_inventory(payload: InventoryCreate, request: Request):
    with SessionLocal() as db:
        item = InventoryItem(**payload.model_dump())
        db.add(item)
        db.commit()
        db.refresh(item)
    data = InventoryRead.model_validate(item).model_dump(mode="json")
    await request.app.state.publisher.publish(
        EventEnvelope(
            event_type="inventory.created",
            source=settings.service_name,
            correlation_id=getattr(request.state, "request_id", None),
            data=data,
        )
    )
    if item.quantity <= item.low_stock_threshold:
        await request.app.state.publisher.publish(
            EventEnvelope(
                event_type="inventory.low_stock",
                source=settings.service_name,
                correlation_id=getattr(request.state, "request_id", None),
                data=data,
            )
        )
    return item


@app.patch("/api/v1/inventory/{item_id}", response_model=InventoryRead)
async def update_inventory(item_id: UUID, payload: InventoryUpdate, request: Request):
    with SessionLocal() as db:
        item = db.get(InventoryItem, item_id)
        if not item:
            raise HTTPException(status_code=404, detail="Inventory item not found")
        for field, value in payload.model_dump(exclude_unset=True).items():
            setattr(item, field, value)
        db.commit()
        db.refresh(item)
    event_type = "inventory.low_stock" if item.quantity <= item.low_stock_threshold else "inventory.updated"
    await request.app.state.publisher.publish(
        EventEnvelope(
            event_type=event_type,
            source=settings.service_name,
            correlation_id=getattr(request.state, "request_id", None),
            data=InventoryRead.model_validate(item).model_dump(mode="json"),
        )
    )
    return item


@app.delete("/api/v1/inventory/{item_id}", status_code=204)
async def delete_inventory(item_id: UUID, request: Request):
    with SessionLocal() as db:
        item = db.get(InventoryItem, item_id)
        if not item:
            raise HTTPException(status_code=404, detail="Inventory item not found")
        data = InventoryRead.model_validate(item).model_dump(mode="json")
        db.delete(item)
        db.commit()
    await request.app.state.publisher.publish(
        EventEnvelope(
            event_type="inventory.deleted",
            source=settings.service_name,
            correlation_id=getattr(request.state, "request_id", None),
            data=data,
        )
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)
