from datetime import UTC, datetime
from threading import Lock
from uuid import UUID, uuid4

from fastapi import APIRouter, status
from pydantic import BaseModel, Field

router = APIRouter(prefix="/audit-events", tags=["audit"])
_lock = Lock()
_events: dict[UUID, "AuditEvent"] = {}


class AuditEventCreate(BaseModel):
    actor: str = Field(min_length=1, max_length=255)
    action: str = Field(min_length=1, max_length=255)
    resource_type: str = Field(min_length=1, max_length=100)
    resource_id: str = Field(min_length=1, max_length=255)
    metadata: dict[str, str | int | float | bool] = {}


class AuditEvent(AuditEventCreate):
    id: UUID
    created_at: datetime


@router.get("", response_model=list[AuditEvent])
def list_audit_events() -> list[AuditEvent]:
    return list(_events.values())


@router.post("", response_model=AuditEvent, status_code=status.HTTP_201_CREATED)
def create_audit_event(payload: AuditEventCreate) -> AuditEvent:
    event = AuditEvent(
        id=uuid4(),
        created_at=datetime.now(UTC),
        **payload.model_dump(),
    )
    with _lock:
        _events[event.id] = event
    return event

