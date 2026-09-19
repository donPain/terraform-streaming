import logging
import os
import signal

from confluent_kafka import Consumer, KafkaError


logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
running = True


def stop(_signum, _frame):
    global running
    running = False


def main():
    bootstrap = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
    topic = os.getenv("KAFKA_TOPIC", "machine.telemetry.enriched")
    consumer = Consumer(
        {
            "bootstrap.servers": bootstrap,
            "group.id": os.getenv("KAFKA_GROUP_ID", "telemetry-learning-consumer"),
            "auto.offset.reset": "earliest",
            "enable.auto.commit": False,
        }
    )
    consumer.subscribe([topic])
    logging.info("consuming topic=%s brokers=%s", topic, bootstrap)

    try:
        while running:
            message = consumer.poll(1)
            if message is None:
                continue
            if message.error():
                if message.error().code() != KafkaError._PARTITION_EOF:
                    logging.error("consumer error: %s", message.error())
                continue
            print(message.value().decode(), flush=True)
            consumer.commit(message=message, asynchronous=False)
    finally:
        consumer.close()


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    main()
