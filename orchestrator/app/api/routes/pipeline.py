import asyncio

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect

from app.agent.loop import AgentLoop
from app.core.settings import Settings
from app.models.canonical_command import CanonicalCommand
from app.models.model_api import CanonicalCommandPredictionRequest
from app.models.requests import CommandRequest, RunCommandRequest
from app.models.session import RunCommandResponse, SessionSnapshot
from app.services.command_normalizer import CommandNormalizer
from app.services.intent_router import IntentRouter
from app.services.model_client import RemoteModelClient
from app.services.safety_classifier import SafetyClassifier
from app.services.session_store import SessionStore

router = APIRouter(prefix="/pipeline", tags=["pipeline"])

settings = Settings.from_env()
normalizer = CommandNormalizer()
router_service = IntentRouter()
safety_classifier = SafetyClassifier()
model_client = RemoteModelClient(settings)
agent_loop = AgentLoop()
session_store = SessionStore()


def build_canonical_command(request: CommandRequest) -> CanonicalCommand:
    normalized_text = normalizer.normalize(request.text)
    task_domain, intent, target_app, notes = _route_command(
        request=request,
        normalized_text=normalized_text,
    )
    risk_level = safety_classifier.classify(intent=intent, normalized_text=normalized_text)
    requires_confirmation = safety_classifier.requires_confirmation(
        intent=intent,
        risk_level=risk_level,
        normalized_text=normalized_text,
    )

    return CanonicalCommand(
        input_mode=request.input_mode,
        raw_text=request.text,
        normalized_text=normalized_text,
        task_domain=task_domain,
        intent=intent,
        risk_level=risk_level,
        requires_confirmation=requires_confirmation,
        target_app=target_app,
        notes=notes,
    )


def _route_command(request: CommandRequest, normalized_text: str) -> tuple[str, str, str | None, list[str]]:
    notes: list[str] = []

    try:
        prediction = model_client.predict_canonical_command(
            CanonicalCommandPredictionRequest(
                input_mode=request.input_mode,
                raw_text=request.text,
                normalized_text=normalized_text,
            )
        )
    except Exception as exc:
        prediction = None
        notes.append(f"llm_fallback:{type(exc).__name__}")

    if prediction is not None:
        notes.extend(["llm_assisted", *prediction.notes])
        return (
            prediction.task_domain,
            prediction.intent,
            prediction.target_app,
            notes,
        )

    task_domain, intent, target_app = router_service.route(normalized_text)
    notes.append("rule_based_fallback")
    return (task_domain, intent, target_app, notes)


@router.post("/canonicalize", response_model=CanonicalCommand)
def canonicalize_command(request: CommandRequest) -> CanonicalCommand:
    return build_canonical_command(request)


@router.post("/run", response_model=RunCommandResponse)
async def run_command(request: RunCommandRequest) -> RunCommandResponse:
    if request.canonical_command is not None:
        command = request.canonical_command
    elif request.text:
        command = build_canonical_command(
            CommandRequest(
                input_mode=request.input_mode or "text",
                text=request.text,
            )
        )
    else:
        raise HTTPException(status_code=422, detail="Either text or canonical_command is required")

    if command.requires_confirmation and not request.confirmed:
        raise HTTPException(
            status_code=409,
            detail="This command requires explicit approval before execution",
        )

    plan = agent_loop.plan(command)
    session = session_store.create(command=command, steps=plan["steps"])
    asyncio.create_task(agent_loop.run(session.session_id, command, session_store))
    latest_snapshot = session_store.get(session.session_id)
    return RunCommandResponse(
        session_id=latest_snapshot.session_id,
        command=command,
        session=latest_snapshot,
    )


@router.get("/sessions/{session_id}", response_model=SessionSnapshot)
def get_session(session_id: str) -> SessionSnapshot:
    try:
        return session_store.get(session_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Session not found") from exc


@router.post("/sessions/{session_id}/stop", response_model=SessionSnapshot)
def stop_session(session_id: str) -> SessionSnapshot:
    try:
        session_store.cancel(session_id)
        session_store.append_event(
            session_id,
            event_type="session.stop_requested",
            phase="canceled",
            detail="Stop requested by user",
        )
        return session_store.get(session_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="Session not found") from exc


@router.websocket("/sessions/{session_id}/events")
async def stream_session_events(websocket: WebSocket, session_id: str) -> None:
    await websocket.accept()

    try:
        session_store.get(session_id)
    except KeyError:
        await websocket.send_json({"type": "error", "detail": "Session not found"})
        await websocket.close(code=1008)
        return

    last_sequence = 0

    try:
        while True:
            snapshot = session_store.get(session_id)

            for event in snapshot.events:
                if event.sequence > last_sequence:
                    await websocket.send_json(
                        {
                            "session_id": session_id,
                            "sequence": event.sequence,
                            "type": event.type,
                            "phase": event.phase,
                            "detail": event.detail,
                            "status": snapshot.status,
                            "current_phase": snapshot.current_phase,
                            "result": snapshot.result,
                        }
                    )
                    last_sequence = event.sequence

            if snapshot.status in {"completed", "failed", "canceled"} and last_sequence >= len(snapshot.events):
                break

            await asyncio.sleep(0.1)
    except WebSocketDisconnect:
        return
    finally:
        await websocket.close()
