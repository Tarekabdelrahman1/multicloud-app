from enum import Enum


class DeviceVendor(str, Enum):
    NOKIA = "nokia"
    CISCO = "cisco"
    JUNIPER = "juniper"
    HUAWEI = "huawei"
    ARISTA = "arista"
    OTHER = "other"


class DeviceStatus(str, Enum):
    ACTIVE = "active"
    INACTIVE = "inactive"
    MAINTENANCE = "maintenance"
    UNREACHABLE = "unreachable"
    UNKNOWN = "unknown"
