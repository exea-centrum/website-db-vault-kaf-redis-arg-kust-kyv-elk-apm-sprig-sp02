import json
import os
from confluent_kafka import Producer

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9094")
_producer = None


def get_producer():
    global _producer
    if _producer is None:
        _producer = Producer({
            "bootstrap.servers": KAFKA_BOOTSTRAP,
            "security.protocol": "SSL",
            "ssl.ca.location": os.getenv("KAFKA_CA_FILE", "/etc/kafka-tls/ca.crt"),
            "ssl.certificate.location": os.getenv("KAFKA_TLS_CERT_FILE", "/etc/kafka-tls/tls.crt"),
            "ssl.key.location": os.getenv("KAFKA_TLS_KEY_FILE", "/etc/kafka-tls/tls.key"),
            "ssl.endpoint.identification.algorithm": "https",
        })
    return _producer


def publish_event(topic: str, event: dict):
    producer = get_producer()
    producer.produce(topic, json.dumps(event).encode("utf-8"))
    producer.flush(5)
