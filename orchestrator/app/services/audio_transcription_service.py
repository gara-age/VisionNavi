from __future__ import annotations

import threading
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

from app.core.settings import Settings


class AudioTranscriptionService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._model: Any | None = None
        self._model_runtime: tuple[str, str] | None = None
        self._lock = threading.Lock()

    def transcribe_file(
        self,
        file_path: str,
        *,
        language_hint: str | None = None,
    ) -> dict[str, Any]:
        normalized_path = self._resolve_input_path(file_path)
        if not normalized_path.exists() or not normalized_path.is_file():
            raise FileNotFoundError(f"Audio file not found: {file_path}")

        normalized_language = self._normalize_language_hint(language_hint)
        segments, info = self._transcribe_with_retry(
            normalized_path,
            language=normalized_language,
        )

        text_parts: list[str] = []
        duration_seconds = 0.0
        for segment in segments:
            text = getattr(segment, "text", "").strip()
            if text:
                text_parts.append(text)
            duration_seconds = max(
                duration_seconds,
                float(getattr(segment, "end", 0.0) or 0.0),
            )

        return {
            "text": " ".join(text_parts).strip(),
            "detected_language": getattr(info, "language", None),
            "language_probability": getattr(info, "language_probability", None),
            "duration_seconds": duration_seconds or None,
            "file_path": str(normalized_path.resolve()),
            "model": self._settings.audio_transcription_model,
        }

    @staticmethod
    def _resolve_input_path(file_path: str) -> Path:
        value = file_path.strip().strip('"').strip("'")
        parsed = urlparse(value)
        if parsed.scheme == "file":
            resolved = unquote(parsed.path or "")
            if resolved.startswith("/") and len(resolved) >= 3 and resolved[2] == ":":
                resolved = resolved[1:]
            if parsed.netloc:
                resolved = f"//{parsed.netloc}{resolved}"
            value = resolved
        return Path(value).expanduser()

    def _get_model(self) -> Any:
        with self._lock:
            if self._model is not None:
                return self._model
            try:
                self._model = self._load_model(
                    device=self._settings.audio_transcription_device,
                    compute_type=self._settings.audio_transcription_compute_type,
                )
            except Exception as exc:
                if not self._should_fallback_to_cpu(
                    exc,
                    self._settings.audio_transcription_device,
                ):
                    raise
                self._model = self._load_model(device="cpu", compute_type="int8")
            return self._model

    def _load_model(self, *, device: str, compute_type: str) -> Any:
        try:
            from faster_whisper import WhisperModel
        except Exception as exc:  # pragma: no cover - import path
            raise RuntimeError(
                "faster-whisper is not installed. Install orchestrator dependencies again."
            ) from exc

        model = WhisperModel(
            self._settings.audio_transcription_model,
            device=device,
            compute_type=compute_type,
        )
        self._model_runtime = (device, compute_type)
        return model

    def _transcribe_with_retry(
        self,
        normalized_path: Path,
        *,
        language: str | None,
    ) -> tuple[list[Any], Any]:
        model = self._get_model()
        kwargs = {
            "language": language,
            "vad_filter": self._settings.audio_transcription_vad_filter,
            "beam_size": self._settings.audio_transcription_beam_size,
            "condition_on_previous_text": False,
        }

        try:
            segments, info = model.transcribe(str(normalized_path), **kwargs)
            return list(segments), info
        except Exception as exc:
            current_runtime = self._model_runtime or (
                self._settings.audio_transcription_device,
                self._settings.audio_transcription_compute_type,
            )
            if not self._should_fallback_to_cpu(exc, current_runtime[0]):
                raise

            with self._lock:
                self._model = self._load_model(device="cpu", compute_type="int8")

            segments, info = self._model.transcribe(str(normalized_path), **kwargs)
            return list(segments), info

    @staticmethod
    def _should_fallback_to_cpu(exc: Exception, requested_device: str) -> bool:
        lowered = str(exc).lower()
        if requested_device.lower() == "cpu":
            return False
        fallback_markers = (
            "cublas",
            "cuda",
            "cudnn",
            "cannot be loaded",
            "is not found",
            "failed to create cublas handle",
            "no cuda-capable device is detected",
        )
        return any(marker in lowered for marker in fallback_markers)

    @staticmethod
    def _normalize_language_hint(language_hint: str | None) -> str | None:
        if language_hint is None:
            return None
        value = language_hint.strip().lower()
        if not value or value == "auto":
            return None

        korean_aliases = {
            "ko",
            "ko-kr",
            "korean",
            "\ud55c\uad6d\uc5b4",
        }
        japanese_aliases = {
            "ja",
            "ja-jp",
            "jp",
            "japanese",
            "\u65e5\u672c\u8a9e",
            "\uc77c\ubcf8\uc5b4",
        }

        if value in korean_aliases or value.startswith("ko"):
            return "ko"
        if value in japanese_aliases or value.startswith("ja") or value.startswith("jp"):
            return "ja"
        return value
