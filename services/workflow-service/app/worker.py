import asyncio
import logging
import time
from typing import Any
from uuid import UUID

from common.events import EventEnvelope, EventPublisher, consume_events
from common.http import configure_logging
from .domain import Base, SessionLocal, Workflow, engine
from .settings import settings

configure_logging()
logger = logging.getLogger(settings.service_name + ".worker")


def execute_workflow(action: str, parameters: dict[str, Any]) -> dict[str, Any]:
    if settings.execution_mode != "mock":
        raise RuntimeError(
            "Real execution is disabled until an approved Nokia/NSP adapter exists."
        )
    time.sleep(1)
    if action.startswith("fail_"):
        raise RuntimeError("Mock failure requested by action name")
    return {
        "mode": "mock",
        "action": action,
        "parameters_received": parameters,
        "message": "Workflow simulated; no device was changed.",
    }


def mark_running(workflow_id: UUID) -> tuple[str, dict[str, Any]]:
    with SessionLocal() as db:
        workflow = db.get(Workflow, workflow_id)
        if not workflow:
            raise RuntimeError(f"Workflow {workflow_id} does not exist")
        workflow.state = "running"
        db.commit()
        return workflow.action, workflow.parameters


def mark_finished(workflow_id: UUID, result: dict | None, error: str | None) -> dict:
    with SessionLocal() as db:
        workflow = db.get(Workflow, workflow_id)
        if not workflow:
            raise RuntimeError(f"Workflow {workflow_id} does not exist")
        workflow.state = "failed" if error else "completed"
        workflow.result = result
        workflow.error_message = error
        db.commit()
        db.refresh(workflow)
        return {
            "id": str(workflow.id),
            "name": workflow.name,
            "device_id": str(workflow.device_id) if workflow.device_id else None,
            "action": workflow.action,
            "state": workflow.state,
            "result": workflow.result,
            "error_message": workflow.error_message,
        }


async def main() -> None:
    Base.metadata.create_all(engine)
    publisher = EventPublisher(settings.rabbitmq_url)
    await publisher.start()

    async def handler(event: EventEnvelope) -> None:
        workflow_id = UUID(str(event.data["id"]))
        action, parameters = await asyncio.to_thread(mark_running, workflow_id)
        try:
            result = await asyncio.to_thread(execute_workflow, action, parameters)
            snapshot = await asyncio.to_thread(mark_finished, workflow_id, result, None)
            event_type = "workflow.completed"
        except Exception as exc:
            logger.exception("Workflow execution failed")
            snapshot = await asyncio.to_thread(mark_finished, workflow_id, None, str(exc))
            event_type = "workflow.failed"
        await publisher.publish(
            EventEnvelope(
                event_type=event_type,
                source=settings.service_name + ".worker",
                correlation_id=event.correlation_id,
                data=snapshot,
            )
        )

    try:
        await consume_events(
            rabbitmq_url=settings.rabbitmq_url,
            queue_name="workflow.executor",
            binding_keys=["workflow.execute"],
            handler=handler,
            prefetch_count=1,
        )
    finally:
        await publisher.close()


if __name__ == "__main__":
    asyncio.run(main())
