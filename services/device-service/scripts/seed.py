from sqlalchemy import select

from app.db.session import SessionLocal
from app.models.device import Device
from app.models.enums import DeviceStatus, DeviceVendor


def seed_devices() -> None:
    devices = [
        Device(
            hostname="cairo-core-01",
            management_ip="10.10.0.11",
            vendor=DeviceVendor.NOKIA.value,
            model="7750 SR-1",
            site="Cairo-Core",
            software_version="24.7.R1",
            status=DeviceStatus.ACTIVE.value,
        ),
        Device(
            hostname="alex-edge-01",
            management_ip="10.20.0.11",
            vendor=DeviceVendor.NOKIA.value,
            model="7250 IXR",
            site="Alexandria-Edge",
            software_version="24.7.R1",
            status=DeviceStatus.ACTIVE.value,
        ),
    ]

    with SessionLocal() as database_session:
        for device in devices:
            existing = database_session.scalar(
                select(Device).where(Device.hostname == device.hostname)
            )
            if existing is None:
                database_session.add(device)
        database_session.commit()


if __name__ == "__main__":
    seed_devices()
    print("Seed data inserted successfully.")
