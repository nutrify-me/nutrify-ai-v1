from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse
import structlog

from app.core.config import settings
from app.core.database import init_db, close_db
from app.core.redis import redis_client
from app.api.routes import auth, users, nutrition, fitness, progress, ai, subscriptions, workout_sessions, gamification, runs

# Configure structured logging
structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.add_log_level,
        structlog.processors.JSONRenderer()
    ]
)

logger = structlog.get_logger()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events"""
    # Startup
    logger.info("Starting Nutrify-AI Backend", version=settings.APP_VERSION)

    # Initialize database
    await init_db()
    logger.info("Database initialized")

    # Connect to Redis (optional — app works without it)
    try:
        if settings.REDIS_URL and settings.REDIS_URL.startswith(("redis://", "rediss://")):
            await redis_client.connect()
            logger.info("Redis connected")
        else:
            logger.info("Redis not configured, skipping")
    except Exception as e:
        logger.warning("Redis connection failed, continuing without cache", error=str(e))

    yield

    # Shutdown
    logger.info("Shutting down Nutrify-AI Backend")

    # Close connections
    await close_db()
    try:
        await redis_client.close()
    except Exception:
        pass
    logger.info("Connections closed")


# Create FastAPI application
app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="Agentic AI-powered fitness and nutrition platform",
    docs_url="/docs" if settings.DEBUG else None,
    redoc_url="/redoc" if settings.DEBUG else None,
    lifespan=lifespan
)

# Add CORS middleware
allowed_origins = [
    "http://localhost:3000",
    "http://localhost:5173",
    "https://nutrify-me.github.io",  # Your specific GitHub Pages domain
]

if settings.ENVIRONMENT == "development":
    allowed_origins.append("*")

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
    expose_headers=["*"],
    max_age=3600,
)

# Add GZip compression
app.add_middleware(GZipMiddleware, minimum_size=1000)


# Health check endpoint
@app.get("/health", tags=["Health"])
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "environment": settings.ENVIRONMENT
    }


# Root endpoint
@app.get("/", tags=["Root"])
async def root():
    """Root endpoint"""
    return {
        "message": "Welcome to Nutrify-AI API",
        "version": settings.APP_VERSION,
        "docs": "/docs" if settings.DEBUG else "Disabled in production"
    }


# Include routers
app.include_router(auth.router, prefix=f"{settings.api_v1_prefix}/auth", tags=["Authentication"])
app.include_router(users.router, prefix=f"{settings.api_v1_prefix}/users", tags=["Users"])
app.include_router(nutrition.router, prefix=f"{settings.api_v1_prefix}/nutrition", tags=["Nutrition"])
app.include_router(fitness.router, prefix=f"{settings.api_v1_prefix}/fitness", tags=["Fitness"])
app.include_router(progress.router, prefix=f"{settings.api_v1_prefix}/progress", tags=["Progress"])
app.include_router(ai.router, prefix=f"{settings.api_v1_prefix}/ai", tags=["AI"])
app.include_router(subscriptions.router, prefix=f"{settings.api_v1_prefix}/subscriptions", tags=["Subscriptions"])
app.include_router(workout_sessions.router, prefix=f"{settings.api_v1_prefix}/workout-sessions", tags=["Workout Sessions"])
app.include_router(gamification.router, prefix=f"{settings.api_v1_prefix}/gamification", tags=["Gamification"])
app.include_router(runs.router, prefix=f"{settings.api_v1_prefix}/runs", tags=["Run Tracking"])


# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Global exception handler"""
    logger.error(
        "Unhandled exception",
        exc_info=exc,
        path=request.url.path,
        method=request.method
    )

    return JSONResponse(
        status_code=500,
        content={
            "detail": "Internal server error" if settings.is_production else str(exc)
        }
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.RELOAD,
        log_level=settings.LOG_LEVEL.lower()
    )
