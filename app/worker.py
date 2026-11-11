"""Обробник черги: окремий контейнер (той самий образ, команда `python -m app.worker`).

Читає повідомлення із SQS і записує показники в базу. SQS гарантує доставку
"щонайменше один раз", тому те саме повідомлення може прийти двічі:
від повторного запису захищає позначка processed:<request_id> у Redis.
"""
import json
import logging
import os
import signal
import time

import boto3

from . import cache, jobs, models
from .database import SessionLocal

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("worker")

# Штучна затримка імітує тривалу обробку (щоб черга росла під навантаженням)
DELAY_SECONDS = float(os.getenv("WORKER_DELAY_MS", "0")) / 1000
PROCESSED_TTL_SECONDS = 24 * 3600

running = True


def stop(signum, frame):
    """Graceful shutdown: на SIGTERM дообробляємо поточну пачку і виходимо."""
    global running
    log.info("SIGTERM received, finishing current batch")
    running = False


def already_processed(request_id: str) -> bool:
    return cache.client is not None and cache.client.get(f"processed:{request_id}") is not None


def mark_processed(request_id: str) -> None:
    if cache.client is not None:
        cache.client.set(f"processed:{request_id}", "1", ex=PROCESSED_TTL_SECONDS)


def process(message: dict) -> None:
    request_id = message["request_id"]

    if already_processed(request_id):
        log.info("Duplicate delivery of %s, skipping", request_id)
        return

    time.sleep(DELAY_SECONDS)

    with SessionLocal() as db:
        if db.get(models.Device, message["device_id"]) is None:
            mark_processed(request_id)
            jobs.set_status(
                request_id,
                {"request_id": request_id, "status": "failed", "error": "Device not found"},
            )
            return

        reading = models.Reading(
            device_id=message["device_id"],
            temperature=message["temperature"],
            humidity=message.get("humidity"),
        )
        db.add(reading)
        db.commit()
        db.refresh(reading)
        result = {
            "id": reading.id,
            "device_id": reading.device_id,
            "temperature": reading.temperature,
            "humidity": reading.humidity,
            "created_at": reading.created_at.isoformat(),
        }

    mark_processed(request_id)
    jobs.set_status(request_id, {"request_id": request_id, "status": "done", "reading": result})


def main() -> None:
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    sqs = boto3.client("sqs", region_name=jobs.AWS_REGION)
    log.info("Worker started, queue: %s", jobs.QUEUE_URL)

    while running:
        # Long polling: чекаємо повідомлення до 20 с замість постійних порожніх запитів
        response = sqs.receive_message(
            QueueUrl=jobs.QUEUE_URL,
            MaxNumberOfMessages=10,
            WaitTimeSeconds=20,
        )
        for msg in response.get("Messages", []):
            try:
                process(json.loads(msg["Body"]))
            except Exception:
                # Не видаляємо: після visibility timeout SQS віддасть повідомлення ще раз
                log.exception("Failed to process message %s", msg.get("MessageId"))
                continue
            # Видаляємо лише після успішної обробки
            sqs.delete_message(QueueUrl=jobs.QUEUE_URL, ReceiptHandle=msg["ReceiptHandle"])

    log.info("Worker stopped")


if __name__ == "__main__":
    main()
