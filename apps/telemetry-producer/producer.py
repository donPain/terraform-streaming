import json
import logging
import os
import random
import signal
import time
from datetime import datetime, timezone

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
running = True


def generate_event(malformed=False):
    event = {
        "machineId": f"tractor-{random.randint(1, 5):03d}",
        "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "latitude": round(-21.20 + random.uniform(-0.05, 0.05), 6),
        "longitude": round(-50.43 + random.uniform(-0.05, 0.05), 6),
        "speed": round(random.uniform(0, 25), 1),
        "temperature": round(random.uniform(70, 105), 1),
        "fuelLevel": round(random.uniform(5, 100), 1),
    }
    if malformed:
        event.pop("machineId")
    return event


def stop(_signum, _frame):
    global running
    running = False


def delivery_report(error, message):
    if error:
        logging.error("delivery failed: %s", error)
    else:
        logging.info("delivered partition=%s offset=%s", message.partition(), message.offset())


def main():
    from confluent_kafka import Producer

    bootstrap = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
    topic = os.getenv("KAFKA_TOPIC", "machine.telemetry.raw")
    rate = float(os.getenv("EVENTS_PER_SECOND", "2"))
    malformed_percent = float(os.getenv("MALFORMED_PERCENT", "0.02"))
    if rate <= 0 or not 0 <= malformed_percent <= 1:
        raise ValueError("EVENTS_PER_SECOND must be > 0 and MALFORMED_PERCENT must be between 0 and 1")

    producer = Producer({"bootstrap.servers": bootstrap, "client.id": "telemetry-producer"})
    logging.info("producing topic=%s brokers=%s rate=%s/s", topic, bootstrap, rate)

    while running:
        payload = json.dumps(generate_event(random.random() < malformed_percent))
        producer.poll(0)
        try:
            producer.produce(topic, payload.encode(), callback=delivery_report)
        except BufferError:
            producer.poll(1)
            continue
        time.sleep(1 / rate)

    producer.flush(10)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    main()
