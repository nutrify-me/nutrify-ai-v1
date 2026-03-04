"""
LLM Factory - Creates LangChain LLM instances based on configuration.
Supports both OpenAI and Azure AI Foundry (Azure OpenAI) backends.

Usage:
    from app.core.llm_factory import get_llm, get_fast_llm, get_vision_client

    llm = get_llm()               # Main model (gpt-4o / Azure gpt-4o)
    fast = get_fast_llm()          # Fast model (gpt-4o-mini / Azure gpt-4o-mini)
    client = get_vision_client()   # AsyncOpenAI-compatible client for vision
"""

from langchain_core.language_models.chat_models import BaseChatModel
from app.core.config import settings


def get_llm(
    temperature: float | None = None,
    model: str | None = None,
) -> BaseChatModel:
    """Get the primary LLM (for plan generation, insights, coaching)."""
    temp = temperature or settings.AI_TEMPERATURE
    mdl = model or settings.AI_MODEL

    if settings.AZURE_OPENAI_ENDPOINT:
        return _azure_llm(mdl, temp)
    else:
        return _openai_llm(mdl, temp)


def get_fast_llm(
    temperature: float = 0.7,
) -> BaseChatModel:
    """Get the fast/cheap LLM (for meal/workout generation)."""
    model = settings.AZURE_FAST_DEPLOYMENT or settings.AI_FAST_MODEL

    if settings.AZURE_OPENAI_ENDPOINT:
        return _azure_llm(model, temperature)
    else:
        return _openai_llm(model, temperature)


def get_vision_client():
    """
    Get an AsyncOpenAI-compatible client for vision (food image analysis).
    Works with both OpenAI and Azure OpenAI.
    """
    if settings.AZURE_OPENAI_ENDPOINT:
        from openai import AsyncAzureOpenAI
        return AsyncAzureOpenAI(
            azure_endpoint=settings.AZURE_OPENAI_ENDPOINT,
            api_key=settings.AZURE_OPENAI_API_KEY,
            api_version=settings.AZURE_OPENAI_API_VERSION,
        )
    else:
        from openai import AsyncOpenAI
        return AsyncOpenAI(api_key=settings.OPENAI_API_KEY)


def get_vision_model() -> str:
    """Get the vision model name/deployment."""
    return settings.AZURE_VISION_DEPLOYMENT or "gpt-4o"


# ─── Private constructors ───────────────────────────────

def _openai_llm(model: str, temperature: float) -> BaseChatModel:
    from langchain_openai import ChatOpenAI
    return ChatOpenAI(
        model=model,
        temperature=temperature,
        api_key=settings.OPENAI_API_KEY,
    )


def _azure_llm(deployment: str, temperature: float) -> BaseChatModel:
    from langchain_openai import AzureChatOpenAI
    return AzureChatOpenAI(
        azure_deployment=deployment,
        azure_endpoint=settings.AZURE_OPENAI_ENDPOINT,
        api_key=settings.AZURE_OPENAI_API_KEY,
        api_version=settings.AZURE_OPENAI_API_VERSION,
        temperature=temperature,
    )
