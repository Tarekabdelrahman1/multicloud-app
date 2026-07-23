from datetime import UTC, datetime
from threading import Lock
from uuid import UUID, uuid4

from fastapi import APIRouter, status
from pydantic import BaseModel, Field

router = APIRouter(prefix="/notifications", tags=["notifications"])
_lock = Lock()
_notifications: dict[UUID, "Notification"] = {}


class NotificationCreate(BaseModel):
    channel: str = Field(pattern="^(email|sms|webhook|console)$")
    recipient: str = Field(min_length=1, max_length=255)
    subject: str = Field(min_length=1, max_length=255)
    message: str = Field(min_length=1, max_length=4000)


class Notification(NotificationCreate):
    id: UUID
    state: str
    created_at: datetime


@router.get("", response_model=list[Notification])
def list_notifications() -> list[Notification]:
    return list(_notifications.values())


@router.post("", response_model=Notification, status_code=status.HTTP_202_ACCEPTED)
def send_notification(payload: NotificationCreate) -> Notification:
    notification = Notification(
        id=uuid4(),
        state="accepted",
        created_at=datetime.now(UTC),
        **payload.model_dump(),
    )
    with _lock:
        _notifications[notification.id] = notification
    return notification

