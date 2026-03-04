"""Redis caching decorator for API route handlers.

Usage:
    @router.get("/plans/current")
    @cache_response(ttl=300, key_prefix="nutrition_plan")
    async def get_current_plan(current_user: User = Depends(get_current_user), db=...):
        ...
"""

import functools
import hashlib
import json
from typing import Optional, Callable
from fastapi import Request
from fastapi.responses import JSONResponse

from app.core.redis import redis_client


def cache_response(
    ttl: int = 300,
    key_prefix: str = "",
    per_user: bool = True,
):
    """
    Decorator that caches JSON responses in Redis.

    Args:
        ttl: Cache time-to-live in seconds (default 5 min)
        key_prefix: Cache key prefix (e.g. "nutrition_plan")
        per_user: Whether to scope cache per user (default True)
    """

    def decorator(func: Callable):
        @functools.wraps(func)
        async def wrapper(*args, **kwargs):
            # Extract user_id for per-user caching
            user_id = None
            if per_user:
                current_user = kwargs.get("current_user")
                if current_user:
                    user_id = str(current_user.id)

            # Build cache key
            cache_key = _build_key(key_prefix, user_id, kwargs)

            # Try cache first
            cached = await redis_client.get(cache_key)
            if cached is not None:
                return JSONResponse(
                    content=cached,
                    headers={"X-Cache": "HIT"},
                )

            # Cache miss — call the actual handler
            result = await func(*args, **kwargs)

            # Serialize and cache the response
            try:
                if hasattr(result, "model_dump"):
                    # Pydantic model
                    serialized = result.model_dump(mode="json")
                elif isinstance(result, list):
                    serialized = [
                        item.model_dump(mode="json")
                        if hasattr(item, "model_dump")
                        else item
                        for item in result
                    ]
                elif isinstance(result, dict):
                    serialized = result
                else:
                    serialized = result

                await redis_client.set(cache_key, serialized, expire=ttl)
            except Exception:
                pass  # Don't fail the request if caching fails

            return result

        return wrapper

    return decorator


def invalidate_cache(key_prefix: str, user_id: Optional[str] = None):
    """Invalidate cache entries matching a prefix + user."""

    async def _invalidate():
        if redis_client.redis is None:
            return
        # Delete the exact key pattern
        pattern = f"cache:{key_prefix}:*"
        if user_id:
            pattern = f"cache:{key_prefix}:{user_id}:*"

        try:
            cursor = 0
            while True:
                cursor, keys = await redis_client.redis.scan(
                    cursor, match=pattern, count=100
                )
                if keys:
                    await redis_client.redis.delete(*keys)
                if cursor == 0:
                    break
        except Exception:
            pass

    return _invalidate()


def _build_key(prefix: str, user_id: Optional[str], kwargs: dict) -> str:
    """Build a deterministic cache key."""
    parts = ["cache", prefix]
    if user_id:
        parts.append(user_id)

    # Include relevant query params in key
    for key in sorted(kwargs.keys()):
        if key in ("current_user", "db", "request"):
            continue
        val = kwargs[key]
        if val is not None:
            parts.append(f"{key}={val}")

    raw = ":".join(parts)
    # Hash if too long
    if len(raw) > 200:
        raw = f"cache:{prefix}:{user_id}:{hashlib.md5(raw.encode()).hexdigest()}"
    return raw
