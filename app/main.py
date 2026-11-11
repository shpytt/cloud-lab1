import json
import logging
import time
import uuid
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Response, status
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from . import cache, idempotency, jobs, models, schemas
from .database import Base, engine, get_db

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("api")

APP_VERSION = "1.3.1"


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Чекаємо базу і створюємо таблиці, якщо їх ще немає
    for attempt in range(1, 11):
        try:
            Base.metadata.create_all(bind=engine)
            log.info("Database is ready")
            break
        except OperationalError:
            log.warning("Database not ready (attempt %d/10), retrying...", attempt)
            time.sleep(3)
    else:
        raise RuntimeError("Could not connect to the database")
    yield
    # Зупинка (SIGTERM): відправляємо в SQS усе, що лишилось у буфері
    jobs.shutdown()


app = FastAPI(title="IoT Devices API", version=APP_VERSION, lifespan=lifespan)


def get_device_or_404(device_id: int, db: Session) -> models.Device:
    device = db.get(models.Device, device_id)
    if device is None:
        raise HTTPException(status_code=404, detail="Device not found")
    return device


def json_response(body: str, cache_status: str) -> Response:
    """Готовий JSON + заголовок X-Cache: HIT / MISS / DISABLED."""
    return Response(
        content=body,
        media_type="application/json",
        headers={"X-Cache": cache_status},
    )


@app.get("/")
def root():
    return {"service": "IoT Devices API", "version": APP_VERSION}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/cache/stats")
def cache_stats():
    return cache.stats()


# ---------- Devices ----------

@app.get("/devices", response_model=list[schemas.DeviceOut])
def list_devices(db: Session = Depends(get_db)):
    # Cache-aside, крок 1: перевіряємо кеш
    cached = cache.get_cached(cache.DEVICES_LIST_KEY)
    if cached is not None:
        return json_response(cached, "HIT")  # до бази не звертаємося взагалі

    # Крок 2: у кеші немає (або сплив TTL) - читаємо з бази
    devices = db.scalars(select(models.Device).order_by(models.Device.id)).all()
    body = json.dumps(
        [schemas.DeviceOut.model_validate(d).model_dump(mode="json") for d in devices]
    )

    # Крок 3: кладемо в кеш із терміном дії і повертаємо
    cache.put(cache.DEVICES_LIST_KEY, body)
    return json_response(body, cache.miss_label())


@app.post("/devices", response_model=schemas.DeviceOut, status_code=status.HTTP_201_CREATED)
def create_device(data: schemas.DeviceCreate, db: Session = Depends(get_db)):
    device = models.Device(**data.model_dump())
    db.add(device)
    db.commit()
    db.refresh(device)
    cache.invalidate(cache.DEVICES_LIST_KEY)  # список змінився
    return device


@app.get("/devices/{device_id}", response_model=schemas.DeviceOut)
def get_device(device_id: int, db: Session = Depends(get_db)):
    key = cache.device_key(device_id)
    cached = cache.get_cached(key)
    if cached is not None:
        return json_response(cached, "HIT")

    device = get_device_or_404(device_id, db)
    body = schemas.DeviceOut.model_validate(device).model_dump_json()
    cache.put(key, body)
    return json_response(body, cache.miss_label())


@app.patch("/devices/{device_id}", response_model=schemas.DeviceOut)
def update_device(device_id: int, data: schemas.DeviceUpdate, db: Session = Depends(get_db)):
    device = get_device_or_404(device_id, db)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(device, field, value)
    db.commit()
    db.refresh(device)
    # Інвалідація: після запису в базу видаляємо застарілі записи з кешу
    cache.invalidate(cache.DEVICES_LIST_KEY, cache.device_key(device_id))
    return device


@app.delete("/devices/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_device(device_id: int, db: Session = Depends(get_db)):
    device = get_device_or_404(device_id, db)
    db.delete(device)
    db.commit()
    cache.invalidate(cache.DEVICES_LIST_KEY, cache.device_key(device_id))


# ---------- Readings ----------

def create_reading_now(device_id: int, data: schemas.ReadingCreate, db: Session) -> tuple[int, dict]:
    """Синхронний запис: одразу в базу, відповідь 201."""
    get_device_or_404(device_id, db)
    reading = models.Reading(device_id=device_id, **data.model_dump())
    db.add(reading)
    db.commit()
    db.refresh(reading)
    return 201, schemas.ReadingOut.model_validate(reading).model_dump(mode="json")


def enqueue_reading(device_id: int, data: schemas.ReadingCreate) -> tuple[int, dict]:
    """Асинхронний запис: кладемо в чергу, відповідь 202. До бази не звертаємося."""
    request_id = str(uuid.uuid4())
    jobs.enqueue_reading(request_id, device_id, data.model_dump())
    return 202, {
        "request_id": request_id,
        "status": "queued",
        "status_url": f"/readings/requests/{request_id}",
    }


@app.post(
    "/devices/{device_id}/readings",
    response_model=schemas.ReadingOut,
    status_code=status.HTTP_201_CREATED,
    responses={202: {"model": schemas.ReadingAccepted}},
)
def add_reading(
    device_id: int,
    data: schemas.ReadingCreate,
    idempotency_key: str | None = Header(default=None, max_length=200),
    db: Session = Depends(get_db),
):
    # --- Ідемпотентність: перевіряємо, чи не бачили вже цей ключ ---
    idem_key = None
    if idempotency_key:
        idem_key = f"idem:reading:{device_id}:{idempotency_key}"
        state, saved = idempotency.begin(idem_key)
        if state == "replay":
            # Повтор: віддаємо збережену відповідь, операцію НЕ виконуємо
            return JSONResponse(
                status_code=saved["status"],
                content=saved["body"],
                headers={"Idempotency-Replayed": "true"},
            )
        if state == "in_progress":
            raise HTTPException(
                status_code=409,
                detail="A request with this Idempotency-Key is still being processed",
            )

    # --- Сама операція: через чергу або напряму ---
    try:
        if jobs.ASYNC_WRITES:
            status_code, body = enqueue_reading(device_id, data)
        else:
            status_code, body = create_reading_now(device_id, data, db)
    except Exception:
        if idem_key:
            idempotency.abort(idem_key)  # помилка: дозволяємо повторити з тим самим ключем
        raise

    if idem_key:
        idempotency.complete(idem_key, status_code, body)  # зберігаємо на 24 години
    return JSONResponse(status_code=status_code, content=body)


@app.get("/readings/requests/{request_id}")
def reading_request_status(request_id: str):
    """Як клієнт дізнається результат асинхронного запису: queued / done / failed."""
    job = jobs.get_status(request_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Request not found")
    return job


@app.get("/devices/{device_id}/readings", response_model=list[schemas.ReadingOut])
def list_readings(
    device_id: int,
    limit: int = Query(default=50, ge=1, le=500),
    db: Session = Depends(get_db),
):
    get_device_or_404(device_id, db)
    stmt = (
        select(models.Reading)
        .where(models.Reading.device_id == device_id)
        .order_by(models.Reading.created_at.desc())
        .limit(limit)
    )
    return db.scalars(stmt).all()
