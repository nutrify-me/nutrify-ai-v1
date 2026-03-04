"""Run activity Pydantic schemas"""

from typing import Optional, List, Dict, Any
from uuid import UUID
from datetime import datetime
from pydantic import BaseModel, Field


# ---------- Route Points ----------

class RoutePointCreate(BaseModel):
    latitude: float
    longitude: float
    altitude_meters: Optional[float] = None
    speed_ms: Optional[float] = None
    accuracy_meters: Optional[float] = None
    timestamp: datetime
    cumulative_distance_meters: Optional[float] = None
    cumulative_duration_seconds: Optional[float] = None


class RoutePointResponse(RoutePointCreate):
    id: UUID
    activity_id: UUID

    class Config:
        from_attributes = True


# ---------- Run Activity ----------

class RunActivityCreate(BaseModel):
    """Schema for saving a completed run"""
    activity_type: str = Field(default="run", pattern="^(run|walk|hike|cycle)$")
    title: Optional[str] = None
    description: Optional[str] = None

    started_at: datetime
    finished_at: Optional[datetime] = None
    duration_seconds: int = Field(..., ge=0)
    moving_time_seconds: Optional[int] = Field(None, ge=0)

    distance_meters: float = Field(..., ge=0)
    avg_pace_seconds_per_km: Optional[float] = None
    best_pace_seconds_per_km: Optional[float] = None
    avg_speed_kmh: Optional[float] = None
    max_speed_kmh: Optional[float] = None

    elevation_gain_meters: Optional[float] = None
    elevation_loss_meters: Optional[float] = None
    min_elevation_meters: Optional[float] = None
    max_elevation_meters: Optional[float] = None

    calories_burned: Optional[int] = None
    avg_heart_rate: Optional[int] = None
    max_heart_rate: Optional[int] = None
    avg_cadence: Optional[int] = None

    splits: Optional[List[Dict[str, Any]]] = None
    route_polyline: Optional[str] = None

    start_lat: Optional[float] = None
    start_lng: Optional[float] = None
    end_lat: Optional[float] = None
    end_lng: Optional[float] = None

    weather: Optional[Dict[str, Any]] = None

    # Route points (optional — can be sent separately for large routes)
    route_points: Optional[List[RoutePointCreate]] = None


class RunActivityResponse(BaseModel):
    id: UUID
    user_id: UUID
    activity_type: str
    title: Optional[str]
    description: Optional[str]

    started_at: datetime
    finished_at: Optional[datetime]
    duration_seconds: int
    moving_time_seconds: Optional[int]

    distance_meters: float
    avg_pace_seconds_per_km: Optional[float]
    best_pace_seconds_per_km: Optional[float]
    avg_speed_kmh: Optional[float]
    max_speed_kmh: Optional[float]

    elevation_gain_meters: Optional[float]
    elevation_loss_meters: Optional[float]

    calories_burned: Optional[int]
    avg_heart_rate: Optional[int]
    max_heart_rate: Optional[int]
    avg_cadence: Optional[int]

    splits: Optional[List[Dict[str, Any]]]
    route_polyline: Optional[str]

    start_lat: Optional[float]
    start_lng: Optional[float]
    end_lat: Optional[float]
    end_lng: Optional[float]

    weather: Optional[Dict[str, Any]]
    status: str

    ai_summary: Optional[str]
    ai_coaching_tips: Optional[List[str]]

    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class RunActivitySummary(BaseModel):
    """Lightweight response for list views"""
    id: UUID
    activity_type: str
    title: Optional[str]
    started_at: datetime
    duration_seconds: int
    distance_meters: float
    avg_pace_seconds_per_km: Optional[float]
    calories_burned: Optional[int]
    elevation_gain_meters: Optional[float]
    status: str

    class Config:
        from_attributes = True


# ---------- Stats ----------

class RunStats(BaseModel):
    """Aggregate run statistics for a user"""
    total_runs: int = 0
    total_distance_km: float = 0.0
    total_duration_minutes: float = 0.0
    total_calories: int = 0
    total_elevation_gain_m: float = 0.0

    avg_pace_seconds_per_km: Optional[float] = None
    best_pace_seconds_per_km: Optional[float] = None
    longest_run_km: float = 0.0
    longest_run_duration_minutes: float = 0.0

    runs_this_week: int = 0
    distance_this_week_km: float = 0.0
    runs_this_month: int = 0
    distance_this_month_km: float = 0.0


class RunActivityUpdate(BaseModel):
    """Schema for updating a run (title, description, etc.)"""
    title: Optional[str] = None
    description: Optional[str] = None
    activity_type: Optional[str] = Field(None, pattern="^(run|walk|hike|cycle)$")
