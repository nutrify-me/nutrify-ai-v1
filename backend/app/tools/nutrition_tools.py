"""
Nutrition Database Tools
Provides nutrition data and meal planning utilities for AI agents.
Uses an embedded food nutrition database (data/food_nutrition_db.json) for
ground-truth calorie/macro lookups per 100g of edible portion.
"""

import json
import os
import re
import logging
from pathlib import Path
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

# ───────────────────────────────────────────────────────────
# Quantity parsing helpers
# ───────────────────────────────────────────────────────────

# Approximate gram weights for common household measures
_UNIT_TO_GRAMS: Dict[str, float] = {
    "cup": 150, "cups": 150,
    "tbsp": 15, "tablespoon": 15, "tablespoons": 15,
    "tsp": 5, "teaspoon": 5, "teaspoons": 5,
    "glass": 250, "glasses": 250,
    "bowl": 200, "bowls": 200,
    "serving": 150, "servings": 150,
    "piece": 100, "pieces": 100, "pc": 100,
    "slice": 30, "slices": 30,
    "handful": 30,
    "small": 80, "medium": 120, "large": 180,
    "ml": 1, "litre": 1000, "liter": 1000, "l": 1000,
    "g": 1, "gm": 1, "gms": 1, "gram": 1, "grams": 1,
    "kg": 1000,
    "oz": 28.35, "ounce": 28.35, "ounces": 28.35,
    "lb": 453.6, "lbs": 453.6, "pound": 453.6, "pounds": 453.6,
}

# Regex: "1.5 cups", "2 tbsp", "100g", "1 medium", "200 ml"
_QTY_RE = re.compile(
    r"(\d+(?:\.\d+)?)\s*"
    r"(cups?|tbsp|tablespoons?|tsp|teaspoons?|glasses?|bowls?|servings?|"
    r"pieces?|pc|slices?|handful|small|medium|large|"
    r"ml|litres?|liters?|l|"
    r"gm?s?|grams?|kg|"
    r"oz|ounces?|lbs?|pounds?)",
    re.IGNORECASE,
)


def parse_quantity_grams(qty_str: str) -> float:
    """
    Convert a human quantity string to approximate grams.
    '1.5 cups' → 225, '2 tbsp' → 30, '100g' → 100, '1 medium' → 120
    Falls back to 100g if parsing fails.
    """
    qty_str = qty_str.strip().lower()

    m = _QTY_RE.search(qty_str)
    if m:
        amount = float(m.group(1))
        unit = m.group(2).lower()
        grams_per_unit = _UNIT_TO_GRAMS.get(unit, 100)
        return amount * grams_per_unit

    # Try bare number → assume grams
    try:
        return float(re.search(r"\d+(?:\.\d+)?", qty_str).group())
    except (AttributeError, ValueError):
        pass

    return 100.0  # default fallback


# ───────────────────────────────────────────────────────────
# Food Nutrition Database
# ───────────────────────────────────────────────────────────

