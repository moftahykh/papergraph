from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.core.middleware import ContentLengthLimitMiddleware
from app.core.rate_limiter import RateLimitMiddleware
from app.api.v1.health import router as health_router
from app.api.v1.search import router as search_router
from app.api.v1.resolve import router as resolve_router
from app.api.v1.graphs import router as graphs_router
from app.api.v1.papers import router as papers_router
from app.api.v1.metrics import router as metrics_router
from app.api.v1.auth import router as auth_router
from app.api.v1.monitoring import router as monitoring_router
from app.core.errors import APIError, api_error_handler

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    description="PaperGraph — Multi-Source Academic Discovery Engine Backend API",
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    docs_url=f"{settings.API_V1_STR}/docs",
    redoc_url=f"{settings.API_V1_STR}/redoc",
)

# Exception Handlers
app.add_exception_handler(APIError, api_error_handler)

# Security & Traffic Middlewares (processed in reverse order of addition)
app.add_middleware(RateLimitMiddleware)
app.add_middleware(ContentLengthLimitMiddleware)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=[str(origin) for origin in settings.BACKEND_CORS_ORIGINS],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

# Root-level health check convenience endpoint
@app.get("/health", tags=["Health"])
async def root_health():
    return {
        "status": "ok",
        "app": settings.PROJECT_NAME,
        "version": settings.VERSION,
    }

# Include API v1 routers
app.include_router(health_router, prefix=settings.API_V1_STR)
app.include_router(search_router, prefix=settings.API_V1_STR)
app.include_router(resolve_router, prefix=settings.API_V1_STR)
app.include_router(graphs_router, prefix=settings.API_V1_STR)
app.include_router(papers_router, prefix=settings.API_V1_STR)
app.include_router(metrics_router, prefix=settings.API_V1_STR)
app.include_router(auth_router, prefix=settings.API_V1_STR)
app.include_router(monitoring_router, prefix=settings.API_V1_STR)
# Authentication & Verification Router Loaded
