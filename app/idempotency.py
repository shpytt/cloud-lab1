"""Ідемпотентність операцій запису за заголовком Idempotency-Key.

Перший запит із ключем виконується, його відповідь зберігається в Redis на 24 години.
Повторний запит із тим самим ключем отримує збережену відповідь без повторного виконання.
"""
import json
import logging

import redis

from . import cache

log = logging.getLogger("idempotency")

RESULT_TTL_SECONDS = 24 * 3600  # скільки пам'ятаємо результат
PENDING_TTL_SECONDS = 60        # скільки тримаємо позначку "запит ще виконується"
PENDING = "PENDING"


def begin(key: str) -> tuple[str, dict | None]:
    """Повертає ("new", None), ("in_progress", None) або ("replay", збережена_відповідь)."""
    client = cache.client
    if client is None:
        return "new", None
    try:
        # SET NX: атомарно займаємо ключ, лише якщо його ще немає.
        # Захищає від двох однакових запитів, що прийшли одночасно на різні екземпляри.
        if client.set(key, PENDING, nx=True, ex=PENDING_TTL_SECONDS):
            return "new", None
        value = client.get(key)
    except redis.RedisError as exc:
        log.warning("Idempotency check failed, executing without it: %s", exc)
        return "new", None

    if value is None:
        return "new", None
    if value == PENDING:
        return "in_progress", None
    return "replay", json.loads(value)


def complete(key: str, status_code: int, body: dict) -> None:
    """Зберігає відповідь першого запиту на 24 години."""
    client = cache.client
    if client is None:
        return
    try:
        client.set(
            key,
            json.dumps({"status": status_code, "body": body}),
            ex=RESULT_TTL_SECONDS,
        )
    except redis.RedisError as exc:
        log.warning("Could not store idempotent result: %s", exc)


def abort(key: str) -> None:
    """Запит завершився помилкою: звільняємо ключ, щоб клієнт міг повторити."""
    client = cache.client
    if client is None:
        return
    try:
        client.delete(key)
    except redis.RedisError:
        pass
