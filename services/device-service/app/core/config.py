from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    service_name: str = "device-service"
    service_version: str = "1.0.0"
    environment: Literal["development", "test", "staging", "production"] = "development"

    host: str = "0.0.0.0"
    port: int = 8080
    api_v1_prefix: str = "/api/v1"

    docs_enabled: bool = True
    log_level: str = "INFO"

    database_url: str = (
        "postgresql+psycopg://device_user:device_password"
        "@localhost:5432/device_db"
    )
    database_pool_size: int = 5
    database_max_overflow: int = 10

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
