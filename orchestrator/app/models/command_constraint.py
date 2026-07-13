from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


ConstraintProvider = Literal[
    "naver",
    "google",
    "youtube",
    "naver_map",
    "kakao_map",
    "browser",
    "desktop",
    "unknown",
]

ConstraintLanguage = Literal["ko", "ja", "en", "unknown"]
ConstraintSource = Literal["rule_extracted", "llm_extracted", "harmonized"]
ConstraintViolation = Literal[
    "provider_mismatch",
    "query_changed",
    "unexpected_language",
    "slot_rewritten",
    "unsupported_constraint_extraction",
    "constraint_repair_failed",
]


class RouteConstraintContext(BaseModel):
    origin: str | None = None
    destination: str | None = None
    transport_mode: str | None = None
    route_kind: str | None = None


class CommandConstraint(BaseModel):
    provider: ConstraintProvider = "unknown"
    query_text: str = ""
    expected_language: ConstraintLanguage = "unknown"
    allow_provider_switch: bool = False
    allow_query_rewrite: bool = False
    allow_language_shift: bool = False
    allow_cross_provider_fallback: bool = False
    source: ConstraintSource = "rule_extracted"
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    route_context: RouteConstraintContext | None = None


class CommandValidationResult(BaseModel):
    ok: bool = True
    attempted_repair: bool = False
    failure_reason: str | None = None
    detected_provider: ConstraintProvider = "unknown"
    detected_query: str = ""
    detected_language: ConstraintLanguage = "unknown"
    violations: list[ConstraintViolation] = Field(default_factory=list)
    repaired_command: dict[str, object] | None = None
    notes: list[str] = Field(default_factory=list)
