"""Run activity tracking API routes — Strava-like GPS run tracking"""

from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc, func, and_, extract
from typing import List, Optional
from datetime import datetime, timedelta
from uuid import UUID

from app.core.database import get_db
from app.core.cache import cache_response, invalidate_cache
from app.api.dependencies import get_current_user
from app.models.user import User
from app.models.run_activity import RunActivity, RoutePoint
from app.schemas.run_activity import (
    RunActivityCreate,
    RunActivityResponse,
    RunActivitySummary,
    RunActivityUpdate,
    RunStats,
    RoutePointResponse,
)

router = APIRouter()


# ──────────────────────────────────────────
#  CREATE — Save a completed run
# ──────────────────────────────────────────

@router.post("", response_model=RunActivityResponse, status_code=status.HTTP_201_CREATED)
async def create_run_activity(
    payload: RunActivityCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Save a completed GPS-tracked run activity"""

    # Auto-generate title if not provided
    title = payload.title
    if not title:
        hour = payload.started_at.hour
        if hour < 6:
            period = "Early Morning"
        elif hour < 12:
            period = "Morning"
        elif hour < 17:
            period = "Afternoon"
        elif hour < 21:
            period = "Evening"
        else:
            period = "Night"
        type_label = payload.activity_type.capitalize()
        title = f"{period} {type_label}"

    # Calculate calories if not provided (rough MET-based estimate)
    calories = payload.calories_burned
    if not calories and payload.distance_meters > 0:
        # Running MET ≈ 9.8, Walking ≈ 3.8, Cycling ≈ 7.5
        met_values = {"run": 9.8, "walk": 3.8, "hike": 6.0, "cycle": 7.5}
        met = met_values.get(payload.activity_type, 8.0)
        weight_kg = 70.0  # TODO: pull from user profile
        if current_user.profile and current_user.profile.weight:
            weight_kg = float(current_user.profile.weight)
        duration_hours = payload.duration_seconds / 3600
        calories = int(met * weight_kg * duration_hours)

    activity = RunActivity(
        user_id=current_user.id,
        activity_type=payload.activity_type,
        title=title,
        description=payload.description,
        started_at=payload.started_at,
        finished_at=payload.finished_at,
        duration_seconds=payload.duration_seconds,
        moving_time_seconds=payload.moving_time_seconds,
        distance_meters=payload.distance_meters,
        avg_pace_seconds_per_km=payload.avg_pace_seconds_per_km,
        best_pace_seconds_per_km=payload.best_pace_seconds_per_km,
        avg_speed_kmh=payload.avg_speed_kmh,
        max_speed_kmh=payload.max_speed_kmh,
        elevation_gain_meters=payload.elevation_gain_meters,
        elevation_loss_meters=payload.elevation_loss_meters,
        min_elevation_meters=payload.min_elevation_meters,
        max_elevation_meters=payload.max_elevation_meters,
        calories_burned=calories,
        avg_heart_rate=payload.avg_heart_rate,
        max_heart_rate=payload.max_heart_rate,
        avg_cadence=payload.avg_cadence,
        splits=payload.splits,
        route_polyline=payload.route_polyline,
        start_lat=payload.start_lat,
        start_lng=payload.start_lng,
        end_lat=payload.end_lat,
        end_lng=payload.end_lng,
        weather=payload.weather,
        status="completed",
    )

    db.add(activity)
    await db.flush()

    # Save route points if provided
    if payload.route_points:
        for pt in payload.route_points:
            route_point = RoutePoint(
                activity_id=activity.id,
                latitude=pt.latitude,
                longitude=pt.longitude,
                altitude_meters=pt.altitude_meters,
                speed_ms=pt.speed_ms,
                accuracy_meters=pt.accuracy_meters,
                timestamp=pt.timestamp,
                cumulative_distance_meters=pt.cumulative_distance_meters,
                cumulative_duration_seconds=pt.cumulative_duration_seconds,
            )
            db.add(route_point)

    await db.commit()
    await db.refresh(activity)

    return activity


# ──────────────────────────────────────────
#  READ — List runs / single run / route
# ──────────────────────────────────────────

@router.get("", response_model=List[RunActivitySummary])
async def list_run_activities(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    activity_type: Optional[str] = Query(None, pattern="^(run|walk|hike|cycle)$"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List user's run activities (most recent first)"""
    query = (
        select(RunActivity)
        .where(
            RunActivity.user_id == current_user.id,
            RunActivity.status == "completed",
        )
        .order_by(desc(RunActivity.started_at))
        .offset(offset)
        .limit(limit)
    )

    if activity_type:
        query = query.where(RunActivity.activity_type == activity_type)

    result = await db.execute(query)
    return result.scalars().all()


@router.get("/stats", response_model=RunStats)
async def get_run_stats(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get aggregate run statistics for the user"""
    base_filter = and_(
        RunActivity.user_id == current_user.id,
        RunActivity.status == "completed",
    )

    # All-time stats
    result = await db.execute(
        select(
            func.count(RunActivity.id).label("total_runs"),
            func.coalesce(func.sum(RunActivity.distance_meters), 0).label("total_distance"),
            func.coalesce(func.sum(RunActivity.duration_seconds), 0).label("total_duration"),
            func.coalesce(func.sum(RunActivity.calories_burned), 0).label("total_calories"),
            func.coalesce(func.sum(RunActivity.elevation_gain_meters), 0).label("total_elevation"),
            func.avg(RunActivity.avg_pace_seconds_per_km).label("avg_pace"),
            func.min(RunActivity.best_pace_seconds_per_km).label("best_pace"),
            func.max(RunActivity.distance_meters).label("longest_distance"),
            func.max(RunActivity.duration_seconds).label("longest_duration"),
        ).where(base_filter)
    )
    row = result.one()

    # This week
    week_start = datetime.utcnow() - timedelta(days=datetime.utcnow().weekday())
    week_start = week_start.replace(hour=0, minute=0, second=0, microsecond=0)
    week_result = await db.execute(
        select(
            func.count(RunActivity.id),
            func.coalesce(func.sum(RunActivity.distance_meters), 0),
        ).where(base_filter, RunActivity.started_at >= week_start)
    )
    week_row = week_result.one()

    # This month
    month_start = datetime.utcnow().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    month_result = await db.execute(
        select(
            func.count(RunActivity.id),
            func.coalesce(func.sum(RunActivity.distance_meters), 0),
        ).where(base_filter, RunActivity.started_at >= month_start)
    )
    month_row = month_result.one()

    return RunStats(
        total_runs=row.total_runs or 0,
        total_distance_km=round((row.total_distance or 0) / 1000, 2),
        total_duration_minutes=round((row.total_duration or 0) / 60, 1),
        total_calories=row.total_calories or 0,
        total_elevation_gain_m=round(row.total_elevation or 0, 1),
        avg_pace_seconds_per_km=round(row.avg_pace, 1) if row.avg_pace else None,
        best_pace_seconds_per_km=round(row.best_pace, 1) if row.best_pace else None,
        longest_run_km=round((row.longest_distance or 0) / 1000, 2),
        longest_run_duration_minutes=round((row.longest_duration or 0) / 60, 1),
        runs_this_week=week_row[0] or 0,
        distance_this_week_km=round((week_row[1] or 0) / 1000, 2),
        runs_this_month=month_row[0] or 0,
        distance_this_month_km=round((month_row[1] or 0) / 1000, 2),
    )


@router.get("/{activity_id}", response_model=RunActivityResponse)
async def get_run_activity(
    activity_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get a single run activity with full details"""
    result = await db.execute(
        select(RunActivity).where(
            RunActivity.id == activity_id,
            RunActivity.user_id == current_user.id,
        )
    )
    activity = result.scalar_one_or_none()
    if not activity:
        raise HTTPException(status_code=404, detail="Run activity not found")
    return activity


@router.get("/{activity_id}/route", response_model=List[RoutePointResponse])
async def get_run_route(
    activity_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get the GPS route points for a run activity"""
    # Verify ownership
    activity = await db.execute(
        select(RunActivity.id).where(
            RunActivity.id == activity_id,
            RunActivity.user_id == current_user.id,
        )
    )
    if not activity.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Run activity not found")

    result = await db.execute(
        select(RoutePoint)
        .where(RoutePoint.activity_id == activity_id)
        .order_by(RoutePoint.timestamp)
    )
    return result.scalars().all()


# ──────────────────────────────────────────
#  UPDATE / DELETE
# ──────────────────────────────────────────

@router.put("/{activity_id}", response_model=RunActivityResponse)
async def update_run_activity(
    activity_id: UUID,
    payload: RunActivityUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update run activity metadata (title, description)"""
    result = await db.execute(
        select(RunActivity).where(
            RunActivity.id == activity_id,
            RunActivity.user_id == current_user.id,
        )
    )
    activity = result.scalar_one_or_none()
    if not activity:
        raise HTTPException(status_code=404, detail="Run activity not found")

    update_data = payload.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(activity, field, value)

    await db.commit()
    await db.refresh(activity)
    return activity


@router.delete("/{activity_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_run_activity(
    activity_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete a run activity"""
    result = await db.execute(
        select(RunActivity).where(
            RunActivity.id == activity_id,
            RunActivity.user_id == current_user.id,
        )
    )
    activity = result.scalar_one_or_none()
    if not activity:
        raise HTTPException(status_code=404, detail="Run activity not found")

    await db.delete(activity)
    await db.commit()
