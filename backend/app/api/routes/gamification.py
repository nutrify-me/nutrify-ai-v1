"""Gamification API routes for streaks and achievements"""

from datetime import date, datetime, timedelta
from typing import List, Optional
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.dependencies import get_current_user
from app.core.database import get_db
from app.core.cache import cache_response
from app.models.user import User
from app.models.gamification import UserStreak, Achievement, UserAchievement
from app.models.workout_session import WorkoutSession, PersonalRecord
from app.schemas.gamification import (
    StreakResponse,
    AchievementResponse,
    UserAchievementResponse,
    AchievementProgressResponse,
    GamificationStatsResponse,
    NewAchievementNotification,
)

router = APIRouter()

DAY_NAMES = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]


def _bitmask_to_days(bitmask: int) -> List[str]:
    """Convert bitmask to list of day names"""
    days = []
    for i, day in enumerate(DAY_NAMES):
        if bitmask & (1 << i):
            days.append(day)
    return days


def _get_monday_of_week(d: date) -> date:
    """Get the Monday of the week containing the given date"""
    return d - timedelta(days=d.weekday())


async def _get_or_create_streak(db: AsyncSession, user_id) -> UserStreak:
    """Get or create user streak record"""
    result = await db.execute(
        select(UserStreak).where(UserStreak.user_id == user_id)
    )
    streak = result.scalar_one_or_none()

    if not streak:
        streak = UserStreak(
            id=uuid4(),
            user_id=user_id,
            current_streak=0,
            longest_streak=0,
            total_workouts=0,
            total_workout_minutes=0,
            current_week_workouts=0,
        )
        db.add(streak)
        await db.flush()

    return streak


async def _check_and_award_achievements(
    db: AsyncSession,
    user_id,
    streak: UserStreak,
) -> List[Achievement]:
    """Check and award any new achievements the user has earned"""
    awarded = []

    # Get all achievements
    result = await db.execute(select(Achievement).where(Achievement.is_active == True))
    all_achievements = result.scalars().all()

    # Get user's earned achievements
    result = await db.execute(
        select(UserAchievement.achievement_id).where(UserAchievement.user_id == user_id)
    )
    earned_ids = set(row[0] for row in result.all())

    # Get user stats for checking
    # Count PRs
    result = await db.execute(
        select(func.count(PersonalRecord.id)).where(PersonalRecord.user_id == user_id)
    )
    pr_count = result.scalar() or 0

    # Calculate total volume from completed sessions
    result = await db.execute(
        select(func.sum(WorkoutSession.total_volume)).where(
            WorkoutSession.user_id == user_id,
            WorkoutSession.status == "completed"
        )
    )
    total_volume = result.scalar() or 0

    for achievement in all_achievements:
        if achievement.id in earned_ids:
            continue

        earned = False
        context = {}

        if achievement.requirement_type == "workout_count":
            if streak.total_workouts >= achievement.requirement_value:
                earned = True
                context = {"total_workouts": streak.total_workouts}

        elif achievement.requirement_type == "streak":
            # Check both current and longest streak
            max_streak = max(streak.current_streak, streak.longest_streak)
            if max_streak >= achievement.requirement_value:
                earned = True
                context = {"streak": max_streak}

        elif achievement.requirement_type == "pr_count":
            if pr_count >= achievement.requirement_value:
                earned = True
                context = {"pr_count": pr_count}

        elif achievement.requirement_type == "total_volume":
            if total_volume >= achievement.requirement_value:
                earned = True
                context = {"total_volume": total_volume}

        elif achievement.requirement_type == "perfect_week":
            # Check if all 7 days of the week are set (bitmask = 127)
            if streak.current_week_workouts == 127:
                earned = True
                context = {"week_start": str(streak.week_start_date)}

        if earned:
            user_achievement = UserAchievement(
                id=uuid4(),
                user_id=user_id,
                achievement_id=achievement.id,
                context=context,
                notified=False,
            )
            db.add(user_achievement)
            awarded.append(achievement)

    if awarded:
        await db.flush()

    return awarded


