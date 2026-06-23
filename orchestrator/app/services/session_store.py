from copy import deepcopy
from typing import Any
from uuid import uuid4

from app.models.canonical_command import CanonicalCommand
from app.models.session import SessionEvent, SessionSnapshot


class SessionStore:
    def __init__(self) -> None:
        self._sessions: dict[str, SessionSnapshot] = {}

    def create(self, command: CanonicalCommand, steps: list[dict[str, str]]) -> SessionSnapshot:
        session_id = str(uuid4())
        snapshot = SessionSnapshot(
            session_id=session_id,
            status="queued",
            current_phase="queued",
            command=command,
            steps=steps,
        )
        self._sessions[session_id] = snapshot
        self.append_event(
            session_id,
            event_type="session.queued",
            phase="queued",
            detail="Session created and waiting to start",
        )
        return self.get(session_id)

    def get(self, session_id: str) -> SessionSnapshot:
        snapshot = self._sessions[session_id]
        return SessionSnapshot.model_validate(deepcopy(snapshot.model_dump()))

    def mark_running(self, session_id: str) -> None:
        self._sessions[session_id].status = "running"

    def update_phase(self, session_id: str, phase: str) -> None:
        self._sessions[session_id].current_phase = phase

    def complete(self, session_id: str, result: dict[str, Any]) -> None:
        snapshot = self._sessions[session_id]
        snapshot.status = "completed"
        snapshot.current_phase = "complete"
        snapshot.result = result

    def fail(self, session_id: str, result: dict[str, Any]) -> None:
        snapshot = self._sessions[session_id]
        snapshot.status = "failed"
        snapshot.current_phase = "complete"
        snapshot.result = result

    def cancel(self, session_id: str) -> None:
        snapshot = self._sessions[session_id]
        snapshot.status = "canceled"
        snapshot.current_phase = "canceled"

    def is_canceled(self, session_id: str) -> bool:
        return self._sessions[session_id].status == "canceled"

    def append_event(self, session_id: str, event_type: str, phase: str, detail: str) -> SessionEvent:
        snapshot = self._sessions[session_id]
        event = SessionEvent(
            sequence=len(snapshot.events) + 1,
            type=event_type,
            phase=phase,
            detail=detail,
        )
        snapshot.events.append(event)
        return event
