from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, Response, status

from app.db.dependencies import DbSession
from app.schemas.device import DeviceCreate, DeviceListResponse, DeviceRead, DeviceUpdate
from app.services.device_service import DeviceService

router = APIRouter(prefix="/devices", tags=["devices"])


@router.get("", response_model=DeviceListResponse)
def list_devices(
    database_session: DbSession,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> DeviceListResponse:
    devices, total = DeviceService(database_session).list_devices(
        limit=limit,
        offset=offset,
    )
    return DeviceListResponse(items=devices, total=total, limit=limit, offset=offset)


@router.post("", response_model=DeviceRead, status_code=status.HTTP_201_CREATED)
def create_device(payload: DeviceCreate, database_session: DbSession) -> DeviceRead:
    return DeviceService(database_session).create_device(payload)


@router.get("/{device_id}", response_model=DeviceRead)
def get_device(device_id: UUID, database_session: DbSession) -> DeviceRead:
    return DeviceService(database_session).get_device(device_id)


@router.patch("/{device_id}", response_model=DeviceRead)
def update_device(
    device_id: UUID,
    payload: DeviceUpdate,
    database_session: DbSession,
) -> DeviceRead:
    return DeviceService(database_session).update_device(device_id, payload)


@router.delete(
    "/{device_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
)
def delete_device(device_id: UUID, database_session: DbSession) -> Response:
    DeviceService(database_session).delete_device(device_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
