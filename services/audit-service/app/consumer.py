import asyncio

from sqlalchemy import select
from common.events import EventEnvelope, consume_events
from common.http import configure_logging
from .domain import AuditEvent, Base, SessionLocal, engine, settings

configure_logging()


def store_event(event: EventEnvelope) -> None:
    with SessionLocal() as db:
        if db.scalar(select(AuditEvent).where(AuditEvent.event_id == event.event_id)):
            return
        db.add(
            AuditEvent(
                event_id=event.event_id,
                event_type=event.event_type,
                source=event.source,
                correlation_id=event.correlation_id,
                occurred_at=event.occurred_at,
                payload=event.data,
            )
        )
        db.commit()


async def main() -> None:
    Base.metadata.create_all(engine)

    async def handler(event: EventEnvelope) -> None:
        await asyncio.to_thread(store_event, event)

    await consume_events(
        rabbitmq_url=settings.rabbitmq_url,
        queue_name="audit.all-events",
        binding_keys=["#"],
        handler=handler,
        prefetch_count=20,
    )


if __name__ == "__main__":
    asyncio.run(main())
