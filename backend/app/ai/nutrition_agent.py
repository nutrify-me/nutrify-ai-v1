"""
Nutrition Agent - Generates personalized meal plans
Implements context-aware AI meal planning with hierarchical memory
"""

from typing import Dict, List, Optional
from datetime import datetime, timedelta
from sqlalchemy.ext.asyncio import AsyncSession
from langchain_core.messages import HumanMessage, SystemMessage

from app.models.user import User
from app.models.nutrition import NutritionPlan, Meal
from app.memory.hierarchical_memory import HierarchicalMemory
from app.tools.nutrition_tools import NutritionDatabase
from app.core.config import settings
from app.core.llm_factory import get_llm, get_fast_llm


class NutritionAgent:
    """
    AI Agent for generating personalized nutrition plans
    Uses hierarchical memory for context management and cost optimization
    """

    def __init__(self, db: AsyncSession):
        self.db = db
        self.llm = get_llm()
        self.memory = HierarchicalMemory(db)
        self.nutrition_db = NutritionDatabase()

    async def generate_weekly_plan(
        self,
        user: User,
        start_date: Optional[datetime] = None
    ) -> NutritionPlan:
        """
        Generate a personalized weekly meal plan

        Args:
            user: User object with profile data
            start_date: Week start date (defaults to next Monday)

        Returns:
            NutritionPlan with 7 days of meals
        """
        if start_date is None:
            start_date = self._get_next_monday()

        # Step 1: Retrieve user context using hierarchical memory
        context = await self.memory.get_user_context(
            user_id=user.id,
            context_type="nutrition_planning"
        )

        # Step 2: Calculate nutritional targets (daily calories & macros)
        targets = await self._calculate_nutrition_targets(user, context)

        # Step 3: Generate weekly meals using AI
        meals = await self._generate_weekly_meals(user, targets, context)

        # Step 4: Create NutritionPlan in database
        nutrition_plan = NutritionPlan(
            user_id=user.id,
            week_start=start_date.date() if isinstance(start_date, datetime) else start_date,
            week_end=(start_date + timedelta(days=6)).date() if isinstance(start_date, datetime) else start_date + timedelta(days=6),
            daily_calories=targets["daily_calories"],
            protein_grams=targets["protein_grams"],
            carbs_grams=targets["carbs_grams"],
            fat_grams=targets["fat_grams"],
            created_by_ai=True,
            adaptation_reason="AI-generated personalized meal plan"
        )

        self.db.add(nutrition_plan)
        await self.db.flush()  # Get plan ID

        # Add meals to plan
        for meal in meals:
            meal.plan_id = nutrition_plan.id
            self.db.add(meal)

        # Note: Commit is handled by the route handler
        # Just flush to ensure we have IDs for relationships
        await self.db.flush()

        # Step 5: Update episodic memory with this plan (will be committed by route handler)
        await self.memory.store_episode(
            user_id=user.id,
            episode_type="nutrition_plan_generated",
            content={
                "plan_id": str(nutrition_plan.id),
                "targets": targets,
                "meal_count": len(meals),
                "generated_at": datetime.utcnow().isoformat()
            }
        )

        return nutrition_plan

    async def _calculate_nutrition_targets(
        self,
        user: User,
        context: Dict
    ) -> Dict[str, int]:
        """
        Calculate daily calorie and macro targets using AI + formulas
        """
        profile = user.profile
        if not profile:
            # Default targets
            return {
                "daily_calories": 2000,
                "protein_grams": 150,
                "carbs_grams": 200,
                "fat_grams": 67
            }

        # Base calculation using Mifflin-St Jeor
        age = profile.age or 25
        weight = float(profile.weight) if profile.weight else 70.0
        height = float(profile.height) if profile.height else 170.0
        gender = profile.gender or "male"
        activity = profile.activity_level or "moderate"
        goal = profile.primary_goal or "maintain"

        # BMR calculation
        bmr = (10 * weight) + (6.25 * height) - (5 * age)
        bmr += 5 if gender == "male" else -161

        # Activity multipliers
        activity_multipliers = {
            "sedentary": 1.2,
            "lightly_active": 1.375,
            "moderately_active": 1.55,
            "very_active": 1.725,
            "extremely_active": 1.9
        }
        tdee = bmr * activity_multipliers.get(activity, 1.55)

        # Goal adjustments
        if goal == "weight_loss":
            daily_calories = int(tdee - 500)
        elif goal == "muscle_gain":
            daily_calories = int(tdee + 300)
        else:
            daily_calories = int(tdee)

        # Macro split (can be customized per user preferences)
        protein_grams = int(daily_calories * 0.30 / 4)  # 30% protein
        carbs_grams = int(daily_calories * 0.40 / 4)    # 40% carbs
        fat_grams = int(daily_calories * 0.30 / 9)      # 30% fat

        return {
            "daily_calories": daily_calories,
            "protein_grams": protein_grams,
            "carbs_grams": carbs_grams,
            "fat_grams": fat_grams
        }

    async def _generate_weekly_meals(
        self,
        user: User,
        targets: Dict[str, int],
        context: Dict
    ) -> List[Meal]:
        """
        Generate 7 days of meal plans using AI
        Returns list of Meal objects (4 meals per day x 7 days = 28 meals)
        """
        profile = user.profile

        # Build AI prompt with user context
        system_prompt = self._build_nutrition_system_prompt()
        user_prompt = self._build_nutrition_user_prompt(user, targets, context)

        # Use fast LLM for meal generation (cheaper and faster)
        fast_llm = get_fast_llm()

        response = await fast_llm.ainvoke([
            SystemMessage(content=system_prompt),
            HumanMessage(content=user_prompt)
        ])

        # Parse AI response into structured meal data
        meals = await self._parse_meal_response(response.content, targets)

        return meals

    def _build_nutrition_system_prompt(self) -> str:
        """System prompt for nutrition agent"""
        import random

        # Randomize cuisine focus for variety
        cuisine_themes = [
            "Mediterranean and Middle Eastern cuisines",
            "Asian-inspired meals (Japanese, Korean, Thai, Vietnamese)",
            "Latin American and Mexican cuisines",
            "Indian and South Asian flavors",
            "Modern American with international fusion",
            "European comfort foods (Italian, French, Greek)",
        ]
        cuisine_focus = random.choice(cuisine_themes)

        # Randomize protein variety
        protein_focuses = [
            "emphasizing fish and seafood twice this week",
            "featuring lean poultry and eggs",
            "incorporating plant-based proteins like tofu, tempeh, and legumes",
            "balancing red meat, poultry, and fish throughout the week",
        ]
        protein_focus = random.choice(protein_focuses)

        return f"""You are an expert nutritionist and meal planner AI.
Your role is to create personalized, balanced, and UNIQUE weekly meal plans.

VARIETY IS CRITICAL - This week's theme: {cuisine_focus}, {protein_focus}.

Key principles:
- Prioritize whole foods and balanced macronutrients
- Consider user preferences, dietary restrictions, and cultural foods
- MAXIMUM VARIETY: Never repeat the same main protein or dish across the week
- Different breakfast styles each day (smoothies, eggs, oatmeal, yogurt bowls, etc.)
- Different lunch formats (salads, wraps, bowls, soups, sandwiches)
- Different dinner cuisines and cooking methods each day
- Make meals practical based on cooking skills and time constraints
- Include specific portion sizes and preparation methods
- Provide accurate calorie and macro breakdowns per meal

CRITICAL: You MUST respond with ONLY a valid JSON array, nothing else. No explanations, no code blocks, no markdown.

Return exactly 28 meals (4 per day x 7 days) as a JSON array. Each meal object must have these fields:
{{
  "day": 0,
  "meal_type": "breakfast",
  "meal_order": 1,
  "name": "Shakshuka with Crusty Bread",
  "description": "Poached eggs in spiced tomato sauce with feta and fresh herbs",
  "calories": 380,
  "protein_grams": 18.5,
  "carbs_grams": 32.0,
  "fat_grams": 20.0,
  "fiber_grams": 5.0,
  "ingredients": {{"eggs": "2 large", "tomato_sauce": "1 cup", "feta": "1 oz", "bread": "1 slice"}},
  "instructions": "Simmer tomato sauce with spices, crack eggs into sauce, cover and cook until set",
  "prep_time_minutes": 5,
  "cook_time_minutes": 15,
  "cuisine_type": "Middle Eastern",
  "dietary_tags": ["vegetarian"]
}}

Ensure daily totals match target calories and macros. Be CREATIVE and DIVERSE with meal choices!
RESPOND WITH ONLY THE JSON ARRAY."""

    def _build_nutrition_user_prompt(
        self,
        user: User,
        targets: Dict[str, int],
        context: Dict
    ) -> str:
        """Build user-specific prompt with context"""
        import random
        from datetime import datetime

        profile = user.profile

        # Add variety hints
        breakfast_styles = ["smoothie bowl", "egg-based", "overnight oats", "savory breakfast", "pancakes/waffles", "yogurt parfait", "breakfast burrito"]
        random.shuffle(breakfast_styles)
        breakfast_hint = ", ".join(breakfast_styles[:3])

        # Generate a unique seed based on time for truly different plans
        unique_seed = datetime.now().strftime("%Y%m%d%H%M%S")

        prompt = f"""Generate a UNIQUE 7-day meal plan (seed: {unique_seed}) for this user:

NUTRITIONAL TARGETS (daily):
- Calories: {targets['daily_calories']} kcal
- Protein: {targets['protein_grams']}g
- Carbs: {targets['carbs_grams']}g
- Fat: {targets['fat_grams']}g

USER PROFILE:
- Age: {profile.age if profile else 'N/A'}
- Gender: {profile.gender if profile else 'N/A'}
- Primary Goal: {profile.primary_goal if profile else 'general health'}
- Activity Level: {profile.activity_level if profile else 'moderate'}
- Meals Per Day: {profile.meals_per_day if profile and profile.meals_per_day else 4}
- Cooking Time Preference: {profile.cooking_time if profile and profile.cooking_time else 'moderate'}

"""

        # CRITICAL: Add dietary restrictions and allergies prominently
        if profile and profile.dietary_restrictions:
            restrictions = ', '.join(profile.dietary_restrictions)
            prompt += f"""⚠️ MANDATORY DIETARY RESTRICTIONS (MUST FOLLOW — DO NOT INCLUDE ANY FOOD THAT VIOLATES THESE):
{restrictions}

"""
        if profile and profile.allergies:
            prompt += f"""⚠️ ALLERGIES (MUST AVOID — these can cause medical harm):
{profile.allergies}

"""
        if profile and profile.nutrition_preferences:
            prompt += f"NUTRITION PREFERENCES: {profile.nutrition_preferences}\n\n"

        prompt += f"""VARIETY REQUIREMENTS:
- Include at least 3 different breakfast styles from: {breakfast_hint}
- Each dinner should feature a different main protein
- Mix cooking methods: grilling, baking, sautéing, steaming, raw

"""

        # Add context from memory if available
        episodic = context.get("episodic_memory", {})
        semantic = context.get("semantic_memory", {})

        # Include past nutrition history for adaptive planning
        nutrition_history = episodic.get("nutrition_history", [])
        if nutrition_history:
            prompt += f"\nPAST NUTRITION PLANS (adapt and vary from these):\n"
            for hist in nutrition_history[:3]:
                prompt += f"  - Week of {hist.get('week_start', 'N/A')}: {hist.get('daily_calories', 'N/A')} kcal, {hist.get('meal_count', 0)} meals\n"
            prompt += "\n"

        # Include preferences from semantic memory
        prefs = semantic.get("preferences", {})
        if prefs.get("dietary"):
            prompt += f"KNOWN PREFERENCES FROM HISTORY: {', '.join(prefs['dietary'])}\n"

        prompt += "\nGenerate a creative and diverse 7-day meal plan as JSON:"

        return prompt

    async def _parse_meal_response(
        self,
        response: str,
        targets: Dict[str, int]
    ) -> List[Meal]:
        """Parse AI response into Meal objects"""
        import json
        import logging

        logger = logging.getLogger(__name__)
        logger.info(f"AI Response length: {len(response)} chars")
        logger.debug(f"Full AI Response: {response}")

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
                # Find the matching closing bracket
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
            meals_data = json.loads(json_str)
            logger.info(f"Successfully parsed {len(meals_data)} meals from AI response")
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse AI response as JSON: {e}")
            logger.error(f"Attempted to parse (first 500 chars): {json_str[:500]}")
            logger.error(f"Original response (first 500 chars): {response[:500]}")
            return self._generate_fallback_meals(targets)

        meals = []
        for meal_data in meals_data:
            meal = Meal(
                day_of_week=meal_data.get("day", 0),
                meal_type=meal_data.get("meal_type", "breakfast"),
                meal_order=meal_data.get("meal_order", 1),
                name=meal_data.get("name", "Meal"),
                description=meal_data.get("description"),
                calories=int(meal_data.get("calories", 0)),
                protein_grams=float(meal_data.get("protein_grams", 0)),
                carbs_grams=float(meal_data.get("carbs_grams", 0)),
                fat_grams=float(meal_data.get("fat_grams", 0)),
                fiber_grams=float(meal_data.get("fiber_grams", 0)) if meal_data.get("fiber_grams") else None,
                ingredients=meal_data.get("ingredients", {}),
                instructions=meal_data.get("instructions"),
                prep_time_minutes=meal_data.get("prep_time_minutes"),
                cook_time_minutes=meal_data.get("cook_time_minutes"),
                cuisine_type=meal_data.get("cuisine_type"),
                dietary_tags=meal_data.get("dietary_tags", [])
            )
            meals.append(meal)

        return meals

    def _generate_fallback_meals(self, targets: Dict[str, int]) -> List[Meal]:
        """Generate simple fallback meal plan if AI parsing fails"""
        meals = []
        cal_per_meal = targets["daily_calories"] // 4  # breakfast, lunch, dinner, snack

        meal_templates = [
            {"meal_type": "breakfast", "name": "Oatmeal with Berries", "desc": "Steel-cut oats with mixed berries"},
            {"meal_type": "lunch", "name": "Grilled Chicken Salad", "desc": "Mixed greens with grilled chicken"},
            {"meal_type": "dinner", "name": "Salmon with Vegetables", "desc": "Baked salmon with roasted vegetables"},
            {"meal_type": "snack", "name": "Greek Yogurt", "desc": "Greek yogurt with honey"}
        ]

        for day in range(7):  # 0=Monday to 6=Sunday
            for idx, template in enumerate(meal_templates):
                meal = Meal(
                    day_of_week=day,
                    meal_type=template["meal_type"],
                    meal_order=1,
                    name=template["name"],
                    description=template["desc"],
                    calories=cal_per_meal,
                    protein_grams=float(targets["protein_grams"] // 4),
                    carbs_grams=float(targets["carbs_grams"] // 4),
                    fat_grams=float(targets["fat_grams"] // 4),
                    ingredients={"ingredient1": "1 serving"},
                    instructions="Prepare as desired",
                    dietary_tags=[]
                )
                meals.append(meal)

        return meals

    def _get_next_monday(self) -> datetime:
        """Get the next Monday's date"""
        today = datetime.now().date()
        days_ahead = 0 - today.weekday()  # Monday is 0
        if days_ahead <= 0:  # Target day already happened this week
            days_ahead += 7
        return datetime.combine(today + timedelta(days=days_ahead), datetime.min.time())
