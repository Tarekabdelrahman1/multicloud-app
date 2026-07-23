from datetime import UTC, datetime
from uuid import UUID, uuid4

from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import DateTime, JSON, String, Text, create_engine
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker


class Settings(BaseSettings):
    model_config = SettingsConfigDict(case_sensitive=False)
    service_name: str = "notification-service"
    database_url: str = "postgresql+psycopg://platform:platform_password@postgres:5432/notification_db"
    rabbitmq_url: str = "amqp://platform:platform_password@rabbitmq:5672/"


settings = Settings()
engine = create_engine(settings.database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


class Notification(Base):
    __tablename__ = "notifications"
    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    channel: Mapped[str] = mapped_column(String(50), nullable=False, default="console")
    recipient: Mapped[str] = mapped_column(String(255), nullable=False, default="operations")
    subject: Mapped[str] = mapped_column(String(255), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="sent")
    source_event_type: Mapped[str | None] = mapped_column(String(100), nullable=True, index=True)
    source_event_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), nullable=True, unique=True)
    payload: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(UTC))


class NotificationCreate(BaseModel):
    channel: str = "console"
    recipient: str = "operations"
    subject: str = Field(min_length=1, max_length=255)
    body: str = Field(min_length=1)


class NotificationRead(BaseModel):
    id: UUID
    channel: str
    recipient: str
    subject: str
    body: str
    status: str
    source_event_type: str | None
    source_event_id: UUID | None
    payload: dict
    created_at: datetime
    model_config = {"from_attributes": True}
