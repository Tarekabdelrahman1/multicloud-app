from uuid import UUID

from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError
from app.models.device import Device
from app.schemas.device import DeviceCreate, DeviceUpdate


class DeviceService:
    def __init__(self, database_session: Session) -> None:
        self.database_session = database_session

    def list_devices(self, *, limit: int, offset: int) -> tuple[list[Device], int]:
        query = select(Device).order_by(Device.hostname).offset(offset).limit(limit)
        devices = list(self.database_session.scalars(query).all())
        total = self.database_session.scalar(select(func.count()).select_from(Device))
        return devices, int(total or 0)

    def get_device(self, device_id: UUID) -> Device:
        device = self.database_session.get(Device, str(device_id))
        if device is None:
            raise NotFoundError(f"Device '{device_id}' was not found.")
        return device

    def create_device(self, payload: DeviceCreate) -> Device:
        management_ip = str(payload.management_ip)
        self._assert_unique(
            hostname=payload.hostname,
            management_ip=management_ip,
        )

        values = payload.model_dump()
        values["management_ip"] = management_ip
        values["vendor"] = payload.vendor.value
        values["status"] = payload.status.value

        device = Device(**values)
        self.database_session.add(device)

        try:
            self.database_session.commit()
            self.database_session.refresh(device)
        except IntegrityError as exc:
            self.database_session.rollback()
            raise ConflictError(
                "A device with the same hostname or management IP already exists."
            ) from exc

        return device

    def update_device(self, device_id: UUID, payload: DeviceUpdate) -> Device:
        device = self.get_device(device_id)
        updates = payload.model_dump(exclude_unset=True)

        if "management_ip" in updates and updates["management_ip"] is not None:
            updates["management_ip"] = str(updates["management_ip"])
        if "vendor" in updates and updates["vendor"] is not None:
            updates["vendor"] = updates["vendor"].value
        if "status" in updates and updates["status"] is not None:
            updates["status"] = updates["status"].value

        self._assert_unique(
            hostname=updates.get("hostname"),
            management_ip=updates.get("management_ip"),
            exclude_device_id=device_id,
        )

        for field_name, value in updates.items():
            setattr(device, field_name, value)

        try:
            self.database_session.commit()
            self.database_session.refresh(device)
        except IntegrityError as exc:
            self.database_session.rollback()
            raise ConflictError(
                "A device with the same hostname or management IP already exists."
            ) from exc

        return device

    def delete_device(self, device_id: UUID) -> None:
        device = self.get_device(device_id)
        self.database_session.delete(device)
        self.database_session.commit()

    def _assert_unique(
        self,
        *,
        hostname: str | None = None,
        management_ip: str | None = None,
        exclude_device_id: UUID | None = None,
    ) -> None:
        conditions = []
        if hostname is not None:
            conditions.append(Device.hostname == hostname)
        if management_ip is not None:
            conditions.append(Device.management_ip == management_ip)
        if not conditions:
            return

        query = select(Device.id).where(or_(*conditions))
        if exclude_device_id is not None:
            query = query.where(Device.id != str(exclude_device_id))

        if self.database_session.scalar(query) is not None:
            raise ConflictError(
                "A device with the same hostname or management IP already exists."
            )
