from __future__ import annotations

import asyncio
import traceback
import time
import uuid
from dataclasses import dataclass
from pathlib import Path

from app.core.settings import Settings


@dataclass(frozen=True)
class GuidanceTtsResult:
    ok: bool
    provider: str
    voice: str | None = None
    device: str | None = None
    audio_path: str | None = None
    detail: str | None = None


class GuidanceTtsService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._project_root = Path(__file__).resolve().parents[3]
        self._output_dir = self._project_root / settings.tts_output_dir
        self._last_error: str | None = None
        self._started = False

    def startup(self) -> None:
        if not self._settings.tts_enabled:
            return
        self._started = True

    def shutdown(self) -> None:
        return

    def speak(
        self,
        *,
        text: str,
        language: str,
        provider: str | None = None,
        voice: str | None = None,
        speed: float,
        volume: float,
    ) -> GuidanceTtsResult:
        normalized = text.strip()
        if not self._settings.tts_enabled:
            return GuidanceTtsResult(
                ok=False,
                provider=self._settings.tts_provider,
                detail="tts_disabled",
            )
        if not normalized:
            return GuidanceTtsResult(
                ok=False,
                provider=self._settings.tts_provider,
                detail="empty_text",
            )
        effective_provider = (provider or self._settings.tts_provider).strip().lower()
        if effective_provider != "edge":
            return GuidanceTtsResult(
                ok=False,
                provider=effective_provider,
                detail="unsupported_tts_provider",
            )

        self.startup()
        normalized_language = language.strip().lower()
        try:
            final_voice = (
                voice.strip()
                if voice is not None and voice.strip()
                else self._resolve_edge_voice(normalized_language)
            )
            output_path = self._synthesize_with_edge_tts(
                text=normalized,
                language=normalized_language,
                speed=max(0.7, min(1.3, float(speed))),
                volume=max(0.7, min(1.3, float(volume))),
                voice_override=final_voice,
            )
        except Exception as exc:
            self._last_error = f"{type(exc).__name__}: {exc}\n{traceback.format_exc()}"
            return GuidanceTtsResult(
                ok=False,
                provider=effective_provider,
                voice=voice,
                device="edge",
                audio_path=None,
                detail=self._last_error,
            )
        return GuidanceTtsResult(
            ok=True,
            provider="edge",
            voice=final_voice,
            device="edge",
            audio_path=str(output_path),
            detail="rendered",
        )

    def _resolve_edge_voice(self, language: str) -> str:
        normalized = language.strip().lower()
        if normalized == "ja":
            return self._settings.tts_edge_voice_ja
        return self._settings.tts_edge_voice_ko

    def _build_edge_output_path(self, language: str) -> Path:
        self._output_dir.mkdir(parents=True, exist_ok=True)
        return self._output_dir / f"{language.lower()}-{int(time.time() * 1000)}-{uuid.uuid4().hex[:8]}.mp3"

    def _synthesize_with_edge_tts(
        self,
        *,
        text: str,
        language: str,
        speed: float,
        volume: float,
        voice_override: str | None,
    ) -> Path:
        import edge_tts

        output_path = self._build_edge_output_path(language)
        voice = voice_override.strip() if voice_override is not None and voice_override.strip() else self._resolve_edge_voice(language)
        rate = self._edge_percent_value(speed)
        edge_volume = self._edge_percent_value(volume)

        async def _render() -> None:
            communicate = edge_tts.Communicate(
                text=text,
                voice=voice,
                rate=rate,
                volume=edge_volume,
            )
            await communicate.save(str(output_path))

        asyncio.run(_render())
        return output_path

    def _edge_percent_value(self, value: float) -> str:
        percent = int(round((value - 1.0) * 100))
        return f"{percent:+d}%"
