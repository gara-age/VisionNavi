from typing import Literal

from pydantic import BaseModel, Field

from app.models.canonical_command import CanonicalCommand
from app.models.execution_backend import ExecutionBackend


class CommandRequest(BaseModel):
    input_mode: Literal["voice", "text"] = "text"
    text: str = Field(min_length=1)


class RunCommandRequest(BaseModel):
    input_mode: Literal["voice", "text"] | None = "text"
    text: str | None = None
    canonical_command: CanonicalCommand | None = None
    confirmed: bool = False
    execution_backend: ExecutionBackend | None = None


class AudioTranscriptionRequest(BaseModel):
    file_path: str = Field(min_length=1)
    language_hint: str | None = None


class AudioTranscriptionResponse(BaseModel):
    text: str
    detected_language: str | None = None
    language_probability: float | None = None
    duration_seconds: float | None = None
    file_path: str
    model: str


class PopupSummaryHttpRequest(BaseModel):
    command: CanonicalCommand
    language: Literal["ko", "ja"] = "ko"
    result: dict[str, object] = Field(default_factory=dict)
