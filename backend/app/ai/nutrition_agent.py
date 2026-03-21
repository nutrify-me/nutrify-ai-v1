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
        system_prompt = self._build_nutrition_system_prompt(user)
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

    def _build_nutrition_system_prompt(self, user: User) -> str:
        """System prompt for nutrition agent — region-aware, practical home cooking"""
        profile = user.profile
        nutrition_prefs = (profile.nutrition_preferences or {}) if profile else {}

        food_region = nutrition_prefs.get("food_region", "mixed")
        cooking_skill = nutrition_prefs.get("cooking_skill", "intermediate")
        cooking_time = nutrition_prefs.get("cooking_time", "30 min")
        spice_tolerance = nutrition_prefs.get("spice_tolerance", "medium")
        staple_foods = nutrition_prefs.get("staple_foods", [])
        foods_to_avoid = nutrition_prefs.get("foods_to_avoid", "")

        # Region → cuisine instruction mapping
        region_instructions = {
            "indian_north": "Plan meals using North Indian home cooking: dal, roti, rice, sabzi, raita, parathas, poha, upma, khichdi. Think what a typical Indian household eats daily — simple, comforting, practical.",
            "indian_south": "Plan meals using South Indian home cooking: idli, dosa, sambar, rice, rasam, upma, pongal, curd rice, coconut chutney, uttapam. Everyday home-style meals.",
            "american": "Plan meals using simple American home cooking: oatmeal, eggs, sandwiches, grilled chicken, salads, pasta, rice bowls and casseroles. Easy weeknight meals anyone can make.",
            "mediterranean": "Plan meals using Mediterranean home cooking: hummus, grilled fish, olive oil dishes, fresh salads, whole grains, lentil soup, tabbouleh. Healthy and simple.",
            "east_asian": "Plan meals using East Asian home cooking: steamed rice, stir-fries, miso soup, tofu dishes, noodle bowls, fried rice. Practical everyday meals.",
            "southeast_asian": "Plan meals using Southeast Asian home cooking: rice, curries, noodle soups, stir-fried vegetables, satay. Flavorful but practical.",
            "latin_american": "Plan meals using Latin American home cooking: rice and beans, tortillas, grilled chicken, tacos, burrito bowls, plantains. Simple and filling.",
            "middle_eastern": "Plan meals using Middle Eastern home cooking: flatbread, kebabs, lentils, yogurt, hummus, rice pilaf, falafel. Comforting everyday food.",
            "european": "Plan meals using European home cooking: bread, soups, pasta, roast chicken, potatoes, salads, omelettes, stews. Classic comfort food.",
            "african": "Plan meals using African home cooking: stews, rice, plantain, jollof rice, lentils, grilled fish, couscous. Hearty everyday meals.",
            "mixed": "Plan meals using a practical international mix based on the user's staple foods. Keep it simple and accessible.",
        }

        cuisine_instruction = region_instructions.get(food_region, region_instructions["mixed"])

        skill_instruction = {
            "beginner": "Recipes MUST be very simple — max 5-6 ingredients, one-pot/one-pan where possible, no complex techniques. Step-by-step instructions a complete beginner can follow.",
            "intermediate": "Recipes should be moderately simple — common techniques like sautéing, boiling, baking. Clear instructions.",
            "advanced": "Recipes can include more complex techniques and ingredients. Still provide clear instructions.",
        }.get(cooking_skill, "Recipes should be moderately simple.")

        staple_instruction = ""
        if staple_foods:
            staple_instruction = f"\nBUILD MEALS AROUND THESE STAPLE FOODS (user eats these regularly): {', '.join(staple_foods)}"

        avoid_instruction = ""
        if foods_to_avoid:
            avoid_instruction = f"\n⚠️ FOODS THE USER DISLIKES (do NOT include): {foods_to_avoid}"

        return f"""You are a practical home-cooking nutritionist AI.
Your role is to create simple, everyday meal plans that someone actually makes at home — NOT fancy restaurant dishes.

CUISINE FOCUS: {cuisine_instruction}
{staple_instruction}
{avoid_instruction}

COOKING LEVEL: {skill_instruction}
MAX COOKING TIME per meal: {cooking_time}
SPICE LEVEL: {spice_tolerance}

Key principles:
- Meals should be what people ACTUALLY cook at home daily — simple, practical, filling
- DO NOT suggest overly fancy or restaurant-style dishes (no "Za'atar Omelette with Feta and Tomato" when the user eats poha for breakfast)
- Include step-by-step cooking instructions that are easy to follow
- Use commonly available ingredients from the user's region
- Variety within the cuisine — different dishes each day but staying within the food culture

CRITICAL INGREDIENT RULES:
- Every ingredient MUST have a weight in grams (e.g. "150g" not "1.5 cups", "15g" not "1 tbsp")
- For liquids use ml (e.g. "10ml oil" not "1 tsp oil")
- Be precise: "150g flattened rice" not "1 bowl poha"
- The calorie and macro numbers MUST be calculated from the gram weights using standard nutrition data
- Example: 150g cooked poha ≈ 165 kcal (110 kcal/100g × 1.5), 15g peanuts ≈ 85 kcal (567 kcal/100g × 0.15)
- SUM the per-ingredient calories to get the meal total — do NOT estimate the total independently

CRITICAL: You MUST respond with ONLY a valid JSON array, nothing else. No explanations, no code blocks, no markdown.

Return the meals as a JSON array. Each meal object must have these fields:
{{
  "day": 0,
  "meal_type": "breakfast",
  "meal_order": 1,
  "name": "Poha with Peanuts and Lemon",
  "description": "Flattened rice stir-fried with onions, peanuts, turmeric, and lemon juice",
  "calories": 312,
  "protein_grams": 8.5,
  "carbs_grams": 42.0,
  "fat_grams": 12.0,
  "fiber_grams": 3.0,
  "ingredients": {{"flattened_rice": "150g", "peanuts": "15g", "onion": "80g", "oil": "10ml", "turmeric": "2g", "lemon_juice": "15ml"}},
  "instructions": "1. Rinse 150g poha in water and drain. 2. Heat 10ml oil, add mustard seeds and curry leaves. 3. Add 80g chopped onion, 1 green chili, sauté until soft. 4. Add 2g turmeric, salt, 15g roasted peanuts. 5. Add poha, mix gently, cook 2 min. 6. Squeeze 15ml lemon juice, garnish with coriander.",
  "prep_time_minutes": 5,
  "cook_time_minutes": 10,
  "cuisine_type": "Indian",
  "dietary_tags": ["vegetarian"]
}}

Ensure daily totals match target calories and macros.
RESPOND WITH ONLY THE JSON ARRAY."""

    def _build_nutrition_user_prompt(
        self,
        user: User,
        targets: Dict[str, int],
        context: Dict
    ) -> str:
        """Build user-specific prompt with context — region-aware"""
        from datetime import datetime

        profile = user.profile
        nutrition_prefs = (profile.nutrition_preferences or {}) if profile else {}

        meals_per_day = profile.meals_per_day if profile and profile.meals_per_day else 4
        food_region = nutrition_prefs.get("food_region", "mixed")
        diet_type = nutrition_prefs.get("diet_type", "No Restriction")

        # Generate a unique seed based on time for truly different plans
        unique_seed = datetime.now().strftime("%Y%m%d%H%M%S")

        prompt = f"""Generate a practical 7-day home-cooking meal plan (seed: {unique_seed}) for this user:

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
- Meals Per Day: {meals_per_day}
- Food Region: {food_region}
- Diet Type: {diet_type}

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

        # Add staple foods and dislikes from nutrition preferences
        staple_foods = nutrition_prefs.get("staple_foods", [])
        if staple_foods:
            prompt += f"BUILD MEALS AROUND THESE STAPLE FOODS: {', '.join(staple_foods)}\n\n"

        foods_to_avoid = nutrition_prefs.get("foods_to_avoid", "")
        if foods_to_avoid:
            prompt += f"FOODS TO AVOID (user dislikes): {foods_to_avoid}\n\n"

        prompt += f"""IMPORTANT:
