"""Run/Cardio Activity tracking models — Strava-like GPS tracked activities"""

from datetime import datetime, date
from typing import Optional, List
from uuid import UUID, uuid4
from sqlalchemy import (
    String, Integer, Text, Boolean, Date, Float,
    DECIMAL, ForeignKey, Index
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID as PGUUID, JSONB, ARRAY
from sqlalchemy.sql import func

from app.core.database import Base


class RunActivity(Base):
    """A GPS-tracked run/walk/ride activity"""

    __tablename__ = "run_activities"
    __table_args__ = (
        Index("ix_run_activities_user_date", "user_id", "started_at"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid4
    )
    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # Activity metadata
    activity_type: Mapped[str] = mapped_column(
        String(50), nullable=False, default="run"
    )  # run, walk, hike, cycle
    title: Mapped[Optional[str]] = mapped_column(String(255))
    description: Mapped[Optional[str]] = mapped_column(Text)

    # Timing
    started_at: Mapped[datetime] = mapped_column(nullable=False)
    finished_at: Mapped[Optional[datetime]]
    duration_seconds: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    moving_time_seconds: Mapped[Optional[int]] = mapped_column(Integer)

    # Distance & pace
    distance_meters: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    avg_pace_seconds_per_km: Mapped[Optional[float]] = mapped_column(Float)
    best_pace_seconds_per_km: Mapped[Optional[float]] = mapped_column(Float)
    avg_speed_kmh: Mapped[Optional[float]] = mapped_column(Float)
    max_speed_kmh: Mapped[Optional[float]] = mapped_column(Float)

    # Elevation
    elevation_gain_meters: Mapped[Optional[float]] = mapped_column(Float)
    elevation_loss_meters: Mapped[Optional[float]] = mapped_column(Float)
    min_elevation_meters: Mapped[Optional[float]] = mapped_column(Float)
    max_elevation_meters: Mapped[Optional[float]] = mapped_column(Float)

    # Calories
    calories_burned: Mapped[Optional[int]] = mapped_column(Integer)

    # Heart rate (if available from wearable)
    avg_heart_rate: Mapped[Optional[int]] = mapped_column(Integer)
    max_heart_rate: Mapped[Optional[int]] = mapped_column(Integer)

    # Cadence (steps per minute)
    avg_cadence: Mapped[Optional[int]] = mapped_column(Integer)

    # Splits (JSON array of per-km split data)
    # Each split: {"km": 1, "duration_seconds": 320, "pace_seconds_per_km": 320, "elevation_delta": 5.2}
    splits: Mapped[Optional[dict]] = mapped_column(JSONB)

    # Route polyline (encoded polyline string for map rendering)
    route_polyline: Mapped[Optional[str]] = mapped_column(Text)

    # Start/end coordinates
    start_lat: Mapped[Optional[float]] = mapped_column(Float)
    start_lng: Mapped[Optional[float]] = mapped_column(Float)
    end_lat: Mapped[Optional[float]] = mapped_column(Float)
    end_lng: Mapped[Optional[float]] = mapped_column(Float)

    # Weather conditions at time of run (optional)
    weather: Mapped[Optional[dict]] = mapped_column(JSONB)

    # Status
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="completed"
    )  # in_progress, completed, discarded

    # AI analysis
    ai_summary: Mapped[Optional[str]] = mapped_column(Text)
    ai_coaching_tips: Mapped[Optional[list]] = mapped_column(JSONB)

    # Source
    source: Mapped[str] = mapped_column(
        String(50), nullable=False, default="app"
    )  # app, garmin, strava_import, apple_health

    # Timestamps
    created_at: Mapped[datetime] = mapped_column(
        nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        nullable=False, server_default=func.now(), onupdate=func.now()
    )

    # Relationships
    user: Mapped["User"] = relationship("User", backref="run_activities")
    route_points: Mapped[List["RoutePoint"]] = relationship(
        "RoutePoint",
        back_populates="activity",
        cascade="all, delete-orphan",
        order_by="RoutePoint.timestamp",
    )


class RoutePoint(Base):
    """Individual GPS point in a run route"""

    __tablename__ = "route_points"
    __table_args__ = (
        Index("ix_route_points_activity", "activity_id", "timestamp"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid4
    )
    activity_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("run_activities.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    altitude_meters: Mapped[Optional[float]] = mapped_column(Float)
    speed_ms: Mapped[Optional[float]] = mapped_column(Float)
    accuracy_meters: Mapped[Optional[float]] = mapped_column(Float)
    timestamp: Mapped[datetime] = mapped_column(nullable=False)

    # Cumulative at this point
    cumulative_distance_meters: Mapped[Optional[float]] = mapped_column(Float)
    cumulative_duration_seconds: Mapped[Optional[float]] = mapped_column(Float)

    # Relationship
    activity: Mapped["RunActivity"] = relationship(
        "RunActivity", back_populates="route_points"
    )
