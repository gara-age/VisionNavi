from __future__ import annotations

import sys
from pathlib import Path

import uvicorn
from fastapi import FastAPI
from pydantic import BaseModel, Field


PROJECT_ROOT = Path(__file__).resolve().parents[3]
ORCHESTRATOR_ROOT = PROJECT_ROOT / "orchestrator"
if str(ORCHESTRATOR_ROOT) not in sys.path:
    sys.path.insert(0, str(ORCHESTRATOR_ROOT))

from app.core.settings import Settings  # noqa: E402
from app.services.guidance_tts_service import GuidanceTtsService  # noqa: E402


class SynthesizeRequest(BaseModel):
    text: str = Field(min_length=1)
    language: str = Field(default="ko")
    provider: str | None = None
    voice: str | None = None
    speed: float = Field(default=1.0, ge=0.7, le=1.3)
    volume: float = Field(default=1.0, ge=0.7, le=1.3)


class SynthesizeResponse(BaseModel):
    ok: bool
    provider: str
    voice: str | None = None
    device: str | None = None
    audio_path: str | None = None
    detail: str | None = None


settings = Settings.from_env()
tts_service = GuidanceTtsService(settings)
app = FastAPI(title="VisionNavi Edge TTS Worker", version="0.1.0")


@app.on_event("startup")
async def _startup() -> None:
    tts_service.startup()


@app.on_event("shutdown")
async def _shutdown() -> None:
    tts_service.shutdown()


@app.get("/health")
def health() -> dict[str, object]:
    return {
        "status": "ok",
        "provider": "edge",
        "engine": "edge-tts",
    }


@app.post("/synthesize", response_model=SynthesizeResponse)
def synthesize(request: SynthesizeRequest) -> SynthesizeResponse:
    result = tts_service.speak(
        text=request.text,
        language=request.language,
        provider=request.provider,
        voice=request.voice,
        speed=request.speed,
        volume=request.volume,
    )
    return SynthesizeResponse(
        ok=result.ok,
        provider=result.provider,
        voice=result.voice,
        device=result.device,
        audio_path=result.audio_path,
        detail=result.detail,
    )


def main() -> None:
    uvicorn.run(
        app,
        host="127.0.0.1",
        port=8011,
        log_level="warning",
    )


if __name__ == "__main__":
    main()
