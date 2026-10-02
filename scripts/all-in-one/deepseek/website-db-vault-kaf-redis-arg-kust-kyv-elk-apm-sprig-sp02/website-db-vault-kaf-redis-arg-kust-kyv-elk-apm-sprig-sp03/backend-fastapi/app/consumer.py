"""
message-processor: osobny deployment/consumer.
Czyta z tematow Kafka 'bookings-created' i 'marketing-actions',
wysyla e-mail (potwierdzenie + faktura proforma) i aktualizuje status w Postgresql.
Kolejka Redis sluzy do deduplikacji/idempotencji przetwarzania.
"""
import json
import os

import redis
from confluent_kafka import Consumer

from .db import SessionLocal, Booking
from .email_sender import send_confirmation_email, send_marketing_email

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9092")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))

redis_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


def handle_booking_event(event: dict):
    dedup_key = f"processed:{event.get('event_id', event.get('booking_id', 'unknown'))}"
    if redis_client.get(dedup_key):
        return
    send_confirmation_email(event.get("email", event.get("guest_email")), event.get("guest_name", "Gosc"), event)

    session = SessionLocal()
    try:
        booking = session.query(Booking).get(event.get("booking_id"))
        if booking:
            booking.status = "confirmed"
            booking.invoice_sent = True
            session.commit()
    finally:
        session.close()

    redis_client.setex(dedup_key, 86400, "1")


def handle_marketing_event(event: dict):
    send_marketing_email(event.get("guest_email", event.get("email")), event.get("guest_name", "Gosc"))


def main():
    consumer = Consumer({
        "bootstrap.servers": KAFKA_BOOTSTRAP,
        "group.id": "message-processor",
        "auto.offset.reset": "earliest",
    })
    consumer.subscribe(["bookings-created", "marketing-actions"])
    print("message-processor: nasluchiwanie na bookings-created i marketing-actions...")
    try:
        while True:
            msg = consumer.poll(1.0)
            if msg is None:
                continue
            if msg.error():
                print("Kafka error:", msg.error())
                continue
            event = json.loads(msg.value().decode("utf-8"))
            if msg.topic() == "bookings-created":
                handle_booking_event(event)
            elif msg.topic() == "marketing-actions":
                handle_marketing_event(event)
    except KeyboardInterrupt:
        pass
    finally:
        consumer.close()


if __name__ == "__main__":
    main()
