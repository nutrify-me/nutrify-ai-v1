from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from typing import List
from datetime import datetime, timedelta

from app.core.database import get_db
from app.core.cache import cache_response, invalidate_cache
from app.api.dependencies import get_current_user
from app.models.user import User
from app.models.progress import ProgressEntry
from app.schemas.progress import (
    ProgressEntryResponse,
    ProgressEntryCreate,
)

router = APIRouter()


@router.get("", response_model=List[ProgressEntryResponse])
async def get_progress_history(
    days: int = Query(None, ge=1, le=365),
    limit: int = Query(None, ge=1, le=365),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get user's progress history for the specified number of days or limit"""
    query = select(ProgressEntry).where(ProgressEntry.user_id == current_user.id)

    if days is not None:
        start_date = datetime.now().date() - timedelta(days=days)
        query = query.where(ProgressEntry.entry_date >= start_date)

    query = query.order_by(desc(ProgressEntry.entry_date))

    if limit is not None:
        query = query.limit(limit)
    elif days is None:
        # Default to 30 if neither days nor limit is specified
        start_date = datetime.now().date() - timedelta(days=30)
        query = query.where(ProgressEntry.entry_date >= start_date)

    result = await db.execute(query)
    entries = result.scalars().all()

    return entries


@router.post("", response_model=ProgressEntryResponse)
async def log_progress(
    progress_data: ProgressEntryCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Log a new progress entry"""
    # Check if entry already exists for today
    entry_date = progress_data.entry_date or datetime.now().date()
    result = await db.execute(
        select(ProgressEntry).where(
            ProgressEntry.user_id == current_user.id,
            ProgressEntry.entry_date == entry_date
        )
    )
    existing_entry = result.scalar_one_or_none()

    if existing_entry:
        # Update existing entry
        update_data = progress_data.model_dump(exclude_unset=True)
        for field, value in update_data.items():
            if field == "entry_date" and value is not None:
                existing_entry.entry_date = value
            elif field == "weight" and value is not None:
                existing_entry.weight = value
            elif field == "body_fat_percentage" and value is not None:
                existing_entry.body_fat_percentage = value
            elif field == "muscle_mass" and value is not None:
                existing_entry.muscle_mass = value
            elif field == "measurements" and value is not None:
                existing_entry.measurements = value
            elif field == "mood_score" and value is not None:
                existing_entry.mood_score = value
            elif field == "energy_score" and value is not None:
                existing_entry.energy_score = value
            elif field == "stress_score" and value is not None:
                existing_entry.stress_score = value
            elif field == "sleep_hours" and value is not None:
                existing_entry.sleep_hours = value
            elif field == "sleep_quality" and value is not None:
                existing_entry.sleep_quality = value
            elif field == "water_intake_ml" and value is not None:
                existing_entry.water_intake_ml = value
            elif field == "adherence_score" and value is not None:
                existing_entry.adherence_score = value
            elif field == "notes" and value is not None:
                existing_entry.notes = value
            elif field == "photos" and value is not None:
                existing_entry.photos = value

        entry = existing_entry
    else:
        # Create new entry
        entry = ProgressEntry(
            user_id=current_user.id,
            entry_date=entry_date,
            weight=progress_data.weight,
            body_fat_percentage=progress_data.body_fat_percentage,
            muscle_mass=progress_data.muscle_mass,
            measurements=progress_data.measurements,
            mood_score=progress_data.mood_score,
            energy_score=progress_data.energy_score,
            stress_score=progress_data.stress_score,
            sleep_hours=progress_data.sleep_hours,
            sleep_quality=progress_data.sleep_quality,
            water_intake_ml=progress_data.water_intake_ml,
            adherence_score=progress_data.adherence_score,
            notes=progress_data.notes,
            photos=progress_data.photos,
        )
        db.add(entry)

    await db.commit()
    await db.refresh(entry)

    return entry


@router.put("/{entry_id}", response_model=ProgressEntryResponse)
async def update_progress_entry(
    entry_id: int,
    progress_data: ProgressEntryCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Update a specific progress entry by ID"""
    result = await db.execute(
        select(ProgressEntry).where(
            ProgressEntry.id == entry_id,
            ProgressEntry.user_id == current_user.id
        )
    )
    entry = result.scalar_one_or_none()

    if not entry:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Progress entry not found"
        )

    # Update entry fields
    update_data = progress_data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        if hasattr(entry, field) and value is not None:
            setattr(entry, field, value)

    await db.commit()
    await db.refresh(entry)

    return entry


@router.delete("/{entry_id}")
async def delete_progress_entry(
    entry_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Delete a specific progress entry by ID"""
    result = await db.execute(
        select(ProgressEntry).where(
            ProgressEntry.id == entry_id,
            ProgressEntry.user_id == current_user.id
        )
    )
    entry = result.scalar_one_or_none()

    if not entry:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Progress entry not found"
        )

    await db.delete(entry)
    await db.commit()

    return {"message": "Progress entry deleted successfully"}
