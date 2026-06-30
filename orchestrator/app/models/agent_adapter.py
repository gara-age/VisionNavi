from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from app.models.canonical_command import CanonicalCommand
from app.models.execution_backend import ExecutionBackend


@dataclass
class AgentAdapterRequest:
    command: CanonicalCommand
    observation: dict[str, object]
    policy_flags: dict[str, object] = field(default_factory=dict)


@dataclass
class AgentAdapterResponse:
    status: str
    execution_backend: ExecutionBackend
    result: dict[str, Any] | None = None
    raw_agent_trace: dict[str, Any] = field(default_factory=dict)
    normalized_agent_trace: list[dict[str, Any]] = field(default_factory=list)
    blocked_reason: str | None = None

