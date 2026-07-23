from datetime import datetime
from uuid import UUID, uuid4

from pydantic import BaseModel
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import DateTime, JSON, String, create_engine
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker


class Settings(BaseSettings):
    model_config = SettingsConfigDict(case_sensitive=False)
    service_name: str = "audit-service"
    database_url: str = "postgresql+psycopg://platform:platform_password@postgres:5432/audit_db"
    rabbitmq_url: str = "amqp://platform:platform_password@rabbitmq:5672/"


settings = Settings()
engine = create_engine(settings.database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


class AuditEvent(Base):
    __tablename__ = "audit_events"
    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    event_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False, unique=True, index=True)
    event_type: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    source: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    correlation_id: Mapped[str | None] = mapped_column(String(100), nullable=True, index=True)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    payload: Mapped[dict] = mapped_column(JSON, nullable=False)


class AuditRead(BaseModel):
    id: UUID
    event_id: UUID
    event_type: str
    source: str
    correlation_id: str | None
    occurred_at: datetime
    payload: dict
    model_config = {"from_attributes": True}
