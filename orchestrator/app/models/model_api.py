from typing import Literal

from pydantic import BaseModel, Field

from app.models.action_step import ActionPlan
from app.models.canonical_command import CanonicalCommand


class CanonicalCommandPredictionRequest(BaseModel):
    input_mode: Literal["voice", "text"]
    raw_text: str = Field(min_length=1)
    normalized_text: str = Field(min_length=1)


class CanonicalCommandPredictionResponse(BaseModel):
    normalized_text: str = Field(min_length=1)
    task_domain: Literal["web", "desktop", "hybrid"]
    intent: str = Field(min_length=1)
    target_app: str | None = None
    notes: list[str] = Field(default_factory=list)


class ActionPlanRequest(BaseModel):
    command: CanonicalCommand
    observation: dict[str, object] = Field(default_factory=dict)
    prior_steps: list[dict[str, object]] = Field(default_factory=list)
    last_result: dict[str, object] | None = None


class ActionPlanResponse(ActionPlan):
    pass
