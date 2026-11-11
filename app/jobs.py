"""Асинхронний запис через чергу SQS: API кладе повідомлення, обробник (worker) виконує.

Повідомлення відправляються в SQS не по одному, а пачками до 10 штук із фонового
потоку: окремий підписаний HTTPS-виклик на кожен запит коштував API більше
процесорного часу, ніж сам запис у базу (див. docs/QUEUE.md).
"""
import json
import logging
import os
import queue
import threading
import time

import boto3
import redis

from . import cache

log = logging.getLogger("jobs")

ASYNC_WRITES = os.getenv("ASYNC_WRITES", "false").lower() == "true"
QUEUE_URL = os.getenv("SQS_QUEUE_URL", "")
AWS_REGION = os.getenv("AWS_REGION", "eu-north-1")
JOB_TTL_SECONDS = 3600  # скільки зберігаємо статус запиту для клієнта

BATCH_SIZE = 10        # максимум повідомлень в одному SendMessageBatch (обмеження SQS)
LINGER_SECONDS = 0.05  # скільки чекаємо, щоб набрати пачку

sqs = boto3.client("sqs", region_name=AWS_REGION) if QUEUE_URL else None

_buffer: queue.Queue = queue.Queue()
_sender: threading.Thread | None = None
_STOP = object()


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


def _send_batch(batch: list[dict]) -> None:
    entries = [{"Id": str(i), "MessageBody": json.dumps(m)} for i, m in enumerate(batch)]
    try:
        response = sqs.send_message_batch(QueueUrl=QUEUE_URL, Entries=entries)
        failed = [batch[int(item["Id"])] for item in response.get("Failed", [])]
    except Exception:
        log.exception("SQS batch send failed")
        failed = batch
    for message in failed:
        set_status(
            message["request_id"],
            {"request_id": message["request_id"], "status": "failed", "error": "Could not enqueue"},
        )


def _sender_loop() -> None:
    """Фоновий потік: збирає повідомлення з буфера в пачки і відправляє в SQS."""
    stopping = False
    while not stopping:
        first = _buffer.get()
        if first is _STOP:
            break
        batch = [first]
        deadline = time.monotonic() + LINGER_SECONDS
        while len(batch) < BATCH_SIZE:
            timeout = deadline - time.monotonic()
            if timeout <= 0:
                break
            try:
                item = _buffer.get(timeout=timeout)
            except queue.Empty:
                break
            if item is _STOP:
                stopping = True
                break
            batch.append(item)
        _send_batch(batch)


def start_sender() -> None:
    global _sender
    if ASYNC_WRITES and sqs is not None and _sender is None:
        _sender = threading.Thread(target=_sender_loop, name="sqs-sender", daemon=True)
        _sender.start()


def shutdown() -> None:
    """Graceful shutdown: перед зупинкою контейнера відправляємо все, що лишилось у буфері."""
    if _sender is not None:
        _buffer.put(_STOP)
        _sender.join(timeout=10)


def enqueue_reading(request_id: str, device_id: int, data: dict) -> None:
    # Статус "queued" ставимо ДО відправлення: інакше швидкий обробник
    # міг би записати "done" раніше, і ми перезаписали б його на "queued".
    set_status(request_id, {"request_id": request_id, "status": "queued"})
    _buffer.put({"request_id": request_id, "device_id": device_id, **data})


start_sender()
