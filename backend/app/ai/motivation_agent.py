"""
Motivation Agent - Provides coaching, insights, and chat support
Implements conversational AI for motivation and guidance
"""

from typing import Dict, List, Optional
from datetime import datetime, timedelta
from sqlalchemy.ext.asyncio import AsyncSession
from langchain_core.messages import HumanMessage, SystemMessage, AIMessage

from app.models.user import User
from app.models.progress import ChatMessage, ProgressEntry
from app.memory.hierarchical_memory import HierarchicalMemory
from app.core.config import settings
from app.core.llm_factory import get_llm


class MotivationAgent:
    """
    AI Agent for coaching, motivation, and chat interactions
    Provides personalized insights and support
    """

    def __init__(self, db: AsyncSession):
        self.db = db
        self.llm = get_llm(temperature=0.8)
        self.memory = HierarchicalMemory(db)

    async def chat(
        self,
        user: User,
        message: str,
        conversation_history: Optional[List[ChatMessage]] = None
    ) -> ChatMessage:
        """
        Handle chat interaction with user

        Args:
            user: User object
            message: User's message
            conversation_history: Recent chat history

        Returns:
            ChatMessage with AI response
        """
        # Retrieve user context using hierarchical memory
        context = await self.memory.get_user_context(
            user_id=user.id,
            context_type="coaching"
        )

        # Get recent progress entries (last 7 days) for immediate context
        from sqlalchemy import select
        seven_days_ago = datetime.utcnow() - timedelta(days=7)
        stmt = select(ProgressEntry).where(
            ProgressEntry.user_id == user.id,
            ProgressEntry.entry_date >= seven_days_ago
        ).order_by(ProgressEntry.entry_date.desc())
        result = await self.db.execute(stmt)
        recent_progress = result.scalars().all()

        # Build conversation with full context
        messages = self._build_chat_messages(
            user, message, conversation_history, context, recent_progress
        )

        # Get AI response
        response = await self.llm.ainvoke(messages)

        # Store user message
        user_msg = ChatMessage(
            user_id=user.id,
            message=message,
            message_type="user",
            timestamp=datetime.utcnow()
        )
        self.db.add(user_msg)

        # Store AI response
        ai_msg = ChatMessage(
            user_id=user.id,
            message=response.content,
            message_type="ai",
            timestamp=datetime.utcnow()
        )
        self.db.add(ai_msg)

        await self.db.commit()
        await self.db.refresh(ai_msg)

        # Store coaching interaction in episodic memory
        await self.memory.store_episode(
            user_id=user.id,
            episode_type="coaching_interaction",
            content={
                "user_message": message,
                "ai_response": response.content,
                "timestamp": datetime.utcnow().isoformat()
            }
        )

        return ai_msg

    async def generate_weekly_insights(
        self,
        user: User
    ) -> str:
        """
        Generate weekly progress insights and recommendations

        Args:
            user: User object

        Returns:
            Insight text
        """
        # Get user's progress data for the week
        week_ago = datetime.utcnow() - timedelta(days=7)

        from sqlalchemy import select
        stmt = select(ProgressEntry).where(
            ProgressEntry.user_id == user.id,
            ProgressEntry.entry_date >= week_ago
        ).order_by(ProgressEntry.entry_date.desc())
        result = await self.db.execute(stmt)
        progress_entries = result.scalars().all()

        # Retrieve user context
        context = await self.memory.get_user_context(
            user_id=user.id,
            context_type="insights"
        )

        # Build insight generation prompt
        system_prompt = self._build_insights_system_prompt()
        user_prompt = self._build_insights_user_prompt(user, progress_entries, context)

        response = await self.llm.ainvoke([
            SystemMessage(content=system_prompt),
            HumanMessage(content=user_prompt)
        ])

        return response.content

    def _build_chat_messages(
        self,
        user: User,
        current_message: str,
        history: Optional[List[ChatMessage]],
        context: Dict,
        recent_progress: List[ProgressEntry]
    ) -> List:
        """Build message list for chat with full user context"""
        messages = []

        # Format recent progress data
        progress_summary = self._format_progress(recent_progress)

        # Extract episodic memory patterns
        progress_patterns = context.get("episodic_memory", {}).get("progress_patterns", {})
        consistency_score = progress_patterns.get("consistency_score", 0)
        weight_trend = progress_patterns.get("weight_trend", "unknown")
        avg_workouts = progress_patterns.get("avg_workouts_per_week", 0)

        # Get semantic memory (core profile)
        semantic = context.get("semantic_memory", {})
        core_identity = semantic.get("core_identity", {})
        preferences = semantic.get("preferences", {})

        # Build enhanced system prompt with full context
        system_prompt = f"""You are a personalized AI fitness and nutrition coach for {user.name or 'this user'}.

USER PROFILE:
- Primary Goal: {core_identity.get('primary_goal', 'general health')}
- Age: {core_identity.get('age', 'N/A')}
- Gender: {core_identity.get('gender', 'N/A')}
- Fitness Experience: {core_identity.get('fitness_experience', 'beginner')}
- Activity Level: {semantic.get('targets', {}).get('activity_level', 'moderate')}

DIETARY PREFERENCES & RESTRICTIONS:
- Dietary Restrictions: {', '.join(preferences.get('dietary', [])) if preferences.get('dietary') else 'None'}
- Allergies: {preferences.get('allergies', 'None')}

RECENT PROGRESS (last 7 days):
{progress_summary}

BEHAVIORAL PATTERNS (last 30 days):
- Consistency Score: {consistency_score:.1f}% (days logged)
- Average Workouts per Week: {avg_workouts:.1f}
- Weight Trend: {weight_trend}

Your coaching style:
- Be encouraging, positive, and empathetic
- Provide specific, actionable advice based on their actual data
- Reference their progress and patterns when relevant
- Celebrate wins and acknowledge challenges
- Keep responses concise but personalized (2-4 sentences)
- Use their name occasionally for personal connection

IMPORTANT: You have access to their actual progress data above. Use it to make your coaching specific and relevant to their journey, not generic advice."""

        messages.append(SystemMessage(content=system_prompt))

        # Add conversation history (last 5 messages for context)
        if history:
            for msg in history[-5:]:
                if msg.message_type == "user":
                    messages.append(HumanMessage(content=msg.message))
                else:
                    messages.append(AIMessage(content=msg.message))

        # Add current message
        messages.append(HumanMessage(content=current_message))

        return messages

    def _format_progress(self, progress_entries: List[ProgressEntry]) -> str:
        """Format progress entries for AI prompt"""
        if not progress_entries:
            return "No recent progress logged"

        formatted = []
        for entry in progress_entries:
            entry_str = f"- {entry.entry_date.strftime('%Y-%m-%d')}: "
            details = []

            if entry.current_weight:
                details.append(f"Weight {entry.current_weight}kg")
            if entry.calories_consumed:
                details.append(f"{entry.calories_consumed} calories")
            if entry.workouts_completed:
                details.append(f"{entry.workouts_completed} workouts")
            if entry.mood_score:
                details.append(f"Mood {entry.mood_score}/10")
            if entry.energy_score:
                details.append(f"Energy {entry.energy_score}/10")
            if entry.notes:
                details.append(f"Notes: {entry.notes}")

            entry_str += ", ".join(details) if details else "Entry logged"
            formatted.append(entry_str)

        return "\n".join(formatted) if formatted else "No detailed progress data"

    def _build_insights_system_prompt(self) -> str:
        """System prompt for insights generation"""
        return """You are an expert fitness and nutrition analyst.
Your role is to analyze user progress data and provide actionable insights.

Key principles:
- Identify patterns and trends in the data
- Highlight achievements and positive behaviors
- Point out areas for improvement with specific suggestions
- Be encouraging but honest
- Provide 3-5 key insights per analysis
- Make recommendations concrete and achievable

Keep insights concise, motivating, and data-driven."""

    def _build_insights_user_prompt(
        self,
        user: User,
        progress_entries: List[ProgressEntry],
        context: Dict
    ) -> str:
        """Build user-specific insights prompt"""
        profile = user.profile

        prompt = f"""Analyze this week's progress and provide insights:

USER PROFILE:
- Goal: {profile.primary_goal if profile else 'general health'}
- Current Weight: {progress_entries[0].weight if progress_entries and progress_entries[0].weight else 'N/A'} kg

WEEKLY PROGRESS DATA:
"""

        for entry in progress_entries:
            prompt += f"""
- Date: {entry.date.strftime('%Y-%m-%d')}
  Weight: {entry.current_weight or 'N/A'} kg
  Calories Consumed: {entry.calories_consumed or 0}
  Workouts Completed: {entry.workouts_completed or 0}
  Notes: {entry.notes or 'None'}
"""

        if not progress_entries:
            prompt += "No progress entries recorded this week.\n"

        prompt += """
Generate 3-5 key insights and recommendations based on this data.
Focus on actionable advice and celebrating wins."""

        return prompt
