"""Асинхронний запис через чергу SQS: API кладе повідомлення, обробник (worker) виконує."""
import json
import logging
import os

import boto3
import redis

from . import cache

log = logging.getLogger("jobs")

ASYNC_WRITES = os.getenv("ASYNC_WRITES", "false").lower() == "true"
QUEUE_URL = os.getenv("SQS_QUEUE_URL", "")
AWS_REGION = os.getenv("AWS_REGION", "eu-north-1")
JOB_TTL_SECONDS = 3600  # скільки зберігаємо статус запиту для клієнта

sqs = boto3.client("sqs", region_name=AWS_REGION) if QUEUE_URL else None


def job_key(request_id: str) -> str:
    return f"job:{request_id}"


def set_status(request_id: str, payload: dict) -> None:
    if cache.client is None:
        return
    try:
        cache.client.set(job_key(request_id), json.dumps(payload), ex=JOB_TTL_SECONDS)
    except redis.RedisError as exc:
        log.warning("Could not store job status: %s", exc)


def get_status(request_id: str) -> dict | None:
    if cache.client is None:
        return None
    try:
        value = cache.client.get(job_key(request_id))
    except redis.RedisError:
        return None
    return json.loads(value) if value else None


def enqueue_reading(request_id: str, device_id: int, data: dict) -> None:
    # Статус "queued" ставимо ДО відправлення: інакше швидкий обробник
    # міг би записати "done" раніше, і ми перезаписали б його на "queued".
    set_status(request_id, {"request_id": request_id, "status": "queued"})
    sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(
            {"request_id": request_id, "device_id": device_id, **data}
        ),
    )
