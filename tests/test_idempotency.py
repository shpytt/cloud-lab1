#!/usr/bin/env python3
"""Тест ідемпотентності: два однакові запити -> один запис у базі, дві однакові відповіді.

Запуск:  python3 tests/test_idempotency.py http://<адреса-сервісу>
Працює і в синхронному режимі (201), і з чергою (202).
"""
import json
import sys
import time
import urllib.request
import uuid

BASE = sys.argv[1].rstrip("/")


def call(method, path, body=None, headers=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path,
        data=data,
        method=method,
        headers={"Content-Type": "application/json", **(headers or {})},
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        raw = resp.read()
        return resp.status, (json.loads(raw) if raw else None), resp.headers


def count_readings(device_id):
    return len(call("GET", f"/devices/{device_id}/readings?limit=500")[1])


def wait_done(body):
    """У режимі черги чекаємо, поки обробник виконає запис."""
    for _ in range(60):
        job = call("GET", body["status_url"])[1]
        if job["status"] != "queued":
            return job
        time.sleep(1)
    raise AssertionError("обробник не виконав запит за 60 с")


_, device, _ = call("POST", "/devices", {"name": "idempotency-test", "location": "test"})
dev = device["id"]
print(f"Створено тестовий пристрій id={dev}, показників: {count_readings(dev)}")

payload = {"temperature": 21.5, "humidity": 40.0}
key = str(uuid.uuid4())
headers = {"Idempotency-Key": key}

s1, b1, h1 = call("POST", f"/devices/{dev}/readings", payload, headers)
s2, b2, h2 = call("POST", f"/devices/{dev}/readings", payload, headers)
print(f"Запит 1: {s1} {b1}")
print(f"Запит 2: {s2} {b2}  Idempotency-Replayed={h2.get('Idempotency-Replayed')}")

assert s1 == s2, "коди відповідей різні"
assert b1 == b2, "тіла відповідей різні"
assert h1.get("Idempotency-Replayed") is None, "перший запит не мав бути повтором"
assert h2.get("Idempotency-Replayed") == "true", "другий запит мав бути повтором"

if s1 == 202:
    print(f"Режим черги, результат: {wait_done(b1)}")

n = count_readings(dev)
print(f"Показників у базі після двох однакових запитів: {n}")
assert n == 1, f"очікували 1 запис, а їх {n}"

s3, b3, _ = call("POST", f"/devices/{dev}/readings", payload, {"Idempotency-Key": str(uuid.uuid4())})
if s3 == 202:
    wait_done(b3)
n = count_readings(dev)
print(f"Після запиту з ІНШИМ ключем: {n}")
assert n == 2, f"очікували 2 записи, а їх {n}"

call("DELETE", f"/devices/{dev}")
print("OK: два однакові запити -> один запис у базі, дві однакові відповіді")
