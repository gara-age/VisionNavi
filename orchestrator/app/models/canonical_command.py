from typing import Literal

from pydantic import BaseModel, Field


class CanonicalCommand(BaseModel):
    input_mode: Literal["voice", "text"]
    raw_text: str = Field(min_length=1)
    normalized_text: str = Field(min_length=1)
    task_domain: Literal["web", "desktop", "hybrid"]
    intent: str = Field(min_length=1)
    risk_level: Literal["low", "medium", "high"]
    requires_confirmation: bool
    target_app: str | None = None
    notes: list[str] = Field(default_factory=list)
