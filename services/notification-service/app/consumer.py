import asyncio
import json
import logging

from sqlalchemy import select
from common.events import EventEnvelope, consume_events
from common.http import configure_logging
from .domain import Base, Notification, SessionLocal, engine, settings

configure_logging()
logger = logging.getLogger(settings.service_name + ".consumer")


def store_notification(event: EventEnvelope) -> None:
    with SessionLocal() as db:
        if db.scalar(select(Notification).where(Notification.source_event_id == event.event_id)):
            return
        if event.event_type == "workflow.completed":
            subject = "Workflow completed"
            body = f"Workflow {event.data.get('name') or event.data.get('id')} completed successfully."
        elif event.event_type == "workflow.failed":
            subject = "Workflow failed"
            body = f"Workflow {event.data.get('name') or event.data.get('id')} failed: {event.data.get('error_message')}"
        else:
            subject = "Inventory low stock"
            body = (
                f"{event.data.get('name')} at {event.data.get('location')} has quantity "
                f"{event.data.get('quantity')} (threshold {event.data.get('low_stock_threshold')})."
            )
        db.add(
            Notification(
                channel="console",
                recipient="operations",
                subject=subject,
                body=body,
                status="sent",
                source_event_type=event.event_type,
                source_event_id=event.event_id,
                payload=event.data,
            )
        )
        db.commit()
        logger.info(json.dumps({"event": "notification_sent", "subject": subject}))


async def main() -> None:
    Base.metadata.create_all(engine)

    async def handler(event: EventEnvelope) -> None:
        await asyncio.to_thread(store_notification, event)

    await consume_events(
        rabbitmq_url=settings.rabbitmq_url,
        queue_name="notification.events",
        binding_keys=["workflow.completed", "workflow.failed", "inventory.low_stock"],
        handler=handler,
    )


if __name__ == "__main__":
    asyncio.run(main())
