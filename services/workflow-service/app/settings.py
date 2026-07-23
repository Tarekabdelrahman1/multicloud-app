from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(case_sensitive=False)
    service_name: str = "workflow-service"
    database_url: str = "postgresql+psycopg://platform:platform_password@postgres:5432/workflow_db"
    rabbitmq_url: str = "amqp://platform:platform_password@rabbitmq:5672/"
    execution_mode: str = "mock"


settings = Settings()
