"""Кеш Redis для схеми cache-aside.

Redis спільний для всіх екземплярів API, тому кожен екземпляр бачить
однакові дані. Якщо Redis недоступний, функції тихо повертають None:
сервіс продовжує працювати, просто читає з бази.
"""
import logging
import os

import redis

log = logging.getLogger("cache")

REDIS_URL = os.getenv("REDIS_URL", "")
CACHE_ENABLED = os.getenv("CACHE_ENABLED", "false").lower() == "true"
CACHE_TTL_SECONDS = int(os.getenv("CACHE_TTL_SECONDS", "30"))

DEVICES_LIST_KEY = "devices:all"

# Короткі тайм-аути: якщо Redis не відповідає, не блокуємо запит надовго
client = (
    redis.Redis.from_url(
        REDIS_URL,
        decode_responses=True,
        socket_connect_timeout=0.5,
        socket_timeout=0.5,
    )
    if REDIS_URL
    else None
)


def device_key(device_id: int) -> str:
    return f"device:{device_id}"


def enabled() -> bool:
    return CACHE_ENABLED and client is not None


def miss_label() -> str:
    """Значення заголовка X-Cache, коли дані взято з бази."""
    return "MISS" if enabled() else "DISABLED"


def get_cached(key: str) -> str | None:
    if not enabled():
        return None
    try:
        return client.get(key)
    except redis.RedisError as exc:
        log.warning("Cache read failed: %s", exc)
        return None


def put(key: str, value: str) -> None:
    if not enabled():
        return
    try:
        client.set(key, value, ex=CACHE_TTL_SECONDS)  # ex = термін дії (TTL), с
    except redis.RedisError as exc:
        log.warning("Cache write failed: %s", exc)


def invalidate(*keys: str) -> None:
    """Видаляє записи з кешу після зміни даних у базі."""
    if not enabled():
        return
    try:
        client.delete(*keys)
    except redis.RedisError as exc:
        log.warning("Cache invalidation failed: %s", exc)


def stats() -> dict:
    """Лічильники влучань і промахів, які веде сам Redis (спільні для всіх екземплярів)."""
    result = {
        "enabled": CACHE_ENABLED,
        "ttl_seconds": CACHE_TTL_SECONDS,
        "redis_available": False,
    }
    if client is None:
        return result
    try:
        info = client.info("stats")
    except redis.RedisError:
        return result
    hits = info.get("keyspace_hits", 0)
    misses = info.get("keyspace_misses", 0)
    total = hits + misses
    result.update(
        redis_available=True,
        hits=hits,
        misses=misses,
        hit_rate=round(hits / total, 4) if total else None,
    )
    return result
