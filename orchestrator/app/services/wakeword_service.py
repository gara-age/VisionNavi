from __future__ import annotations

import asyncio
import concurrent.futures
import json
import time
from collections import deque
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from app.core.settings import Settings


@dataclass(frozen=True)
class WakeWordProfile:
    profile_id: str
    language: str
    phrase: str
    model_path: str


class WakeWordService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._task: asyncio.Task[None] | None = None
        self._stop_event: asyncio.Event | None = None
        self._running = False
        self._available: bool | None = None
        self._language: str | None = None
        self._profile: WakeWordProfile | None = None
        self._last_error: str | None = None
        self._last_detection_at: str | None = None
        self._pending_detection = False
        self._pending_detection_phrase: str | None = None
        self._threshold_override: float | None = None
        self._input_device_index: int | None = None
        self._input_device_name: str | None = None
        self._last_scores: dict[str, float] = {}

    def status(self) -> dict[str, Any]:
        profile = self._profile
        return {
            "backend": self._settings.wakeword_backend,
            "running": self._running,
            "available": self._is_backend_available(),
            "language": self._language,
            "profile_id": profile.profile_id if profile else None,
            "phrase": profile.phrase if profile else None,
            "model_path": str(self._model_path(profile)) if profile else None,
            "threshold": self._active_threshold(),
            "debounce_seconds": self._settings.wakeword_debounce_seconds,
            "last_error": self._last_error,
            "last_detection_at": self._last_detection_at,
            "pending_detection": self._pending_detection,
            "pending_detection_phrase": self._pending_detection_phrase,
            "input_device_index": self._input_device_index,
            "input_device_name": self._input_device_name,
            "last_scores": self._last_scores,
        }

    async def start_monitoring(
        self,
        *,
        language: str,
        phrase: str | None = None,
        profile_id: str | None = None,
        threshold: float | None = None,
    ) -> dict[str, Any]:
        if self._settings.wakeword_backend != "livekit-wakeword":
            raise RuntimeError(
                f"Unsupported wakeword backend: {self._settings.wakeword_backend}"
            )
        self._ensure_backend_available()

        profile = self._resolve_profile(
            language=language,
            phrase=phrase,
            profile_id=profile_id,
        )
        model_path = self._model_path(profile)
        if not model_path.exists():
            raise FileNotFoundError(
                f"Wakeword model not found for profile '{profile.profile_id}': {model_path}"
            )

        await self.stop_monitoring()
        self._running = True
        self._language = language
        self._profile = profile
        self._last_error = None
        self._pending_detection = False
        self._pending_detection_phrase = None
        self._threshold_override = threshold
        self._input_device_index, self._input_device_name = self._resolve_input_device()
        self._last_scores = {}
        self._stop_event = asyncio.Event()
        self._task = asyncio.create_task(self._run_listener(profile, model_path))
        return self.status()

    async def stop_monitoring(self) -> dict[str, Any]:
        if self._stop_event is not None:
            self._stop_event.set()
        task = self._task
        self._task = None
        if task is not None:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
            except Exception as exc:
                self._last_error = f"{type(exc).__name__}: {exc}"
        self._stop_event = None
        self._running = False
        self._pending_detection = False
        self._pending_detection_phrase = None
        self._threshold_override = None
        self._input_device_index = None
        self._input_device_name = None
        self._last_scores = {}
        return self.status()

    def _active_threshold(self) -> float:
        if self._threshold_override is None:
            return self._settings.wakeword_threshold
        return max(0.0, min(1.0, self._threshold_override))

    def acknowledge_detection(self) -> dict[str, Any]:
        self._pending_detection = False
        self._pending_detection_phrase = None
        return self.status()

    def _manifest_path(self) -> Path:
        return Path(self._settings.wakeword_manifest_path).expanduser()

    def _load_profiles(self) -> list[WakeWordProfile]:
        manifest_path = self._manifest_path()
        if not manifest_path.exists():
            raise FileNotFoundError(
                f"Wakeword manifest not found: {manifest_path}. "
                "Create runtime/wakewords/manifest.json from the example manifest."
            )
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
        profiles_raw = payload.get("profiles", [])
        profiles: list[WakeWordProfile] = []
        for item in profiles_raw:
            if not isinstance(item, dict):
                continue
            profiles.append(
                WakeWordProfile(
                    profile_id=str(item["id"]),
                    language=str(item["language"]).lower(),
                    phrase=str(item["phrase"]),
                    model_path=str(item["model_path"]),
                )
            )
        return profiles

    def _resolve_profile(
        self,
        *,
        language: str,
        phrase: str | None,
        profile_id: str | None,
    ) -> WakeWordProfile:
        profiles = self._load_profiles()
        filtered = [profile for profile in profiles if profile.language == language.lower()]
        if profile_id is not None:
            for profile in filtered:
                if profile.profile_id == profile_id:
                    return profile
            raise ValueError(f"Wakeword profile '{profile_id}' not found for language '{language}'")
        if phrase is not None:
            phrase_normalized = phrase.strip()
            for profile in filtered:
                if profile.phrase.strip() == phrase_normalized:
                    return profile
            raise ValueError(
                f"Wakeword phrase '{phrase}' is not registered for language '{language}'"
            )
        if filtered:
            return filtered[0]
        raise ValueError(f"No wakeword profiles available for language '{language}'")

    def _model_path(self, profile: WakeWordProfile | None) -> Path:
        if profile is None:
            return Path()
        return Path(profile.model_path).expanduser()

    def _is_backend_available(self) -> bool:
        if self._available is not None:
            return self._available
        try:
            from livekit.wakeword import WakeWordListener, WakeWordModel  # noqa: F401
        except Exception:
            self._available = False
        else:
            self._available = True
        return self._available

    def _ensure_backend_available(self) -> None:
        if not self._is_backend_available():
            raise RuntimeError(
                "livekit-wakeword is not installed. Install orchestrator dependencies again."
            )

    def _looks_like_remote_audio(self, name: str) -> bool:
        normalized = name.lower()
        return any(
            token in normalized
            for token in (
                "원격 오디오",
                "remote audio",
            )
        )

    def _resolve_input_device(self) -> tuple[int | None, str | None]:
        import pyaudio

        pa = pyaudio.PyAudio()
        try:
            devices: list[dict[str, Any]] = []
            for index in range(pa.get_device_count()):
                info = pa.get_device_info_by_index(index)
                if int(info.get("maxInputChannels", 0)) <= 0:
                    continue
                devices.append(
                    {
                        "index": int(info.get("index", index)),
                        "name": str(info.get("name", "")),
                        "default_sample_rate": float(info.get("defaultSampleRate", 0.0)),
                    }
                )

            try:
                default_info = pa.get_default_input_device_info()
            except Exception:
                default_info = None

            if default_info is not None:
                default_name = str(default_info.get("name", ""))
                default_index = int(default_info.get("index", 0))
                if not self._looks_like_remote_audio(default_name):
                    return default_index, default_name

            if not devices:
                return None, None

            def can_open(device_index: int) -> bool:
                stream = None
                try:
                    stream = pa.open(
                        format=pyaudio.paInt16,
                        channels=1,
                        rate=16000,
                        input=True,
                        frames_per_buffer=1280,
                        input_device_index=device_index,
                    )
                    return True
                except Exception:
                    return False
                finally:
                    if stream is not None:
                        try:
                            stream.stop_stream()
                        except Exception:
                            pass
                        try:
                            stream.close()
                        except Exception:
                            pass

            def score(device: dict[str, Any]) -> tuple[int, int]:
                name = str(device["name"])
                lowered = name.lower()
                positive = 0
                if any(
                    token in lowered
                    for token in (
                        "microsoft sound mapper",
                        "사운드 매퍼",
                        "primary sound capture driver",
                        "사운드 캡처 드라이버",
                    )
                ):
                    positive += 150
                if not self._looks_like_remote_audio(name):
                    positive += 100
                if any(token in lowered for token in ("hands-free", "수화기", "headset", "헤드셋")):
                    positive += 20
                if int(device["default_sample_rate"]) == 16000:
                    positive += 10
                return positive, -int(device["index"])

            sorted_devices = sorted(devices, key=score, reverse=True)
            for device in sorted_devices:
                if can_open(int(device["index"])):
                    return int(device["index"]), str(device["name"])

            if default_info is not None and can_open(int(default_info.get("index", 0))):
                return int(default_info.get("index", 0)), str(default_info.get("name", ""))

            return None, None
        finally:
            pa.terminate()

    async def _run_listener(self, profile: WakeWordProfile, model_path: Path) -> None:
        from livekit.wakeword import WakeWordModel
        import numpy as np
        import pyaudio

        sample_rate = 16000
        frame_samples = 1280
        chunk_seconds = 2.0
        chunk_frames = int(chunk_seconds * sample_rate / frame_samples)

        model = WakeWordModel(models=[str(model_path)])
        stop_event = self._stop_event
        if stop_event is None:
            return

        pa: pyaudio.PyAudio | None = None
        stream = None
        executor: concurrent.futures.ThreadPoolExecutor | None = None
        frame_buffer: deque[np.ndarray] = deque(maxlen=chunk_frames)

        try:
            pa = pyaudio.PyAudio()
            stream = pa.open(
                format=pyaudio.paInt16,
                channels=1,
                rate=sample_rate,
                input=True,
                frames_per_buffer=frame_samples,
                input_device_index=self._input_device_index,
            )
            executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)
            loop = asyncio.get_running_loop()
            last_detection_monotonic = 0.0

            while not stop_event.is_set():
                data = await loop.run_in_executor(
                    executor,
                    lambda: stream.read(frame_samples, exception_on_overflow=False),
                )
                if stop_event.is_set():
                    break

                frame = np.frombuffer(data, dtype=np.int16)
                frame_buffer.append(frame)
                if len(frame_buffer) < chunk_frames:
                    continue

                chunk = np.concatenate(list(frame_buffer))
                scores = await loop.run_in_executor(executor, model.predict, chunk)
                self._last_scores = {name: float(score) for name, score in scores.items()}

                now = time.monotonic()
                for _name, score in scores.items():
                    if score < self._active_threshold():
                        continue
                    if now - last_detection_monotonic < self._settings.wakeword_debounce_seconds:
                        continue

                    last_detection_monotonic = now
                    frame_buffer.clear()
                    self._pending_detection = True
                    self._pending_detection_phrase = profile.phrase
                    self._last_detection_at = datetime.now(UTC).isoformat()
                    break
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            self._last_error = f"{type(exc).__name__}: {exc}"
            self._running = False
            self._pending_detection = False
            self._pending_detection_phrase = None
        finally:
            if executor is not None:
                executor.shutdown(wait=True)
            if stream is not None:
                try:
                    stream.stop_stream()
                except Exception:
                    pass
                try:
                    stream.close()
                except Exception:
                    pass
            if pa is not None:
                try:
                    pa.terminate()
                except Exception:
                    pass
