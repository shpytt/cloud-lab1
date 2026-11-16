import json
import logging

import redis

from . import cache

log = logging.getLogger("idempotency")

RESULT_TTL_SECONDS = 24 * 3600
PENDING_TTL_SECONDS = 60
PENDING = "PENDING"


def begin(key: str) -> tuple[str, dict | None]:
    client = cache.client
    if client is None:
        return "new", None
    try:
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
    client = cache.client
    if client is None:
        return
    try:
        client.delete(key)
    except redis.RedisError:
        pass
