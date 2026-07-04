import asyncio
import re

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect

from app.agent.loop import AgentLoop
from app.core.build_info import get_build_info
from app.core.settings import Settings
from app.models.canonical_command import CanonicalCommand
from app.models.model_api import CanonicalCommandPredictionRequest
from app.models.model_api import PopupSummaryRequest, PopupSummaryResponse
from app.models.requests import (
    AudioDiagnosticsResponse,
    AudioTranscriptionRequest,
    AudioTranscriptionResponse,
    CommandRequest,
    PopupSummaryHttpRequest,
    RunCommandRequest,
    WakeWordStartRequest,
    WakeWordStatusResponse,
)
from app.models.session import RunCommandResponse, SessionSnapshot
from app.services.audio_diagnostics_service import AudioDiagnosticsService
from app.services.audio_transcription_service import AudioTranscriptionService
from app.services.command_normalizer import CommandNormalizer
from app.services.intent_router import IntentRouter
from app.services.map_route_parser import detect_map_provider
from app.services.model_client import RemoteModelClient
from app.services.safety_classifier import SafetyClassifier
from app.services.session_store import SessionStore
from app.services.wakeword_service import WakeWordService

router = APIRouter(prefix="/pipeline", tags=["pipeline"])

settings = Settings.from_env()
normalizer = CommandNormalizer()
router_service = IntentRouter()
safety_classifier = SafetyClassifier()
model_client = RemoteModelClient(settings)
agent_loop = AgentLoop()
session_store = SessionStore()
audio_transcription_service = AudioTranscriptionService(settings)
wakeword_service = WakeWordService(settings)
audio_diagnostics_service = AudioDiagnosticsService()


def build_canonical_command(request: CommandRequest) -> CanonicalCommand:
    command, _ = build_canonical_command_with_trace(request)
    return command


