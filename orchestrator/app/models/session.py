from typing import Any, Literal

from pydantic import BaseModel, Field

from app.models.canonical_command import CanonicalCommand


class SessionEvent(BaseModel):
    sequence: int
    type: str
    phase: str
    detail: str


class SessionSnapshot(BaseModel):
    session_id: str
    status: Literal["queued", "running", "completed", "failed", "canceled"]
    current_phase: str
    command: CanonicalCommand
    steps: list[dict[str, str]] = Field(default_factory=list)
    result: dict[str, Any] | None = None
    events: list[SessionEvent] = Field(default_factory=list)


class RunCommandResponse(BaseModel):
    session_id: str
    command: CanonicalCommand
    session: SessionSnapshot
