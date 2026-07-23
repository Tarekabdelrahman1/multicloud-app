from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, IPvAnyAddress, field_validator

from app.models.enums import DeviceStatus, DeviceVendor


class DeviceCreate(BaseModel):
    hostname: str = Field(
        min_length=1,
        max_length=255,
        pattern=r"^[A-Za-z0-9][A-Za-z0-9._-]*$",
    )
    management_ip: IPvAnyAddress
    vendor: DeviceVendor
    model: str = Field(min_length=1, max_length=255)
    site: str = Field(min_length=1, max_length=255)
    software_version: str | None = Field(default=None, max_length=128)
    status: DeviceStatus = DeviceStatus.UNKNOWN

    @field_validator("hostname")
    @classmethod
    def normalize_hostname(cls, value: str) -> str:
        return value.strip().lower()

    @field_validator("model", "site")
    @classmethod
    def normalize_required_text(cls, value: str) -> str:
        return value.strip()


class DeviceUpdate(BaseModel):
    hostname: str | None = Field(
        default=None,
        min_length=1,
        max_length=255,
        pattern=r"^[A-Za-z0-9][A-Za-z0-9._-]*$",
    )
    management_ip: IPvAnyAddress | None = None
    vendor: DeviceVendor | None = None
    model: str | None = Field(default=None, min_length=1, max_length=255)
    site: str | None = Field(default=None, min_length=1, max_length=255)
    software_version: str | None = Field(default=None, max_length=128)
    status: DeviceStatus | None = None

    @field_validator("hostname")
    @classmethod
    def normalize_hostname(cls, value: str | None) -> str | None:
        return value.strip().lower() if value is not None else None


class DeviceRead(BaseModel):
    id: UUID
    hostname: str
    management_ip: IPvAnyAddress
    vendor: DeviceVendor
    model: str
    site: str
    software_version: str | None
    status: DeviceStatus
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class DeviceListResponse(BaseModel):
    items: list[DeviceRead]
    total: int
    limit: int
    offset: int