def build_canonical_command_with_trace(request: CommandRequest) -> tuple[CanonicalCommand, dict[str, object]]:
    normalized_text = normalizer.normalize(request.text)
    task_domain, intent, target_app, notes, route_trace = _route_command(
        request=request,
        normalized_text=normalized_text,
    )
    task_domain, intent, target_app, notes, harmonize_trace = _harmonize_command_route(
        task_domain,
        intent,
        target_app,
        notes,
        normalized_text=normalized_text,
    )
    risk_level = safety_classifier.classify(intent=intent, normalized_text=normalized_text)
    requires_confirmation = safety_classifier.requires_confirmation(
        intent=intent,
        risk_level=risk_level,
        normalized_text=normalized_text,
    )

    command = CanonicalCommand(
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
    trace = {
        "raw_text": request.text,
        "normalized_text": normalized_text,
        "routing": route_trace,
        "harmonization": harmonize_trace,
        "risk": {
            "risk_level": risk_level,
            "requires_confirmation": requires_confirmation,
        },
        "final_command": command.model_dump(),
    }
    return command, trace


def _route_command(
    request: CommandRequest,
    normalized_text: str,
) -> tuple[str, str, str | None, list[str], dict[str, object]]:
    notes: list[str] = []
    trace: dict[str, object] = {
        "request": {
            "input_mode": request.input_mode,
            "raw_text": request.text,
            "normalized_text_candidate": normalized_text,
        },
        "path": "rule_based_fallback",
    }

    try:
        trace["llm_debug"] = model_client.build_canonicalization_debug_payload(
            CanonicalCommandPredictionRequest(
                input_mode=request.input_mode,
                raw_text=request.text,
                normalized_text=normalized_text,
            )
        )
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
        trace["llm_error"] = f"{type(exc).__name__}: {exc}"

    if prediction is not None:
        notes.extend(["llm_assisted", *prediction.notes])
        trace["path"] = "llm_assisted"
        trace["llm_response"] = prediction.model_dump()
        return (
            prediction.task_domain,
            prediction.intent,
            prediction.target_app,
            notes,
            trace,
        )

    task_domain, intent, target_app = router_service.route(normalized_text)
    notes.append("rule_based_fallback")
    trace["rule_based_response"] = {
        "task_domain": task_domain,
        "intent": intent,
        "target_app": target_app,
    }
    return (task_domain, intent, target_app, notes, trace)


def _harmonize_command_route(
    task_domain: str,
    intent: str,
    target_app: str | None,
    notes: list[str],
    normalized_text: str | None = None,
) -> tuple[str, str, str | None, list[str], dict[str, object]]:
    resolved_domain = task_domain
    resolved_intent = intent
    resolved_target = target_app
    harmonized = False

    command_text = normalized_text or ""
    signal = _detect_command_signal(command_text)
    map_provider = detect_map_provider(command_text)

    if intent == "search_and_read":
        resolved_domain = "web"
        resolved_target = "browser"
        harmonized = resolved_domain != task_domain or resolved_target != target_app
    elif intent == "find_map_route":
        resolved_domain = "web"
        resolved_target = map_provider or "naver_map"
        harmonized = resolved_domain != task_domain or resolved_target != target_app
    elif intent == "open_notepad_and_type":
        resolved_domain = "desktop"
        resolved_target = "notepad"
        harmonized = resolved_domain != task_domain or resolved_target != target_app
    elif intent == "inspect_workspace_files":
        resolved_domain = "desktop"
        resolved_target = "file_explorer"
        harmonized = resolved_domain != task_domain or resolved_target != target_app
    elif intent == "change_system_setting":
        resolved_domain = "desktop"
        resolved_target = "windows_settings"
        harmonized = resolved_domain != task_domain or resolved_target != target_app
    elif intent == "general_assistance":
        if signal == "map_route":
            resolved_domain = "web"
            resolved_intent = "find_map_route"
            resolved_target = map_provider or "naver_map"
            harmonized = True
        elif signal == "web_search":
            resolved_domain = "web"
            resolved_target = "browser"
            harmonized = True
        elif signal == "local_lookup":
            resolved_domain = "desktop"
            resolved_target = "file_explorer"
            harmonized = True

    if harmonized:
        notes = [*notes, "route_harmonized"]

    trace = {
        "signal": signal,
        "original": {
            "task_domain": task_domain,
            "intent": intent,
            "target_app": target_app,
        },
        "resolved": {
            "task_domain": resolved_domain,
            "intent": resolved_intent,
            "target_app": resolved_target,
        },
        "harmonized": harmonized,
    }

    return (resolved_domain, resolved_intent, resolved_target, notes, trace)


def _detect_command_signal(normalized_text: str) -> str | None:
    text = normalized_text.lower().strip()
    if not text:
        return None

    local_markers = [
        "c:\\",
        "d:\\",
        "e:\\",
        "drive",
        "folder",
        "file",
        "photo",
        "picture",
        "document",
        "explorer",
        "desktop",
        "workspace",
        "\ub4dc\ub77c\uc774\ube0c",
        "\ud3f4\ub354",
        "\ud30c\uc77c",
        "\uc0ac\uc9c4",
        "\ubb38\uc11c",
        "\ud0d0\uc0c9\uae30",
        "\uc791\uc5c5\uacf5\uac04",
    ]
    web_markers = [
        "google",
        "naver",
        "naver map",
        "map",
        "youtube",
        "browser",
        "site",
        "web",
        "http://",
        "https://",
        "www.",
        "\uad6c\uae00",
        "\ub124\uc774\ubc84",
        "\ub124\uc774\ubc84 \uc9c0\ub3c4",
        "\uc9c0\ub3c4",
        "\uc720\ud29c\ube0c",
        "\ube0c\ub77c\uc6b0\uc800",
        "\uc0ac\uc774\ud2b8",
        "\uac80\uc0c9",
        "\uae38\ucc3e\uae30",
        "\uacbd\ub85c",
    ]
    lookup_markers = [
        "search",
        "find",
        "look up",
        "read",
        "\uac80\uc0c9",
        "\ucc3e\uc544",
        "\uc77d\uc5b4",
    ]

    has_local = any(marker in text for marker in local_markers)
    has_web = any(marker in text for marker in web_markers)
    has_lookup = any(marker in text for marker in lookup_markers)
    has_map_route = (
        any(marker in text for marker in ["naver map", "\ub124\uc774\ubc84 \uc9c0\ub3c4", "\uc9c0\ub3c4", "map"])
        and any(marker in text for marker in ["directions", "route", "\uae38\ucc3e\uae30", "\uacbd\ub85c"])
    )

    if has_local:
        return "local_lookup"
    if has_map_route and not has_local:
        return "map_route"
    if has_web and has_lookup:
        return "web_search"

    korean_web_pattern = re.search(
        r"(?:\uad6c\uae00|\ub124\uc774\ubc84|\uc720\ud29c\ube0c).+?(?:\uac80\uc0c9|\ucc3e\uc544|\uc77d\uc5b4)",
        text,
    )
    if korean_web_pattern and not has_local:
        return "web_search"

    korean_map_route_pattern = re.search(
        r"(?:\ub124\uc774\ubc84\s*\uc9c0\ub3c4|\uc9c0\ub3c4).+?(?:\uae38\ucc3e\uae30|\uacbd\ub85c)",
        text,
    )
    if korean_map_route_pattern and not has_local:
        return "map_route"

    korean_local_pattern = re.search(
        r"(?:[a-z]:\\|\ub4dc\ub77c\uc774\ube0c).+?(?:\ucc3e\uc544|\ud0d0\uc0c9|\uc5f4\uc5b4)",
        text,
    )
    if korean_local_pattern:
        return "local_lookup"

    return None


@router.post("/canonicalize", response_model=CanonicalCommand)
def canonicalize_command(request: CommandRequest) -> CanonicalCommand:
    return build_canonical_command(request)


@router.post("/run", response_model=RunCommandResponse)
async def run_command(request: RunCommandRequest) -> RunCommandResponse:
    if request.canonical_command is not None:
        command = request.canonical_command
        command_trace = {
            "source": "client_supplied_canonical_command",
            "final_command": command.model_dump(),
        }
    elif request.text:
        command, command_trace = build_canonical_command_with_trace(
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
    session = session_store.create(
        command=command,
        steps=plan["steps"],
        metadata={
            "canonicalization_trace": command_trace,
            "requested_execution_backend": request.execution_backend,
            "default_browser_execution_backend": settings.default_browser_execution_backend,
            "default_desktop_execution_backend": settings.default_desktop_execution_backend,
            "execution_channel_policy": "external_first",
            **get_build_info(),
        },
    )
    asyncio.create_task(
        agent_loop.run(
            session.session_id,
            command,
            session_store,
            requested_backend=request.execution_backend,
        )
    )
    latest_snapshot = session_store.get(session.session_id)
    return RunCommandResponse(
        session_id=latest_snapshot.session_id,
        command=command,
        session=latest_snapshot,
    )


@router.post("/transcribe-audio", response_model=AudioTranscriptionResponse)
def transcribe_audio(request: AudioTranscriptionRequest) -> AudioTranscriptionResponse:
    try:
        payload = audio_transcription_service.transcribe_file(
            request.file_path,
            language_hint=request.language_hint,
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Audio transcription failed: {exc}") from exc

    text = payload["text"]
    if not text:
        raise HTTPException(status_code=422, detail="Audio transcription produced no text")

    return AudioTranscriptionResponse(**payload)


@router.get("/wakeword/status", response_model=WakeWordStatusResponse)
def get_wakeword_status() -> WakeWordStatusResponse:
    return WakeWordStatusResponse(**wakeword_service.status())


@router.get("/audio-diagnostics", response_model=AudioDiagnosticsResponse)
def get_audio_diagnostics() -> AudioDiagnosticsResponse:
    try:
        payload = audio_diagnostics_service.collect()
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Audio diagnostics failed: {type(exc).__name__}: {exc}",
        ) from exc
    return AudioDiagnosticsResponse(**payload)


@router.post("/wakeword/start", response_model=WakeWordStatusResponse)
async def start_wakeword_monitoring(
    request: WakeWordStartRequest,
) -> WakeWordStatusResponse:
    try:
        payload = await wakeword_service.start_monitoring(
            language=request.language,
            phrase=request.phrase,
            profile_id=request.profile_id,
            threshold=request.threshold,
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Wakeword start failed: {exc}") from exc
    return WakeWordStatusResponse(**payload)


@router.post("/wakeword/stop", response_model=WakeWordStatusResponse)
async def stop_wakeword_monitoring() -> WakeWordStatusResponse:
    payload = await wakeword_service.stop_monitoring()
    return WakeWordStatusResponse(**payload)


@router.post("/wakeword/acknowledge", response_model=WakeWordStatusResponse)
def acknowledge_wakeword_detection() -> WakeWordStatusResponse:
    return WakeWordStatusResponse(**wakeword_service.acknowledge_detection())


@router.post("/popup-summary", response_model=PopupSummaryResponse)
def generate_popup_summary(request: PopupSummaryHttpRequest) -> PopupSummaryResponse:
    popup_context = _build_popup_summary_context(
        command=request.command,
        result=request.result,
        language=request.language,
    )
    response = model_client.summarize_popup(
        PopupSummaryRequest(
            command=request.command,
            language=request.language,
            result=request.result,
            popup_context=popup_context,
        )
    )
    if response is None:
        raise HTTPException(status_code=503, detail="Popup summary model is not enabled")
    return response


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
                            "payload": event.payload,
                            "status": snapshot.status,
                            "current_phase": snapshot.current_phase,
                            "result": snapshot.result,
                            "metadata": snapshot.metadata,
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


def _build_popup_summary_context(
    command: CanonicalCommand,
    result: dict[str, object],
    language: str,
) -> dict[str, object]:
    context: dict[str, object] = {
        "language": language,
        "intent": command.intent,
        "task_domain": command.task_domain,
        "target_app": command.target_app,
        "normalized_text": command.normalized_text,
        "result_status": str(result.get("status", "success")),
    }

    if command.intent == "search_and_read":
        context.update(
            {
                "result_title": _first_non_empty(
                    result.get("top_result_title"),
                    result.get("page_title"),
                ),
                "summary": _truncate_text(
                    _first_non_empty(
                        result.get("page_summary"),
                        result.get("summary"),
                        result.get("top_result_snippet"),
                    ),
                    160,
                ),
                "looks_like_welfare": _looks_like_welfare_query(command.normalized_text),
            }
        )
    elif command.intent == "find_map_route":
        context.update(
            {
                "origin": _extract_route_endpoint(command.normalized_text, kind="origin"),
                "destination": _extract_route_endpoint(command.normalized_text, kind="destination"),
                "transport": _detect_transport_mode(command.normalized_text),
                "fastest_duration": _extract_route_duration(result),
                "fare": _extract_route_fare(result),
            }
        )
    elif command.intent == "open_notepad_and_type":
        context.update(
            {
                "saved_file_path": result.get("file_path"),
                "observed_text_preview": _truncate_text(result.get("observed_text"), 100),
            }
        )
    elif command.intent == "inspect_workspace_files":
        directory_entries = result.get("directory_entries")
        if isinstance(directory_entries, list):
            context["entry_count"] = len(directory_entries)
    elif command.intent == "change_system_setting":
        context["setting_target"] = command.target_app or "windows_settings"

    return context


def _first_non_empty(*values: object) -> str | None:
    for value in values:
        if value is None:
            continue
        text = str(value).strip()
        if text:
            return text
    return None


def _truncate_text(value: object, max_length: int) -> str | None:
    if value is None:
        return None
    text = str(value).strip().replace("\n", " ")
    if not text:
        return None
    if len(text) <= max_length:
        return text
    return f"{text[: max_length - 3].rstrip()}..."


def _looks_like_welfare_query(text: str) -> bool:
    normalized = text.lower()
    keywords = [
        "복지",
        "지원",
        "보조금",
        "월세",
        "청년",
        "고령자",
        "시니어",
        "돌봄",
        "연금",
        "benefit",
        "support",
        "welfare",
        "senior",
        "care",
        "subsidy",
        "rent support",
    ]
    return any(keyword in normalized for keyword in keywords)


def _extract_route_endpoint(text: str, kind: str) -> str | None:
    if kind == "origin":
        match = re.search(r"(.+?)에서\s+(.+?)(?:까지|가는)", text)
        if match:
            return match.group(1).strip()
    else:
        match = re.search(r"에서\s+(.+?)(?:까지|가는)", text)
        if match:
            return match.group(1).strip()
    return None


def _detect_transport_mode(text: str) -> str | None:
    lowered = text.lower()
    if "지하철" in text or "subway" in lowered:
        return "subway"
    if "버스" in text or "bus" in lowered:
        return "bus"
    if "도보" in text or "walk" in lowered:
        return "walk"
    if "자동차" in text or "car" in lowered or "driving" in lowered:
        return "car"
    return None


def _extract_route_duration(result: dict[str, object]) -> str | None:
    for key in ("route_duration", "fastest_duration", "duration", "top_route_duration"):
        value = result.get(key)
        if value:
            return str(value).strip()

    observed_text = result.get("observed_text")
    if observed_text:
        match = re.search(r"(\d+\s*시간\s*\d+\s*분|\d+\s*시간|\d+\s*분)", str(observed_text))
        if match:
            return match.group(1).strip()
    return None


def _extract_route_fare(result: dict[str, object]) -> str | None:
    for key in ("fare", "route_fare", "top_route_fare"):
        value = result.get(key)
        if value:
            return str(value).strip()

    observed_text = result.get("observed_text")
    if observed_text:
        match = re.search(r"(\d[\d,]*\s*원)", str(observed_text))
        if match:
            return match.group(1).strip()
    return None
