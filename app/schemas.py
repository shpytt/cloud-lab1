from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class DeviceCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    location: str | None = Field(default=None, max_length=200)


class DeviceUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    location: str | None = Field(default=None, max_length=200)


class DeviceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    location: str | None
    created_at: datetime


class ReadingCreate(BaseModel):
    temperature: float
    humidity: float | None = Field(default=None, ge=0, le=100)


class ReadingOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    device_id: int
    temperature: float
    humidity: float | None
    created_at: datetime