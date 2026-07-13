from typing import Literal

from pydantic import BaseModel, Field

from app.models.canonical_command import CanonicalCommand
from app.models.execution_backend import ExecutionBackend


class CommandRequest(BaseModel):
    input_mode: Literal["voice", "text"] = "text"
    text: str = Field(min_length=1)
    preferred_language: Literal["ko", "ja", "en", "unknown"] | None = None


class RunCommandRequest(BaseModel):
    input_mode: Literal["voice", "text"] | None = "text"
    text: str | None = None
    preferred_language: Literal["ko", "ja", "en", "unknown"] | None = None
    canonical_command: CanonicalCommand | None = None
    confirmed: bool = False
    execution_backend: ExecutionBackend | None = None


class AudioTranscriptionRequest(BaseModel):
    file_path: str = Field(min_length=1)
    language_hint: str | None = None


class AudioTranscriptionResponse(BaseModel):
    text: str
    normalized_text: str
    detected_language: str | None = None
    language_probability: float | None = None
    duration_seconds: float | None = None
    file_path: str
    model: str


class WakeWordStartRequest(BaseModel):
    language: Literal["ko", "ja"] = "ko"
    phrase: str | None = None
    profile_id: str | None = None
    threshold: float | None = None


class WakeWordStatusResponse(BaseModel):
    backend: str = "livekit-wakeword"
    running: bool = False
    available: bool = False
    language: Literal["ko", "ja"] | None = None
    profile_id: str | None = None
    phrase: str | None = None
    model_path: str | None = None
    threshold: float | None = None
    debounce_seconds: float | None = None
    last_error: str | None = None
    last_detection_at: str | None = None
    pending_detection: bool = False
    pending_detection_phrase: str | None = None
    input_device_index: int | None = None
    input_device_name: str | None = None
    last_scores: dict[str, float] = Field(default_factory=dict)


class AudioDiagnosticEndpoint(BaseModel):
    status: str
    class_name: str = Field(alias="class")
    friendly_name: str
    instance_id: str

    model_config = {"populate_by_name": True}


class AudioDiagnosticsSummary(BaseModel):
    ok_count: int = 0
    unknown_count: int = 0
    remote_audio_count: int = 0
    input_candidate_count: int = 0
    has_any_ok_endpoint: bool = False
    has_ok_input_candidate: bool = False


class AudioDiagnosticsResponse(BaseModel):
    platform: str = "windows"
    input_endpoints: list[AudioDiagnosticEndpoint] = Field(default_factory=list)
    summary: AudioDiagnosticsSummary = Field(default_factory=AudioDiagnosticsSummary)
    error: str | None = None


class PopupSummaryHttpRequest(BaseModel):
    command: CanonicalCommand
    language: Literal["ko", "ja"] = "ko"
    result: dict[str, object] = Field(default_factory=dict)


class GuidanceTtsRequest(BaseModel):
    text: str = Field(min_length=1)
    language: Literal["ko", "ja"] = "ko"
    provider: Literal["edge"] | None = None
    voice: str | None = None
    speed: float = Field(default=1.0, ge=0.7, le=1.3)
    volume: float = Field(default=1.0, ge=0.7, le=1.3)


class GuidanceTtsResponse(BaseModel):
    ok: bool = False
    provider: str = "edge"
    voice: str | None = None
    device: str | None = None
    audio_path: str | None = None
    detail: str | None = None
