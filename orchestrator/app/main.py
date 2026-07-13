from fastapi import FastAPI

from app.api.routes.health import router as health_router
from app.api.routes.pipeline import guidance_tts_service, router as pipeline_router


def create_app() -> FastAPI:
    app = FastAPI(title="VisionNavi Orchestrator", version="0.1.0")

    @app.on_event("startup")
    async def _startup() -> None:
        guidance_tts_service.startup()

    @app.on_event("shutdown")
    async def _shutdown() -> None:
        guidance_tts_service.shutdown()

    app.include_router(health_router)
    app.include_router(pipeline_router)
    return app


app = create_app()
