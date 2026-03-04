"""
Fitness Agent - Generates personalized workout plans
Implements context-aware AI workout planning with hierarchical memory
"""

from typing import Dict, List, Optional
from datetime import datetime, timedelta
from sqlalchemy.ext.asyncio import AsyncSession
from langchain_core.messages import HumanMessage, SystemMessage

from app.models.user import User
from app.models.fitness import FitnessPlan, Workout, Exercise
from app.memory.hierarchical_memory import HierarchicalMemory
from app.tools.fitness_tools import ExerciseDatabase
from app.core.config import settings
from app.core.llm_factory import get_llm, get_fast_llm


class FitnessAgent:
    """
    AI Agent for generating personalized fitness plans
    Uses hierarchical memory for context management
    """

    def __init__(self, db: AsyncSession):
        self.db = db
        self.llm = get_llm()
        self.memory = HierarchicalMemory(db)
        self.exercise_db = ExerciseDatabase()

    async def generate_weekly_plan(
        self,
        user: User,
        start_date: Optional[datetime] = None
    ) -> FitnessPlan:
        """
        Generate a personalized weekly workout plan

        Args:
            user: User object with profile data
            start_date: Week start date (defaults to next Monday)

        Returns:
            FitnessPlan with 7 days of workouts
        """
        if start_date is None:
            start_date = self._get_next_monday()

        # Retrieve user context
        context = await self.memory.get_user_context(
            user_id=user.id,
            context_type="fitness_planning"
        )

        # Generate workouts using AI
        weekly_workouts = await self._generate_weekly_workouts(user, context)

        # Calculate end date
        end_date = start_date + timedelta(days=6)

        # Create FitnessPlan in database (without workouts first)
        workout_plan = FitnessPlan(
            user_id=user.id,
            week_start=start_date,
            week_end=end_date,
            created_by_ai=True,
            ai_model_version=settings.AI_MODEL
        )

        self.db.add(workout_plan)
        await self.db.flush()  # Get plan_id before adding workouts

        # Add workouts with plan_id
        for workout in weekly_workouts:
            workout.plan_id = workout_plan.id
            self.db.add(workout)

        # Note: Commit is handled by the route handler
        # Just flush to ensure we have IDs for relationships
        await self.db.flush()

        # Update episodic memory (will be committed by route handler)
        await self.memory.store_episode(
            user_id=user.id,
            episode_type="workout_plan_generated",
            content={
                "plan_id": str(workout_plan.id),
                "workout_count": len(weekly_workouts),
                "generated_at": datetime.utcnow().isoformat()
            }
        )

        return workout_plan

    async def _generate_weekly_workouts(
        self,
        user: User,
        context: Dict
    ) -> List[Workout]:
        """
        Generate 7 days of workout plans using AI
        """
        system_prompt = self._build_fitness_system_prompt()
        user_prompt = self._build_fitness_user_prompt(user, context)

        # Use fast LLM for workout generation (cheaper and faster)
        fast_llm = get_fast_llm()

        response = await fast_llm.ainvoke([
            SystemMessage(content=system_prompt),
            HumanMessage(content=user_prompt)
        ])

        workouts = await self._parse_workout_response(response.content)
        return workouts

    def _build_fitness_system_prompt(self) -> str:
        """System prompt for fitness agent"""
        import random

        # Randomize workout style focus for variety
        workout_themes = [
            "Push/Pull/Legs split with compound movements",
            "Upper/Lower body split with supersets",
            "Full body workouts with circuit training",
            "Body part split (chest, back, shoulders, legs, arms)",
            "Functional fitness with athletic movements",
            "Strength and conditioning hybrid approach",
        ]
        workout_focus = random.choice(workout_themes)

        # Randomize cardio variety
        cardio_styles = [
            "HIIT intervals with bodyweight exercises",
            "steady-state cardio with incline walking or cycling",
            "metabolic conditioning circuits",
            "plyometric and explosive movements",
        ]
        cardio_focus = random.choice(cardio_styles)

        return f"""You are an expert personal trainer and fitness coach AI.
Your role is to create personalized, safe, and UNIQUE weekly workout plans.

VARIETY IS CRITICAL - This week's theme: {workout_focus}, with {cardio_focus} for cardio days.

Key principles:
- Consider user's fitness level, goals, and available equipment
- Ensure progressive overload and proper recovery
- MAXIMUM VARIETY: Never repeat the same exercise twice in a week
- Different muscle group focus each training day
- Mix compound and isolation exercises
- Vary rep ranges (strength: 4-6, hypertrophy: 8-12, endurance: 15+)
- Include warm-up and cool-down suggestions
- Account for injuries or physical limitations

CRITICAL: You MUST respond with ONLY a valid JSON array, nothing else. No explanations, no code blocks, no markdown.

Response format: Return a JSON array with 7 workouts (one per day). Each workout must include:
- day_of_week: integer 0-6 (0=Monday, 1=Tuesday, 2=Wednesday, 3=Thursday, 4=Friday, 5=Saturday, 6=Sunday)
- name: string (e.g., "Upper Body Strength")
- workout_type: string (e.g., "strength", "cardio", "flexibility", "rest", "mixed")
- duration_minutes: integer
- description: string (brief overview)
- estimated_calories: integer (optional)
- intensity_level: integer 1-5 (optional)
- exercises: array of exercise objects

Each exercise object must include:
- name: string
- description: string
- sets: integer
- reps: string (e.g., "8-10" or "to failure")
- rest_seconds: integer
- muscle_groups: array of strings
- equipment_needed: string or null
- video_url: string (optional)

Example:
[
  {{
    "day_of_week": 0,
    "name": "Upper Body Strength",
    "workout_type": "strength",
    "duration_minutes": 45,
    "description": "Focus on chest, back, and arms",
    "estimated_calories": 300,
    "intensity_level": 4,
    "exercises": [
      {{
        "name": "Bench Press",
        "description": "Lie on bench, lower barbell to chest, press up",
        "sets": 3,
        "reps": "8-10",
        "rest_seconds": 90,
        "muscle_groups": ["chest", "triceps"],
        "equipment_needed": "barbell, bench"
      }}
    ]
  }}
]

Include 1-2 rest days based on intensity and user recovery ability.
Be CREATIVE and DIVERSE with exercise selection!
RESPOND WITH ONLY THE JSON ARRAY."""

    def _build_fitness_user_prompt(
        self,
        user: User,
        context: Dict
    ) -> str:
        """Build user-specific fitness prompt"""
        import random
        from datetime import datetime

        profile = user.profile

        # Add variety hints
        exercise_styles = ["compound lifts", "isolation exercises", "bodyweight movements", "dumbbell exercises", "cable exercises", "kettlebell work"]
        random.shuffle(exercise_styles)
        exercise_hint = ", ".join(exercise_styles[:3])

        # Generate a unique seed based on time for truly different plans
        unique_seed = datetime.now().strftime("%Y%m%d%H%M%S")

        prompt = f"""Generate a UNIQUE 7-day workout plan (seed: {unique_seed}) for this user:

USER PROFILE:
- Age: {profile.age if profile else 'N/A'}
- Gender: {profile.gender if profile else 'N/A'}
- Weight: {float(profile.weight) if profile and profile.weight else 'N/A'} kg
- Height: {float(profile.height) if profile and profile.height else 'N/A'} cm
- Fitness Level: {profile.fitness_experience if profile else 'beginner'}
- Primary Goal: {profile.primary_goal if profile else 'general fitness'}
- Activity Level: {profile.activity_level if profile else 'moderate'}
- Preferred Workout Days/Week: {profile.workout_days_per_week if profile and profile.workout_days_per_week else '4-5'}
- Preferred Workout Duration: {profile.workout_duration if profile and profile.workout_duration else '45-60 min'}
- Preferred Time: {profile.preferred_workout_time if profile and profile.preferred_workout_time else 'flexible'}

VARIETY REQUIREMENTS:
- Include at least 3 different exercise types from: {exercise_hint}
- Each strength day should target different muscle groups
- Mix training intensities throughout the week
- No exercise should be repeated across days
- Schedule REST days based on the user's preferred workout days per week

"""

        if profile and profile.equipment_access:
            prompt += f"AVAILABLE EQUIPMENT: {', '.join(profile.equipment_access)}\n"
        else:
            prompt += "AVAILABLE EQUIPMENT: Full gym access (dumbbells, barbells, machines, cables)\n"

        if profile and profile.fitness_preferences:
            prompt += f"\nFITNESS PREFERENCES: {profile.fitness_preferences}\n"

        # Add context from hierarchical memory for adaptive planning
        episodic = context.get("episodic_memory", {})
        fitness_history = episodic.get("fitness_history", [])
        if fitness_history:
            prompt += f"\nPAST WORKOUT PLANS (adapt and progress from these):\n"
            for hist in fitness_history[:3]:
                prompt += f"  - Week of {hist.get('week_start', 'N/A')}: {hist.get('workout_count', 0)} workouts\n"
            prompt += "Ensure this week's plan builds on previous weeks with progressive overload.\n"

        # Add progress patterns for adaptation
        progress_patterns = episodic.get("progress_patterns", {})
        if progress_patterns:
            consistency = progress_patterns.get("consistency_score", 0)
            if consistency > 0:
                prompt += f"\nUSER ADHERENCE: {consistency:.0f}% consistency. "
                if consistency < 50:
                    prompt += "User struggles with consistency — suggest simpler, shorter workouts.\n"
                elif consistency > 80:
                    prompt += "User is very consistent — can handle challenging progressive plans.\n"

        prompt += "\nGenerate a creative and diverse 7-day workout plan as JSON:"
        return prompt

    async def _parse_workout_response(self, response: str) -> List[Workout]:
        """Parse AI response into Workout objects with nested Exercise objects"""
        import json
        import logging

        logger = logging.getLogger(__name__)
        logger.info(f"Fitness AI Response length: {len(response)} chars")
        logger.debug(f"Full Fitness AI Response: {response}")

        json_str = response.strip()

        # Method 1: Extract from markdown code blocks using index-based approach
        if "```json" in json_str:
            start_marker = "```json"
            start_idx = json_str.find(start_marker) + len(start_marker)
            end_idx = json_str.find("```", start_idx)
            if end_idx > start_idx:
                json_str = json_str[start_idx:end_idx].strip()
                logger.info("Extracted JSON from ```json``` block")
        elif "```" in json_str:
            start_idx = json_str.find("```") + 3
            end_idx = json_str.find("```", start_idx)
            if end_idx > start_idx:
                json_str = json_str[start_idx:end_idx].strip()
                logger.info("Extracted JSON from ``` block")

        # Method 2: Find the JSON array by locating balanced brackets
        if not json_str.startswith('['):
            start_idx = json_str.find('[')
            if start_idx != -1:
                bracket_count = 0
                end_idx = start_idx
                for i, char in enumerate(json_str[start_idx:], start=start_idx):
                    if char == '[':
                        bracket_count += 1
                    elif char == ']':
                        bracket_count -= 1
                        if bracket_count == 0:
                            end_idx = i + 1
                            break
                json_str = json_str[start_idx:end_idx]
                logger.info("Extracted JSON array using bracket matching")

        try:
            workouts_data = json.loads(json_str)
            logger.info(f"Successfully parsed {len(workouts_data)} workouts from AI response")
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse fitness AI response as JSON: {e}")
            logger.error(f"Attempted to parse (first 500 chars): {json_str[:500]}")
            logger.error(f"Original response (first 500 chars): {response[:500]}")
            return self._generate_fallback_workouts()

        workouts = []
        for workout_data in workouts_data:
            # Create workout without exercises first
            workout = Workout(
                day_of_week=workout_data.get("day_of_week", 0),
                name=workout_data.get("name", "Workout"),
                workout_type=workout_data.get("workout_type", "mixed"),
                duration_minutes=workout_data.get("duration_minutes", 30),
                description=workout_data.get("description"),
                estimated_calories=workout_data.get("estimated_calories"),
                intensity_level=workout_data.get("intensity_level")
            )

            # Create exercises (will be added to workout via relationship)
            for idx, ex_data in enumerate(workout_data.get("exercises", [])):
                # Parse reps - handle strings like "8-10" or "to failure"
                reps_str = ex_data.get("reps", "10")
                try:
                    # Try to parse as int, or extract first number from range
                    if isinstance(reps_str, int):
                        reps = reps_str
                    elif "-" in str(reps_str):
                        reps = int(str(reps_str).split("-")[0])
                    else:
                        reps = int(reps_str) if str(reps_str).isdigit() else 10
                except (ValueError, AttributeError):
                    reps = 10

                # Parse equipment - ensure it's a list
                equipment = ex_data.get("equipment_needed")
                if equipment:
                    if isinstance(equipment, str):
                        equipment_list = [e.strip() for e in equipment.split(",")]
                    else:
                        equipment_list = equipment if isinstance(equipment, list) else [str(equipment)]
                else:
                    equipment_list = None

                exercise = Exercise(
                    exercise_order=idx,
                    name=ex_data.get("name", "Exercise"),
                    description=ex_data.get("description"),
                    sets=ex_data.get("sets", 3),
                    reps=reps,
                    rest_time_seconds=ex_data.get("rest_seconds", 60),
                    muscle_groups=ex_data.get("muscle_groups", []),
                    equipment_required=equipment_list,
                    video_url=ex_data.get("video_url")
                )
                workout.exercises.append(exercise)

            workouts.append(workout)

        return workouts

    def _generate_fallback_workouts(self) -> List[Workout]:
        """Generate simple fallback workout plan"""
        workout_templates = [
            {"day": 0, "name": "Upper Body Strength", "type": "strength"},
            {"day": 1, "name": "Cardio & Core", "type": "cardio"},
            {"day": 2, "name": "Lower Body Strength", "type": "strength"},
            {"day": 3, "name": "Active Recovery", "type": "flexibility"},
            {"day": 4, "name": "Full Body Workout", "type": "mixed"},
            {"day": 5, "name": "Cardio Intervals", "type": "cardio"},
            {"day": 6, "name": "Rest Day", "type": "rest"}
        ]

        workouts = []
        for template in workout_templates:
            workout = Workout(
                day_of_week=template["day"],
                name=template["name"],
                workout_type=template["type"],
                duration_minutes=30 if template["type"] != "rest" else 0,
                description=f"{template['name']} workout"
            )

            # Add basic exercise for non-rest days
            if template["type"] != "rest":
                exercise = Exercise(
                    exercise_order=0,
                    name="Basic Exercise",
                    description="Perform as directed",
                    sets=3,
                    reps=10,
                    rest_time_seconds=60,
                    muscle_groups=["full_body"]
                )
                workout.exercises.append(exercise)

            workouts.append(workout)

        return workouts

    def _get_next_monday(self) -> datetime:
        """Get the next Monday's date"""
        today = datetime.now().date()
        days_ahead = 0 - today.weekday()
        if days_ahead <= 0:
            days_ahead += 7
        return datetime.combine(today + timedelta(days=days_ahead), datetime.min.time())
