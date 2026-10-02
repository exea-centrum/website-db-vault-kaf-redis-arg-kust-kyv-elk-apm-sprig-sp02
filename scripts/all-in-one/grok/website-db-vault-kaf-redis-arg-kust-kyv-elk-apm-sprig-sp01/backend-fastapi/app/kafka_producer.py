import json
import os
from confluent_kafka import Producer

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9092")
_producer = None


def get_producer():
    global _producer
    if _producer is None:
        # ISTIO: mTLS realizuje Envoy sidecar – aplikacja łączy się PLAINTEXT
        # do kafka-kraft:9092. Nie montujemy certów, nie konfigurujemy SSL.
        _producer = Producer({
            "bootstrap.servers": KAFKA_BOOTSTRAP,
        })
    return _producer


def publish_event(topic: str, event: dict):
    producer = get_producer()
    producer.produce(topic, json.dumps(event).encode("utf-8"))
    producer.flush(5)
