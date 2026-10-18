import logging
import time
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from . import models, schemas
from .database import Base, engine, get_db

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("api")

APP_VERSION = "1.0.0"


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


app = FastAPI(title="IoT Devices API", version=APP_VERSION, lifespan=lifespan)


def get_device_or_404(device_id: int, db: Session) -> models.Device:
    device = db.get(models.Device, device_id)
    if device is None:
        raise HTTPException(status_code=404, detail="Device not found")
    return device


@app.get("/")
def root():
    return {"service": "IoT Devices API", "version": APP_VERSION}


@app.get("/health")
def health():
    return {"status": "ok"}


# ---------- Devices ----------

@app.get("/devices", response_model=list[schemas.DeviceOut])
def list_devices(db: Session = Depends(get_db)):
    return db.scalars(select(models.Device).order_by(models.Device.id)).all()


@app.post("/devices", response_model=schemas.DeviceOut, status_code=status.HTTP_201_CREATED)
def create_device(data: schemas.DeviceCreate, db: Session = Depends(get_db)):
    device = models.Device(**data.model_dump())
    db.add(device)
    db.commit()
    db.refresh(device)
    return device


@app.get("/devices/{device_id}", response_model=schemas.DeviceOut)
def get_device(device_id: int, db: Session = Depends(get_db)):
    return get_device_or_404(device_id, db)


@app.patch("/devices/{device_id}", response_model=schemas.DeviceOut)
def update_device(device_id: int, data: schemas.DeviceUpdate, db: Session = Depends(get_db)):
    device = get_device_or_404(device_id, db)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(device, field, value)
    db.commit()
    db.refresh(device)
    return device


@app.delete("/devices/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_device(device_id: int, db: Session = Depends(get_db)):
    device = get_device_or_404(device_id, db)
    db.delete(device)
    db.commit()


# ---------- Readings ----------

@app.post(
    "/devices/{device_id}/readings",
    response_model=schemas.ReadingOut,
    status_code=status.HTTP_201_CREATED,
)
def add_reading(device_id: int, data: schemas.ReadingCreate, db: Session = Depends(get_db)):
    get_device_or_404(device_id, db)
    reading = models.Reading(device_id=device_id, **data.model_dump())
    db.add(reading)
    db.commit()
    db.refresh(reading)
    return reading


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