- Generate exactly {meals_per_day * 7} meals ({meals_per_day} per day x 7 days)
- All meals should be simple HOME-COOKED food from the user's region
- Include step-by-step cooking instructions with GRAM WEIGHTS in each step
- Every ingredient MUST be listed with weight in grams (or ml for liquids)
- Calculate each meal's calories by summing per-ingredient calories (weight × kcal/100g)
- Different dishes each day but staying true to the food culture
- Vary proteins and preparations throughout the week
- DAILY MEAL TOTALS MUST sum to approximately {targets['daily_calories']} kcal

"""

        # Add context from memory if available
        episodic = context.get("episodic_memory", {})
        semantic = context.get("semantic_memory", {})

        nutrition_history = episodic.get("nutrition_history", [])
        if nutrition_history:
            prompt += "PAST NUTRITION PLANS (vary from these):\n"
            for hist in nutrition_history[:3]:
                prompt += f"  - Week of {hist.get('week_start', 'N/A')}: {hist.get('daily_calories', 'N/A')} kcal\n"
            prompt += "\n"

        prefs = semantic.get("preferences", {})
        if prefs.get("dietary"):
            prompt += f"KNOWN PREFERENCES FROM HISTORY: {', '.join(prefs['dietary'])}\n"

        prompt += "\nGenerate the meal plan as a JSON array:"

        return prompt

    async def _parse_meal_response(
        self,
        response: str,
        targets: Dict[str, int]
    ) -> List[Meal]:
        """Parse AI response into Meal objects, then validate calories against food DB"""
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

        # ── Validate each meal against the food DB ──
        validated_data = []
        for meal_data in meals_data:
            corrected = self.nutrition_db.validate_meal(meal_data)
            validated_data.append(corrected)

        # ── Validate per-day totals and scale to hit target ──
        from itertools import groupby
        sorted_meals = sorted(validated_data, key=lambda m: m.get("day", 0))
        final_data = []
        for day, day_meals_iter in groupby(sorted_meals, key=lambda m: m.get("day", 0)):
            day_meals = list(day_meals_iter)
            adjusted = self.nutrition_db.validate_day_meals(day_meals, targets["daily_calories"])
            final_data.extend(adjusted)

        corrected_count = sum(1 for m in final_data if m.get("_nutrition_source") == "db_corrected")
        scaled_count = sum(1 for m in final_data if m.get("_scaled"))
        logger.info(
            f"Nutrition validation: {corrected_count}/{len(final_data)} meals corrected by DB, "
            f"{scaled_count} meals scaled to hit daily target"
        )

        meals = []
        for meal_data in final_data:
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