class NutritionDatabase:
    """
    Embedded food nutrition database with fuzzy search.
    Data sourced from IFCT 2017 (Indian Food Composition Tables)
    and USDA FoodData Central.  All values are per 100 g edible portion.
    """

    _instance: Optional["NutritionDatabase"] = None
    _data: Dict[str, Dict] = {}
    _flat: Dict[str, Dict] = {}          # key → nutrition dict
    _search_keys: List[str] = []         # for fuzzy match

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._load()
        return cls._instance

    # ── loading ──────────────────────────────────────────

    def _load(self):
        db_path = Path(__file__).resolve().parent.parent.parent / "data" / "food_nutrition_db.json"
        if not db_path.exists():
            logger.warning(f"Food DB not found at {db_path}")
            return

        with open(db_path, "r", encoding="utf-8") as f:
            raw = json.load(f)

        # Flatten the categorised structure into a single dict
        for category, items in raw.items():
            if category.startswith("_"):
                continue  # skip metadata
            if not isinstance(items, dict):
                continue
            for key, nutrition in items.items():
                if isinstance(nutrition, dict) and "kcal" in nutrition:
                    self._flat[key] = nutrition

        self._search_keys = list(self._flat.keys())
        logger.info(f"Loaded food nutrition DB: {len(self._flat)} items")

    # ── public API ───────────────────────────────────────

    def lookup(self, food_name: str) -> Optional[Dict]:
        """
        Look up nutrition per 100 g for a food item.
        Uses exact match first, then fuzzy substring match.
        Returns dict with kcal, p, c, f, fi  or None.
        """
        key = self._normalise(food_name)

        # 1. Exact key match
        if key in self._flat:
            return self._flat[key]

        # 2. Check if key is a suffix/prefix of a DB entry or vice versa
        #    Only for keys with ≥ 4 chars to avoid false positives
        if len(key) >= 4:
            best, best_len = None, 0
            for db_key in self._search_keys:
                # key must be a prefix/suffix or vice versa (not arbitrary substring)
                if db_key.startswith(key) or db_key.endswith(key) or key.startswith(db_key) or key.endswith(db_key):
                    if len(db_key) > best_len:
                        best = db_key
                        best_len = len(db_key)
            if best:
                return self._flat[best]

        # 3. Token overlap match (at least 2 tokens must match, or 1 token ≥ 5 chars)
        key_tokens = set(key.split("_"))
        best_score, best_match = 0, None
        for db_key in self._search_keys:
            db_tokens = set(db_key.split("_"))
            overlap = key_tokens & db_tokens
            # Require 2+ matching tokens, or 1 matching token that's long enough
            if len(overlap) >= 2 or (len(overlap) == 1 and len(list(overlap)[0]) >= 5):
                score = len(overlap) + sum(len(t) for t in overlap) / 100
                if score > best_score:
                    best_score = score
                    best_match = db_key
        if best_match:
            return self._flat[best_match]

        return None

    def calculate_nutrition(
        self,
        food_name: str,
        quantity_grams: float,
    ) -> Optional[Dict[str, float]]:
        """
        Calculate actual kcal / macros for a given food at a specific weight.
        Returns {kcal, protein, carbs, fat, fiber} or None if food not found.
        """
        entry = self.lookup(food_name)
        if entry is None:
            return None

        factor = quantity_grams / 100.0
        return {
            "kcal": round(entry["kcal"] * factor, 1),
            "protein": round(entry["p"] * factor, 1),
            "carbs": round(entry["c"] * factor, 1),
            "fat": round(entry["f"] * factor, 1),
            "fiber": round(entry.get("fi", 0) * factor, 1),
        }

    def validate_meal(
        self,
        meal_data: Dict,
    ) -> Dict:
        """
        Validate and correct a single LLM-generated meal.

        For each ingredient in `meal_data['ingredients']`:
          1. Parse the quantity string → grams
          2. Look up kcal per 100 g from the DB
          3. Compute actual kcal for that portion

        Then recalculate totals.  If the DB-computed total differs from the
        LLM-stated total by > 20 %, replace with DB values.

        Returns the (possibly corrected) meal_data dict.
        """
        ingredients: Dict[str, str] = meal_data.get("ingredients", {})
        if not ingredients:
            return meal_data  # nothing to validate

        db_total = {"kcal": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0}
        matched_count = 0
        ingredient_details = {}

        for ing_name, qty_str in ingredients.items():
            grams = parse_quantity_grams(str(qty_str))
            nutrition = self.calculate_nutrition(ing_name, grams)

            if nutrition is not None:
                matched_count += 1
                db_total["kcal"] += nutrition["kcal"]
                db_total["protein"] += nutrition["protein"]
                db_total["carbs"] += nutrition["carbs"]
                db_total["fat"] += nutrition["fat"]
                ingredient_details[ing_name] = {
                    "qty_str": qty_str,
                    "grams": round(grams, 0),
                    "kcal": nutrition["kcal"],
                }

        # Only correct if we matched a majority of the ingredients
        if matched_count < len(ingredients) * 0.4:
            logger.debug(
                f"Meal '{meal_data.get('name')}': only matched "
                f"{matched_count}/{len(ingredients)} ingredients – keeping LLM values"
            )
            return meal_data

        llm_kcal = meal_data.get("calories", 0)
        db_kcal = round(db_total["kcal"])

        # If difference > 15 %, trust the DB
        if llm_kcal > 0 and abs(db_kcal - llm_kcal) / llm_kcal > 0.15:
            logger.info(
                f"Correcting meal '{meal_data.get('name')}': "
                f"LLM said {llm_kcal} kcal, DB says {db_kcal} kcal "
                f"({matched_count}/{len(ingredients)} ingredients matched)"
            )
            meal_data["calories"] = db_kcal
            meal_data["protein_grams"] = round(db_total["protein"], 1)
            meal_data["carbs_grams"] = round(db_total["carbs"], 1)
            meal_data["fat_grams"] = round(db_total["fat"], 1)
            meal_data["_nutrition_source"] = "db_corrected"
            meal_data["_db_match_ratio"] = f"{matched_count}/{len(ingredients)}"
        else:
            meal_data["_nutrition_source"] = "llm_verified"

        return meal_data

    def validate_day_meals(
        self,
        meals: List[Dict],
        daily_calorie_target: int,
    ) -> List[Dict]:
        """
        Validate a full day's meals and proportionally adjust portions
        so the day's total kcal matches the target within ±5 %.
        """
        # First validate individual meals
        validated = [self.validate_meal(m) for m in meals]

        # Calculate day total
        day_total = sum(m.get("calories", 0) for m in validated)
        if day_total <= 0:
            return validated

        # If within 5 %, leave it
        if abs(day_total - daily_calorie_target) / daily_calorie_target <= 0.05:
            return validated

        # Proportional scaling
        scale_factor = daily_calorie_target / day_total
        for m in validated:
            m["calories"] = round(m["calories"] * scale_factor)
            m["protein_grams"] = round(m.get("protein_grams", 0) * scale_factor, 1)
            m["carbs_grams"] = round(m.get("carbs_grams", 0) * scale_factor, 1)
            m["fat_grams"] = round(m.get("fat_grams", 0) * scale_factor, 1)
            m["_scaled"] = True

        return validated

    # ── search (for food scanner etc.) ───────────────────

    async def search_foods(
        self,
        query: str,
        limit: int = 10,
    ) -> List[Dict]:
        """
        Search the embedded DB for foods matching a query.
        Returns list of {key, name, kcal, protein, carbs, fat} per 100 g.
        """
        q = self._normalise(query)
        results = []
        for db_key, nutr in self._flat.items():
            if q in db_key or db_key in q:
                results.append({
                    "key": db_key,
                    "name": db_key.replace("_", " ").title(),
                    **nutr,
                })
            if len(results) >= limit:
                break
        return results

    async def get_food_nutrition(self, food_id: str) -> Optional[Dict]:
        """Look up a food by its key."""
        return self.lookup(food_id)

    def calculate_macros(
        self,
        calories: int,
        protein_ratio: float = 0.30,
        carbs_ratio: float = 0.40,
        fat_ratio: float = 0.30,
    ) -> Dict[str, int]:
        protein_grams = int((calories * protein_ratio) / 4)
        carbs_grams = int((calories * carbs_ratio) / 4)
        fat_grams = int((calories * fat_ratio) / 9)
        return {
            "protein_grams": protein_grams,
            "carbs_grams": carbs_grams,
            "fat_grams": fat_grams,
        }

    # ── internal ─────────────────────────────────────────

    @staticmethod
    def _normalise(name: str) -> str:
        """Normalise a food name to a DB-friendly key."""
        name = name.lower().strip()
        name = re.sub(r"[^a-z0-9\s_]", "", name)
        name = re.sub(r"[\s]+", "_", name)
        name = re.sub(r"_+", "_", name)
        return name.strip("_")
