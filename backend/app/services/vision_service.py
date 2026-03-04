"""Vision AI service for OCR food logging"""

import os
import base64
from typing import Dict, List, Optional

from app.core.llm_factory import get_vision_client, get_vision_model


class VisionService:
    """Service for handling vision-based food recognition"""

    @staticmethod
    async def analyze_food_image(image_data: bytes, image_format: str = "jpeg") -> Dict:
        """
        Analyze a food image and extract nutritional information

        Args:
            image_data: Raw image bytes
            image_format: Image format (jpeg, png, etc.)

        Returns:
            Dict containing identified foods and their nutritional info
        """
        try:
            # Encode image to base64
            base64_image = base64.b64encode(image_data).decode('utf-8')

            # Create prompt for food analysis
            prompt = """Analyze this food image and provide detailed nutritional information.

Return a JSON object with the following structure:
{
  "foods": [
    {
      "name": "food item name",
      "serving_size": "estimated portion size",
      "calories": estimated calories (integer),
      "protein_grams": estimated protein in grams (float),
      "carbs_grams": estimated carbs in grams (float),
      "fat_grams": estimated fat in grams (float),
      "fiber_grams": estimated fiber in grams (float, optional),
      "sugar_grams": estimated sugar in grams (float, optional),
      "confidence": confidence score 0-1 (float)
    }
  ],
  "meal_type_suggestion": "breakfast/lunch/dinner/snack",
  "total_calories": sum of all calories (integer),
  "notes": "any additional observations about the meal"
}

Be as accurate as possible with portion sizes and nutritional estimates. If you can't identify a food clearly, set confidence to a low value."""

            # Call Vision API (works with both OpenAI and Azure OpenAI)
            vision_client = get_vision_client()
            response = await vision_client.chat.completions.create(
                model=get_vision_model(),
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": prompt
                            },
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:image/{image_format};base64,{base64_image}"
                                }
                            }
                        ]
                    }
                ],
                response_format={"type": "json_object"},
                max_tokens=1000,
            )

            # Parse the response
            result = response.choices[0].message.content

            # The response should be valid JSON
            import json
            parsed_result = json.loads(result)

            return parsed_result

        except Exception as e:
            raise Exception(f"Failed to analyze food image: {str(e)}")

    @staticmethod
    async def analyze_food_from_url(image_url: str) -> Dict:
        """
        Analyze a food image from a URL

        Args:
            image_url: URL of the image

        Returns:
            Dict containing identified foods and their nutritional info
        """
        try:
            prompt = """Analyze this food image and provide detailed nutritional information.

Return a JSON object with the following structure:
{
  "foods": [
    {
      "name": "food item name",
      "serving_size": "estimated portion size",
      "calories": estimated calories (integer),
      "protein_grams": estimated protein in grams (float),
      "carbs_grams": estimated carbs in grams (float),
      "fat_grams": estimated fat in grams (float),
      "fiber_grams": estimated fiber in grams (float, optional),
      "sugar_grams": estimated sugar in grams (float, optional),
      "confidence": confidence score 0-1 (float)
    }
  ],
  "meal_type_suggestion": "breakfast/lunch/dinner/snack",
  "total_calories": sum of all calories (integer),
  "notes": "any additional observations about the meal"
}

Be as accurate as possible with portion sizes and nutritional estimates. If you can't identify a food clearly, set confidence to a low value."""

            response = await get_vision_client().chat.completions.create(
                model=get_vision_model(),
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": prompt
                            },
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": image_url
                                }
                            }
                        ]
                    }
                ],
                response_format={"type": "json_object"},
                max_tokens=1000,
            )

            result = response.choices[0].message.content

            import json
            parsed_result = json.loads(result)

            return parsed_result

        except Exception as e:
            raise Exception(f"Failed to analyze food image from URL: {str(e)}")

    @staticmethod
    async def get_food_suggestions(partial_name: str) -> List[Dict]:
        """
        Get food suggestions based on partial name using AI

        Args:
            partial_name: Partial food name

        Returns:
            List of food suggestions with nutritional info
        """
        try:
            prompt = f"""Given the food name "{partial_name}", provide 5 similar food items with their typical nutritional information per standard serving.

Return a JSON object with this structure:
{{
  "suggestions": [
    {{
      "name": "food item name",
      "serving_size": "standard serving size",
      "calories": calories per serving (integer),
      "protein_grams": protein in grams (float),
      "carbs_grams": carbs in grams (float),
      "fat_grams": fat in grams (float)
    }}
  ]
}}"""

            response = await get_vision_client().chat.completions.create(
                model=get_vision_model(),
                messages=[
                    {
                        "role": "user",
                        "content": prompt
                    }
                ],
                response_format={"type": "json_object"},
                max_tokens=500,
            )

            result = response.choices[0].message.content

            import json
            parsed_result = json.loads(result)

            return parsed_result.get("suggestions", [])

        except Exception as e:
            raise Exception(f"Failed to get food suggestions: {str(e)}")
