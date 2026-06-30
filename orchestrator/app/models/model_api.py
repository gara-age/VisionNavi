from typing import Literal

from pydantic import BaseModel, Field

from app.models.action_step import ActionPlan, ActionStep
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


class RuntimeCandidate(BaseModel):
    candidate_id: str = Field(min_length=1)
    kind: Literal["clickable", "input", "result_region", "window", "unknown"] = "unknown"
    label: str | None = None
    role: str | None = None
    selector_hint: str | None = None
    text_preview: str | None = None
    score: float | None = None
    metadata: dict[str, object] = Field(default_factory=dict)


class NextActionRequest(BaseModel):
    command: CanonicalCommand
    observation: dict[str, object] = Field(default_factory=dict)
    candidate_targets: list[RuntimeCandidate] = Field(default_factory=list)
    history: list[dict[str, object]] = Field(default_factory=list)
    last_result: dict[str, object] | None = None


class NextActionResponse(BaseModel):
    step: ActionStep | None = None
    done: bool = False
    needs_recovery: bool = False
    choice_reason: str | None = None
    completion_reason: str | None = None
    notes: list[str] = Field(default_factory=list)


class VisionObservationRequest(BaseModel):
    command: CanonicalCommand
    observation: dict[str, object] = Field(default_factory=dict)


class VisionObservationResponse(BaseModel):
    summary: str = Field(min_length=1)
    task_state: str = Field(min_length=1)
    recommended_action: str | None = None
    confidence: float | None = None
    notes: list[str] = Field(default_factory=list)


class PopupSummaryRequest(BaseModel):
    command: CanonicalCommand
    language: Literal["ko", "ja"] = "ko"
    result: dict[str, object] = Field(default_factory=dict)
    popup_context: dict[str, object] = Field(default_factory=dict)


class PopupSummaryResponse(BaseModel):
    title: str = Field(min_length=1)
    message: str = Field(min_length=1)
    notes: list[str] = Field(default_factory=list)