async def update_streak_on_workout(
    db: AsyncSession,
    user_id,
    workout_duration_minutes: int = 0,
) -> tuple[UserStreak, List[Achievement]]:
    """
    Update user's streak when they complete a workout.
    Returns the updated streak and any newly awarded achievements.
    """
    streak = await _get_or_create_streak(db, user_id)
    today = date.today()
    monday = _get_monday_of_week(today)

    # Check if this is a new week
    if streak.week_start_date != monday:
        streak.week_start_date = monday
        streak.current_week_workouts = 0

    # Update weekly bitmask
    day_bit = 1 << today.weekday()
    streak.current_week_workouts |= day_bit

    # Update streak
    if streak.last_workout_date is None:
        # First workout ever
        streak.current_streak = 1
        streak.streak_start_date = today
    elif streak.last_workout_date == today:
        # Already worked out today, don't change streak
        pass
    elif streak.last_workout_date == today - timedelta(days=1):
        # Consecutive day - increment streak
        streak.current_streak += 1
    else:
        # Streak broken - start new streak
        streak.current_streak = 1
        streak.streak_start_date = today

    # Update longest streak
    if streak.current_streak > streak.longest_streak:
        streak.longest_streak = streak.current_streak

    # Update totals
    streak.total_workouts += 1
    streak.total_workout_minutes += workout_duration_minutes
    streak.last_workout_date = today

    await db.flush()

    # Check for new achievements
    new_achievements = await _check_and_award_achievements(db, user_id, streak)

    return streak, new_achievements


