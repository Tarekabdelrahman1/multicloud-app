import asyncio
import json
import logging
from collections.abc import Awaitable, Callable, Iterable
from datetime import UTC, datetime
from typing import Any
from uuid import UUID, uuid4

import aio_pika
from aio_pika import DeliveryMode, ExchangeType, Message
from pydantic import BaseModel, Field

logger = logging.getLogger("platform.events")


class EventEnvelope(BaseModel):
    event_id: UUID = Field(default_factory=uuid4)
    event_type: str
    source: str
    occurred_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    correlation_id: str | None = None
    data: dict[str, Any] = Field(default_factory=dict)


class EventPublisher:
    def __init__(self, rabbitmq_url: str, exchange_name: str = "platform.events") -> None:
        self.rabbitmq_url = rabbitmq_url
        self.exchange_name = exchange_name
        self.connection: aio_pika.RobustConnection | None = None
        self.channel = None
        self.exchange = None

    async def start(self) -> None:
        if self.connection and not self.connection.is_closed:
            return
        self.connection = await aio_pika.connect_robust(self.rabbitmq_url)
        self.channel = await self.connection.channel(publisher_confirms=True)
        self.exchange = await self.channel.declare_exchange(
            self.exchange_name,
            ExchangeType.TOPIC,
            durable=True,
        )

    async def close(self) -> None:
        if self.connection and not self.connection.is_closed:
            await self.connection.close()

    async def publish(self, event: EventEnvelope) -> None:
        if not self.exchange:
            await self.start()
        body = event.model_dump_json().encode("utf-8")
        message = Message(
            body=body,
            content_type="application/json",
            delivery_mode=DeliveryMode.PERSISTENT,
            correlation_id=event.correlation_id,
            message_id=str(event.event_id),
            timestamp=event.occurred_at,
        )
        await self.exchange.publish(message, routing_key=event.event_type)


async def consume_events(
    *,
    rabbitmq_url: str,
    queue_name: str,
    binding_keys: Iterable[str],
    handler: Callable[[EventEnvelope], Awaitable[None]],
    exchange_name: str = "platform.events",
    prefetch_count: int = 10,
) -> None:
    binding_keys = list(binding_keys)
    while True:
        try:
            connection = await aio_pika.connect_robust(rabbitmq_url)
            async with connection:
                channel = await connection.channel()
                await channel.set_qos(prefetch_count=prefetch_count)
                exchange = await channel.declare_exchange(
                    exchange_name, ExchangeType.TOPIC, durable=True
                )
                dlx = await channel.declare_exchange(
                    "platform.dlx", ExchangeType.DIRECT, durable=True
                )
                queue = await channel.declare_queue(
                    queue_name,
                    durable=True,
                    arguments={
                        "x-dead-letter-exchange": "platform.dlx",
                        "x-dead-letter-routing-key": queue_name,
                    },
                )
                dlq = await channel.declare_queue(f"{queue_name}.dlq", durable=True)
                await dlq.bind(dlx, routing_key=queue_name)
                for key in binding_keys:
                    await queue.bind(exchange, routing_key=key)

                logger.info(
                    json.dumps(
                        {
                            "event": "consumer_started",
                            "queue": queue_name,
                            "bindings": binding_keys,
                        }
                    )
                )
                async with queue.iterator() as iterator:
                    async for message in iterator:
                        async with message.process(requeue=False):
                            event = EventEnvelope.model_validate_json(message.body)
                            await handler(event)
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("Consumer failed; retrying in 5 seconds")
            await asyncio.sleep(5)