@router.get("/streak", response_model=StreakResponse)
async def get_user_streak(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get current user's streak information"""
    streak = await _get_or_create_streak(db, current_user.id)
    await db.commit()

    # Check if streak should be reset (missed a day)
    today = date.today()
    if streak.last_workout_date and streak.last_workout_date < today - timedelta(days=1):
        # Streak is broken but we don't reset it here - that happens on next workout
        pass

    return StreakResponse(
        current_streak=streak.current_streak,
        longest_streak=streak.longest_streak,
        last_workout_date=streak.last_workout_date,
        streak_start_date=streak.streak_start_date,
        total_workouts=streak.total_workouts,
        total_workout_minutes=streak.total_workout_minutes,
        current_week_workouts=streak.current_week_workouts,
        week_workout_days=_bitmask_to_days(streak.current_week_workouts),
    )


@router.get("/achievements", response_model=List[AchievementProgressResponse])
async def get_achievements_with_progress(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get all achievements with user's progress"""
    # Get all achievements
    result = await db.execute(
        select(Achievement).where(Achievement.is_active == True).order_by(Achievement.sort_order)
    )
    all_achievements = result.scalars().all()

    # Get user's earned achievements with eager loading
    result = await db.execute(
        select(UserAchievement)
        .options(selectinload(UserAchievement.achievement))
        .where(UserAchievement.user_id == current_user.id)
    )
    earned = result.scalars().all()
    earned_map = {ua.achievement_id: ua for ua in earned}

    # Get user stats
    streak = await _get_or_create_streak(db, current_user.id)

    result = await db.execute(
        select(func.count(PersonalRecord.id)).where(PersonalRecord.user_id == current_user.id)
    )
    pr_count = result.scalar() or 0

    result = await db.execute(
        select(func.sum(WorkoutSession.total_volume)).where(
            WorkoutSession.user_id == current_user.id,
            WorkoutSession.status == "completed"
        )
    )
    total_volume = result.scalar() or 0

    await db.commit()

    # Build response
    response = []
    for achievement in all_achievements:
        earned = achievement.id in earned_map
        earned_at = earned_map[achievement.id].earned_at if earned else None

        # Calculate progress
        current_progress = 0
        if achievement.requirement_type == "workout_count":
            current_progress = streak.total_workouts
        elif achievement.requirement_type == "streak":
            current_progress = max(streak.current_streak, streak.longest_streak)
        elif achievement.requirement_type == "pr_count":
            current_progress = pr_count
        elif achievement.requirement_type == "total_volume":
            current_progress = total_volume
        elif achievement.requirement_type == "perfect_week":
            # Count bits set in the bitmask
            current_progress = bin(streak.current_week_workouts).count('1')

        progress_pct = min(100.0, (current_progress / achievement.requirement_value) * 100)

        response.append(AchievementProgressResponse(
            achievement=AchievementResponse.model_validate(achievement),
            earned=earned,
            earned_at=earned_at,
            current_progress=current_progress,
            progress_percentage=progress_pct,
        ))

    return response


@router.get("/achievements/earned", response_model=List[UserAchievementResponse])
async def get_earned_achievements(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get user's earned achievements"""
    result = await db.execute(
        select(UserAchievement)
        .options(selectinload(UserAchievement.achievement))
        .where(UserAchievement.user_id == current_user.id)
        .order_by(UserAchievement.earned_at.desc())
    )
    earned = result.scalars().all()

    return [
        UserAchievementResponse(
            id=ua.id,
            achievement_id=ua.achievement_id,
            earned_at=ua.earned_at,
            context=ua.context,
            notified=ua.notified,
            achievement=AchievementResponse.model_validate(ua.achievement),
        )
        for ua in earned
    ]


@router.get("/achievements/unnotified", response_model=List[NewAchievementNotification])
async def get_unnotified_achievements(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get achievements that haven't been shown to the user yet"""
    result = await db.execute(
        select(UserAchievement)
        .options(selectinload(UserAchievement.achievement))
        .where(
            UserAchievement.user_id == current_user.id,
            UserAchievement.notified == False
        )
        .order_by(UserAchievement.earned_at.asc())
    )
    unnotified = result.scalars().all()

    # Mark as notified
    for ua in unnotified:
        ua.notified = True

    await db.commit()

    return [
        NewAchievementNotification(
            achievement=AchievementResponse.model_validate(ua.achievement),
            earned_at=ua.earned_at,
            context=ua.context,
        )
        for ua in unnotified
    ]


@router.get("/stats", response_model=GamificationStatsResponse)
async def get_gamification_stats(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get complete gamification stats for dashboard"""
    # Get streak
    streak = await _get_or_create_streak(db, current_user.id)

    # Get total achievements count
    result = await db.execute(
        select(func.count(Achievement.id)).where(Achievement.is_active == True)
    )
    total_achievements = result.scalar() or 0

    # Get earned achievements with points
    result = await db.execute(
        select(UserAchievement)
        .options(selectinload(UserAchievement.achievement))
        .where(UserAchievement.user_id == current_user.id)
        .order_by(UserAchievement.earned_at.desc())
    )
    earned = result.scalars().all()

    total_points = sum(ua.achievement.points for ua in earned)
    recent = earned[:5]  # Last 5 achievements

    await db.commit()

    return GamificationStatsResponse(
        streak=StreakResponse(
            current_streak=streak.current_streak,
            longest_streak=streak.longest_streak,
            last_workout_date=streak.last_workout_date,
            streak_start_date=streak.streak_start_date,
            total_workouts=streak.total_workouts,
            total_workout_minutes=streak.total_workout_minutes,
            current_week_workouts=streak.current_week_workouts,
            week_workout_days=_bitmask_to_days(streak.current_week_workouts),
        ),
        total_points=total_points,
        achievements_earned=len(earned),
        achievements_total=total_achievements,
        recent_achievements=[
            UserAchievementResponse(
                id=ua.id,
                achievement_id=ua.achievement_id,
                earned_at=ua.earned_at,
                context=ua.context,
                notified=ua.notified,
                achievement=AchievementResponse.model_validate(ua.achievement),
            )
            for ua in recent
        ],
    )
