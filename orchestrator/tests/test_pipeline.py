from fastapi.testclient import TestClient

from app.api.routes import pipeline
from app.agent.loop import AgentLoop
from app.main import app
from app.models.action_step import ActionStep
from app.models.canonical_command import CanonicalCommand
from app.models.model_api import CanonicalCommandPredictionResponse, PopupSummaryResponse


client = TestClient(app)


class FakeModelClient:
    def __init__(
        self,
        response: CanonicalCommandPredictionResponse | None = None,
        should_fail: bool = False,
        popup_response: PopupSummaryResponse | None = None,
    ) -> None:
        self.response = response
        self.should_fail = should_fail
        self.popup_response = popup_response

    def build_canonicalization_debug_payload(self, request):  # noqa: ANN001
        return {"request": request.model_dump(), "provider": "fake"}

    def predict_canonical_command(self, request):  # noqa: ANN001
        if self.should_fail:
            raise RuntimeError("model unavailable")
        return self.response

    def summarize_popup(self, request):  # noqa: ANN001
        if self.should_fail:
            raise RuntimeError("model unavailable")
        if self.popup_response is not None:
            return self.popup_response
        return PopupSummaryResponse(
            title="Mock Popup Title",
            message=f"intent={request.command.intent}",
            notes=["fake_popup"],
        )


class FakeAudioTranscriptionService:
    def __init__(self, text: str = "서울시 청년 지원 조건 알려줘", should_fail: bool = False) -> None:
        self.text = text
        self.should_fail = should_fail

    def transcribe_file(self, file_path: str, *, language_hint: str | None = None):  # noqa: ANN001
        if self.should_fail:
            raise RuntimeError("transcriber unavailable")
        if file_path == "missing.wav":
            raise FileNotFoundError(f"Audio file not found: {file_path}")
        return {
            "text": self.text,
            "detected_language": "ko",
            "language_probability": 0.99,
            "duration_seconds": 2.5,
            "file_path": file_path,
            "model": "small",
        }


def test_health_check() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ok"
    assert "server_build_id" in payload
    assert "server_started_at_utc" in payload
    assert "server_code_signature" in payload


def test_canonicalize_dark_mode_command() -> None:
    response = client.post(
        "/pipeline/canonicalize",
        json={"input_mode": "voice", "text": "윈도우를 다크모드로 바꿔줘"},
    )
    assert response.status_code == 200

    payload = response.json()
    assert payload["task_domain"] == "desktop"
    assert payload["intent"] == "change_system_setting"
    assert payload["risk_level"] == "medium"
    assert payload["requires_confirmation"] is False


def test_canonicalize_non_dark_setting_requires_confirmation() -> None:
    response = client.post(
        "/pipeline/canonicalize",
        json={"input_mode": "text", "text": "Change Windows theme to light mode"},
    )
    assert response.status_code == 200

    payload = response.json()
    assert payload["risk_level"] == "medium"
    assert payload["requires_confirmation"] is True


def test_canonicalize_kakao_map_route_preserves_kakao_target() -> None:
    response = client.post(
        "/pipeline/canonicalize",
        json={
            "input_mode": "text",
            "text": "\uce74\uce74\uc624\ub9f5\uc5d0\uc11c \uc11c\uc6b8\uc5ed\uc5d0\uc11c \uc1a1\ub0b4\uc5ed \uac00\ub294 \uacbd\ub85c \ucc3e\uc544\uc918",
        },
    )
    assert response.status_code == 200

    payload = response.json()
    assert payload["intent"] == "find_map_route"
    assert payload["target_app"] == "kakao_map"


def test_run_search_command_uses_browser_path() -> None:
    response = client.post(
        "/pipeline/run",
        json={"input_mode": "text", "text": "네이버에서 인천 청년 월세 지원 찾아줘"},
    )
    assert response.status_code == 200

    payload = response.json()
    assert payload["command"]["task_domain"] == "web"
    assert payload["session"]["status"] == "queued"
    assert payload["session"]["result"] is None
    assert "server_build_id" in payload["session"]["metadata"]


def test_transcribe_audio_file_returns_text() -> None:
    original_service = pipeline.audio_transcription_service
    pipeline.audio_transcription_service = FakeAudioTranscriptionService()
    try:
        response = client.post(
            "/pipeline/transcribe-audio",
            json={"file_path": "sample.wav", "language_hint": "한국어"},
        )
    finally:
        pipeline.audio_transcription_service = original_service

    assert response.status_code == 200
    payload = response.json()
    assert payload["text"] == "서울시 청년 지원 조건 알려줘"
    assert payload["detected_language"] == "ko"
    assert payload["file_path"] == "sample.wav"


def test_transcribe_audio_file_missing_returns_404() -> None:
    original_service = pipeline.audio_transcription_service
    pipeline.audio_transcription_service = FakeAudioTranscriptionService()
    try:
        response = client.post(
            "/pipeline/transcribe-audio",
            json={"file_path": "missing.wav"},
        )
    finally:
        pipeline.audio_transcription_service = original_service

    assert response.status_code == 404


def test_popup_summary_returns_structured_response() -> None:
    original_client = pipeline.model_client
    pipeline.model_client = FakeModelClient(
        popup_response=PopupSummaryResponse(
            title="복지 정보를 찾았어요",
            message="지원 조건과 확인할 내용을 준비했어요.",
            notes=["fake_popup"],
        )
    )
    try:
        response = client.post(
            "/pipeline/popup-summary",
            json={
                "command": {
                    "input_mode": "text",
                    "raw_text": "Search Naver for Incheon youth monthly rent support and read the conditions.",
                    "normalized_text": "Search Naver for Incheon youth monthly rent support and read the conditions.",
                    "task_domain": "web",
                    "intent": "search_and_read",
                    "risk_level": "low",
                    "requires_confirmation": False,
                    "target_app": "browser",
                    "notes": ["test"],
                },
                "language": "ko",
                "result": {
                    "status": "success",
                    "top_result_title": "Incheon Youth Monthly Rent Support",
                    "page_summary": "Eligibility, support amount, and application timing were extracted.",
                },
            },
        )
    finally:
        pipeline.model_client = original_client

    assert response.status_code == 200
    payload = response.json()
    assert payload["title"] == "복지 정보를 찾았어요"
    assert payload["message"] == "지원 조건과 확인할 내용을 준비했어요."
    assert payload["notes"] == ["fake_popup"]


def test_build_popup_summary_context_marks_welfare_query() -> None:
    command = CanonicalCommand(
        input_mode="text",
        raw_text="Search Naver for Incheon youth monthly rent support and read the conditions.",
        normalized_text="Search Naver for Incheon youth monthly rent support and read the conditions.",
        task_domain="web",
        intent="search_and_read",
        risk_level="low",
        requires_confirmation=False,
        target_app="browser",
        notes=["test"],
    )

    context = pipeline._build_popup_summary_context(  # noqa: SLF001
        command=command,
        result={
            "status": "success",
            "top_result_title": "Incheon Youth Monthly Rent Support",
            "page_summary": "Eligibility, support amount, and application timing were extracted.",
        },
        language="ko",
    )

    assert context["intent"] == "search_and_read"
    assert context["result_title"] == "Incheon Youth Monthly Rent Support"
    assert context["looks_like_welfare"] is True


def test_build_popup_summary_context_extracts_route_fields() -> None:
    command = CanonicalCommand(
        input_mode="text",
        raw_text="Find the subway route from Seoul Station to Songnae Station on Naver Map.",
        normalized_text="Find the subway route from Seoul Station to Songnae Station on Naver Map.",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="naver_map",
        notes=["test"],
    )

    context = pipeline._build_popup_summary_context(  # noqa: SLF001
        command=command,
        result={
            "status": "success",
            "fastest_duration": "1 hour 30 minutes",
            "fare": "1,850 KRW",
        },
        language="ko",
    )

    assert context["intent"] == "find_map_route"
    assert context["transport"] == "subway"
    assert context["fastest_duration"] == "1 hour 30 minutes"
    assert context["fare"] == "1,850 KRW"


def test_run_rejects_unconfirmed_high_risk_command() -> None:
    response = client.post(
        "/pipeline/run",
        json={
            "canonical_command": {
                "input_mode": "text",
                "raw_text": "Send my personal account details",
                "normalized_text": "Send my personal account details",
                "task_domain": "hybrid",
                "intent": "general_assistance",
                "risk_level": "high",
                "requires_confirmation": True,
                "target_app": None,
                "notes": ["llm_assisted"],
            }
        },
    )

    assert response.status_code == 409
    assert "requires explicit approval" in response.json()["detail"]


def test_run_accepts_confirmed_high_risk_command() -> None:
    response = client.post(
        "/pipeline/run",
        json={
            "canonical_command": {
                "input_mode": "text",
                "raw_text": "Send my personal account details",
                "normalized_text": "Send my personal account details",
                "task_domain": "hybrid",
                "intent": "general_assistance",
                "risk_level": "high",
                "requires_confirmation": True,
                "target_app": None,
                "notes": ["llm_assisted"],
            },
            "confirmed": True,
        },
    )

    assert response.status_code == 200
    assert response.json()["session"]["status"] == "queued"


def test_plan_actions_builds_kakao_map_route_steps() -> None:
    loop = AgentLoop()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="\uce74\uce74\uc624\ub9f5\uc5d0\uc11c \uc11c\uc6b8\uc5ed\uc5d0\uc11c \uc1a1\ub0b4\uc5ed \uac00\ub294 \uacbd\ub85c \ucc3e\uc544\uc918",
        normalized_text="\uce74\uce74\uc624\ub9f5\uc5d0\uc11c \uc11c\uc6b8\uc5ed\uc5d0\uc11c \uc1a1\ub0b4\uc5ed \uac00\ub294 \uacbd\ub85c \ucc3e\uc544\uc918",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="kakao_map",
        notes=["test"],
    )
    planned_steps, notes, trace = loop._plan_actions(  # noqa: SLF001
        command,
        loop.browser_executor.observe(command),  # noqa: SLF001
    )

    assert notes == ["structured_map_route"]
    assert trace["route_request"]["provider"] == "kakao_map"
    assert any(
        step.action == "open_browser_url" and step.target == "https://map.kakao.com/?target=car"
        for step in planned_steps
    )
    assert any(step.action == "click_element" and step.target == "#transit" for step in planned_steps)


def test_run_accepts_canonical_command() -> None:
    response = client.post(
        "/pipeline/run",
        json={
            "canonical_command": {
                "input_mode": "text",
                "raw_text": "Change Windows to dark mode",
                "normalized_text": "Change Windows to dark mode",
                "task_domain": "desktop",
                "intent": "change_system_setting",
                "risk_level": "medium",
                "requires_confirmation": False,
                "target_app": "windows_settings",
                "notes": ["llm_assisted", "ollama_qwen2_5_14b"],
            }
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["command"]["intent"] == "change_system_setting"
    assert "ollama_qwen2_5_14b" in payload["command"]["notes"]
    assert payload["session"]["metadata"]["canonicalization_trace"]["source"] == "client_supplied_canonical_command"


def test_canonicalize_uses_llm_prediction_when_available() -> None:
    original_client = pipeline.model_client
    pipeline.model_client = FakeModelClient(
        response=CanonicalCommandPredictionResponse(
            normalized_text="Windows dark mode",
            task_domain="desktop",
            intent="change_system_setting",
            target_app="windows_settings",
            notes=["remote_model"],
        )
    )
    try:
        response = client.post(
            "/pipeline/canonicalize",
            json={"input_mode": "text", "text": "Change Windows to dark mode"},
        )
    finally:
        pipeline.model_client = original_client

    assert response.status_code == 200
    payload = response.json()
    assert payload["task_domain"] == "desktop"
    assert payload["intent"] == "change_system_setting"
    assert "llm_assisted" in payload["notes"]


def test_canonicalize_harmonizes_inconsistent_llm_route() -> None:
    original_client = pipeline.model_client
    pipeline.model_client = FakeModelClient(
        response=CanonicalCommandPredictionResponse(
            normalized_text="Search Naver for rent support",
            task_domain="hybrid",
            intent="search_and_read",
            target_app=None,
            notes=["remote_model"],
        )
    )
    try:
        response = client.post(
            "/pipeline/canonicalize",
            json={"input_mode": "text", "text": "Search Naver for rent support"},
        )
    finally:
        pipeline.model_client = original_client

    assert response.status_code == 200
    payload = response.json()
    assert payload["task_domain"] == "web"
    assert payload["target_app"] == "browser"
    assert "route_harmonized" in payload["notes"]


def test_canonicalize_harmonizes_korean_web_search_when_llm_is_generic() -> None:
    original_client = pipeline.model_client
    pipeline.model_client = FakeModelClient(
        response=CanonicalCommandPredictionResponse(
            normalized_text="구글에서 유튜브 검색해줘",
            task_domain="hybrid",
            intent="general_assistance",
            target_app=None,
            notes=["remote_model"],
        )
    )
    try:
        response = client.post(
            "/pipeline/canonicalize",
            json={"input_mode": "text", "text": "구글에서 유튜브 검색해줘"},
        )
    finally:
        pipeline.model_client = original_client

    assert response.status_code == 200
    payload = response.json()
    assert payload["task_domain"] == "web"
    assert payload["target_app"] == "browser"
    assert payload["intent"] == "general_assistance"
    assert "route_harmonized" in payload["notes"]


def test_canonicalize_keeps_local_lookup_as_desktop_when_llm_is_generic() -> None:
    original_client = pipeline.model_client
    pipeline.model_client = FakeModelClient(
        response=CanonicalCommandPredictionResponse(
            normalized_text="C드라이브에서 사진 찾아줘",
            task_domain="hybrid",
            intent="general_assistance",
            target_app=None,
            notes=["remote_model"],
        )
    )
    try:
        response = client.post(
            "/pipeline/canonicalize",
            json={"input_mode": "text", "text": "C드라이브에서 사진 찾아줘"},
        )
    finally:
        pipeline.model_client = original_client

    assert response.status_code == 200
    payload = response.json()
    assert payload["task_domain"] == "desktop"
    assert payload["target_app"] == "file_explorer"
    assert payload["intent"] == "general_assistance"
    assert "route_harmonized" in payload["notes"]


def test_canonicalize_falls_back_to_rules_when_llm_fails() -> None:
    original_client = pipeline.model_client
    pipeline.model_client = FakeModelClient(should_fail=True)
    try:
        response = client.post(
            "/pipeline/canonicalize",
            json={"input_mode": "text", "text": "Search Naver for rent support"},
        )
    finally:
        pipeline.model_client = original_client

    assert response.status_code == 200
    payload = response.json()
    assert payload["task_domain"] == "web"
    assert "rule_based_fallback" in payload["notes"]


def test_run_session_includes_canonicalization_trace_metadata() -> None:
    original_client = pipeline.model_client
    pipeline.model_client = FakeModelClient(
        response=CanonicalCommandPredictionResponse(
            normalized_text="Search Google for YouTube",
            task_domain="web",
            intent="search_and_read",
            target_app="browser",
            notes=["remote_model"],
        )
    )
    try:
        response = client.post(
            "/pipeline/run",
            json={"input_mode": "text", "text": "구글에서 유튜브 검색해줘"},
        )
    finally:
        pipeline.model_client = original_client

    assert response.status_code == 200
    payload = response.json()
    trace = payload["session"]["metadata"]["canonicalization_trace"]
    assert trace["routing"]["path"] == "llm_assisted"
    assert trace["final_command"]["intent"] == "search_and_read"


def test_canonicalize_workspace_file_command_routes_to_desktop_explorer() -> None:
    response = client.post(
        "/pipeline/canonicalize",
        json={"input_mode": "text", "text": "Open file explorer for the VisionNavi workspace and list files"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["task_domain"] == "desktop"
    assert payload["intent"] == "inspect_workspace_files"
    assert payload["target_app"] == "file_explorer"


def test_canonicalize_korean_google_search_routes_to_web_browser() -> None:
    original_client = pipeline.model_client
    pipeline.model_client = FakeModelClient(
        response=CanonicalCommandPredictionResponse(
            normalized_text="\uad6c\uae00\uc5d0\uc11c \uc720\ud29c\ube0c \uac80\uc0c9\ud574\uc918",
            task_domain="hybrid",
            intent="general_assistance",
            target_app=None,
            notes=["remote_model"],
        )
    )
    try:
        response = client.post(
            "/pipeline/canonicalize",
            json={"input_mode": "text", "text": "\uad6c\uae00\uc5d0\uc11c \uc720\ud29c\ube0c \uac80\uc0c9\ud574\uc918"},
        )
    finally:
        pipeline.model_client = original_client

    assert response.status_code == 200
    payload = response.json()
    assert payload["task_domain"] == "web"
    assert payload["target_app"] == "browser"
    assert "route_harmonized" in payload["notes"]


def test_canonicalize_korean_local_drive_lookup_stays_desktop() -> None:
    original_client = pipeline.model_client
    pipeline.model_client = FakeModelClient(
        response=CanonicalCommandPredictionResponse(
            normalized_text="c\ub4dc\ub77c\uc774\ube0c\uc5d0\uc11c \uc0ac\uc9c4 \ucc3e\uc544\uc918",
            task_domain="hybrid",
            intent="general_assistance",
            target_app=None,
            notes=["remote_model"],
        )
    )
    try:
        response = client.post(
            "/pipeline/canonicalize",
            json={"input_mode": "text", "text": "C\ub4dc\ub77c\uc774\ube0c\uc5d0\uc11c \uc0ac\uc9c4 \ucc3e\uc544\uc918"},
        )
    finally:
        pipeline.model_client = original_client

    assert response.status_code == 200
    payload = response.json()
    assert payload["task_domain"] == "desktop"
    assert payload["target_app"] == "file_explorer"
    assert "route_harmonized" in payload["notes"]


def test_canonicalize_korean_youtube_lookup_routes_to_web_browser() -> None:
    original_client = pipeline.model_client
    pipeline.model_client = FakeModelClient(
        response=CanonicalCommandPredictionResponse(
            normalized_text="\uc720\ud29c\ube0c\uc5d0\uc11c \uc544\uc774\ube0c \ubba4\ube44 \ucc3e\uc544\uc918",
            task_domain="hybrid",
            intent="general_assistance",
            target_app=None,
            notes=["remote_model"],
        )
    )
    try:
        response = client.post(
            "/pipeline/canonicalize",
            json={"input_mode": "text", "text": "\uc720\ud29c\ube0c\uc5d0\uc11c \uc544\uc774\ube0c \ubba4\ube44 \ucc3e\uc544\uc918"},
        )
    finally:
        pipeline.model_client = original_client

    assert response.status_code == 200
    payload = response.json()
    assert payload["task_domain"] == "web"
    assert payload["target_app"] == "browser"
    assert "route_harmonized" in payload["notes"]


def test_canonicalize_korean_naver_map_route_uses_map_route_intent() -> None:
    original_client = pipeline.model_client
    pipeline.model_client = FakeModelClient(
        response=CanonicalCommandPredictionResponse(
            normalized_text="\ub124\uc774\ubc84 \uc9c0\ub3c4\uc5d0\uc11c \uc11c\uc6b8\uc5ed\uc5d0\uc11c \uc1a1\ub0b4\uc5ed\uac00\ub294 \uacbd\ub85c \ucc3e\uc544\uc918",
            task_domain="hybrid",
            intent="general_assistance",
            target_app=None,
            notes=["remote_model"],
        )
    )
    try:
        response = client.post(
            "/pipeline/canonicalize",
            json={
                "input_mode": "text",
                "text": "\ub124\uc774\ubc84 \uc9c0\ub3c4\uc5d0\uc11c \uc11c\uc6b8\uc5ed\uc5d0\uc11c \uc1a1\ub0b4\uc5ed\uac00\ub294 \uacbd\ub85c \ucc3e\uc544\uc918",
            },
        )
    finally:
        pipeline.model_client = original_client

    assert response.status_code == 200
    payload = response.json()
    assert payload["task_domain"] == "web"
    assert payload["intent"] == "find_map_route"
    assert payload["target_app"] == "naver_map"
    assert "route_harmonized" in payload["notes"]


def test_browser_fallback_action_plan_uses_summarize_page() -> None:
    loop = AgentLoop()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="Search Google for VisionNavi and summarize it",
        normalized_text="Search Google for VisionNavi and summarize it",
        task_domain="web",
        intent="search_and_read",
        risk_level="low",
        requires_confirmation=False,
        target_app="browser",
        notes=["test"],
    )

    steps = loop._fallback_action_plan(command)  # noqa: SLF001

    assert steps[-1].action == "read_page_summary"
    assert all(step.action != "click_search_result" for step in steps)


def test_browser_fallback_action_plan_opens_linked_page_for_explicit_detail_request() -> None:
    loop = AgentLoop()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="Search Google for VisionNavi and open the original page to read the full article",
        normalized_text="Search Google for VisionNavi and open the original page to read the full article",
        task_domain="web",
        intent="search_and_read",
        risk_level="low",
        requires_confirmation=False,
        target_app="browser",
        notes=["test"],
    )

    steps = loop._fallback_action_plan(command)  # noqa: SLF001

    assert [step.action for step in steps][-3:] == [
        "click_search_result",
        "verify_page_loaded",
        "summarize_page",
    ]


def test_map_route_fallback_action_plan_uses_naver_map_directions() -> None:
    loop = AgentLoop()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="\ub124\uc774\ubc84 \uc9c0\ub3c4\uc5d0\uc11c \uc11c\uc6b8\uc5ed\uc5d0\uc11c \uc1a1\ub0b4\uc5ed\uac00\ub294 \uacbd\ub85c \ucc3e\uc544\uc918",
        normalized_text="\ub124\uc774\ubc84 \uc9c0\ub3c4\uc5d0\uc11c \uc11c\uc6b8\uc5ed\uc5d0\uc11c \uc1a1\ub0b4\uc5ed\uac00\ub294 \uacbd\ub85c \ucc3e\uc544\uc918",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="naver_map",
        notes=["test"],
    )

    steps = loop._fallback_action_plan(command)  # noqa: SLF001

    assert steps[0].action == "open_browser_url"
    assert steps[0].target == "https://map.naver.com/p/directions/-/-/-/transit?c=15.00,0,0,0,dh"
    assert any(step.action == "fill_input" and step.text == "\uc11c\uc6b8\uc5ed" for step in steps)
    assert any(step.action == "fill_input" and step.text == "\uc1a1\ub0b4\uc5ed" for step in steps)
    assert any(step.action == "click_element" and step.target == "button.btn_direction.search" for step in steps)


def test_map_route_planner_observation_keeps_subway_as_route_kind_not_destination() -> None:
    loop = AgentLoop()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="\ub124\uc774\ubc84 \uc9c0\ub3c4\uc5d0\uc11c \uc11c\uc6b8\uc5ed\uc5d0\uc11c \uc1a1\ub0b4\uc5ed\uac00\ub294 \uc9c0\ud558\ucca0\uacbd\ub85c \ucc3e\uc544\uc918",
        normalized_text="\ub124\uc774\ubc84 \uc9c0\ub3c4\uc5d0\uc11c \uc11c\uc6b8\uc5ed\uc5d0\uc11c \uc1a1\ub0b4\uc5ed\uac00\ub294 \uc9c0\ud558\ucca0\uacbd\ub85c \ucc3e\uc544\uc918",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="naver_map",
        notes=["test"],
    )

    planned_steps, notes, trace = loop._plan_actions(  # noqa: SLF001
        command,
        loop.browser_executor.observe(command),  # noqa: SLF001
    )

    assert notes == ["structured_map_route"]
    assert trace["path"] == "structured_map_route"
    assert trace["route_request"]["provider"] == "naver_map"
    assert trace["observation"]["origin"] == "\uc11c\uc6b8\uc5ed"
    assert trace["observation"]["destination"] == "\uc1a1\ub0b4\uc5ed"
    assert trace["observation"]["mode"] == "transit"
    assert trace["observation"]["route_kind"] == "subway"
    assert any(step.action == "fill_input" and step.text == "\uc1a1\ub0b4\uc5ed" for step in planned_steps)
    assert any(
        step.action == "click_element" and step.target == "button.btn_direction.search"
        for step in planned_steps
    )
    assert any(
        step.action == "click_element" and step.metadata.get("route_kind_filter") == "subway"
        for step in planned_steps
    )


def test_execute_command_uses_iterative_browser_loop_for_map_route(monkeypatch) -> None:
    monkeypatch.setenv("ITERATIVE_BROWSER_LOOP_ENABLED", "true")
    loop = AgentLoop()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="카카오맵에서 서울역에서 송내역 가는 경로 찾아줘",
        normalized_text="카카오맵에서 서울역에서 송내역 가는 경로 찾아줘",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="kakao_map",
        notes=["test"],
    )

    def fake_iterative(command_arg, model_client_arg, *, max_steps=8):  # noqa: ANN001
        return {
            "status": "success",
            "executor": "browser",
            "strategy": "iterative-next-action",
            "intent": command_arg.intent,
            "max_steps": max_steps,
        }

    loop.browser_executor.execute_iterative_browser_task = fake_iterative  # type: ignore[method-assign]

    result = loop._execute_command(command)  # noqa: SLF001

    assert result["status"] == "success"
    assert result["strategy"] == "iterative-next-action"
    assert result["intent"] == "find_map_route"


def test_execute_command_uses_external_browser_agent_backend(monkeypatch) -> None:
    loop = AgentLoop()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="Search Naver for VisionNavi and summarize the top result.",
        normalized_text="Search Naver for VisionNavi and summarize the top result.",
        task_domain="web",
        intent="search_and_read",
        risk_level="low",
        requires_confirmation=False,
        target_app="browser",
        notes=["test"],
    )

    loop.browser_executor.observe = lambda command_arg: {"page_title": "Naver Search"}  # type: ignore[method-assign]
    loop.external_browser_agent.execute = lambda request: type("Resp", (), {  # type: ignore[method-assign]
        "status": "success",
        "execution_backend": "external_browser_agent",
        "result": {
            "status": "success",
            "executor": "browser",
            "strategy": "external-agent-poc",
            "duration_ms": 1234.0,
            "step_count": 2,
        },
        "raw_agent_trace": {"adapter": "external_browser_agent", "opaque": object()},
        "normalized_agent_trace": [{"phase": "observe", "detail": "ok"}],
        "blocked_reason": None,
    })()

    result = loop._execute_command(command, requested_backend="external_browser_agent")  # noqa: SLF001

    assert result["status"] == "success"
    assert result["execution_backend"] == "external_browser_agent"
    assert result["raw_agent_trace"]["adapter"] == "external_browser_agent"
    assert result["normalized_agent_trace"][0]["phase"] == "observe"
    assert result["execution_summary"]["backend"] == "external_browser_agent"
    assert result["execution_summary"]["duration_ms"] == 1234.0
    assert result["execution_summary"]["step_count"] == 2
    assert isinstance(result["raw_agent_trace"]["opaque"], str)


def test_execute_command_falls_back_from_external_browser_agent_to_internal(monkeypatch) -> None:
    loop = AgentLoop()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="Search Naver for VisionNavi and summarize the top result.",
        normalized_text="Search Naver for VisionNavi and summarize the top result.",
        task_domain="web",
        intent="search_and_read",
        risk_level="low",
        requires_confirmation=False,
        target_app="browser",
        notes=["test"],
    )

    loop.browser_executor.observe = lambda command_arg: {"page_title": "Naver Search"}  # type: ignore[method-assign]
    loop.external_browser_agent.execute = lambda request: type("Resp", (), {  # type: ignore[method-assign]
        "status": "failed",
        "execution_backend": "external_browser_agent",
        "result": {"status": "failed", "reason": "external_browser_agent_execution_failed"},
        "raw_agent_trace": {"adapter": "external_browser_agent"},
        "normalized_agent_trace": [{"phase": "decide", "detail": "failed"}],
        "blocked_reason": "external_browser_agent_execution_failed",
    })()
    loop.browser_executor.execute = lambda command_arg: {  # type: ignore[method-assign]
        "status": "success",
        "executor": "browser",
        "strategy": "playwright-first",
    }

    result = loop._execute_command(command, requested_backend="external_browser_agent")  # noqa: SLF001

    assert result["status"] == "success"
    assert result["execution_backend"] == "external_browser_agent"
    assert result["fallback_backend"] == "internal_browser"
    assert result["external_backend_result"]["status"] == "failed"
    assert result["execution_summary"]["failure_reason"] == "external_browser_agent_execution_failed"


def test_execute_command_downgrades_unsupported_external_browser_intent_to_internal_with_reason() -> None:
    loop = AgentLoop()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="Find a route from Seoul Station to Songnae Station on Naver Map",
        normalized_text="Find a route from Seoul Station to Songnae Station on Naver Map",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="naver_map",
        notes=["test"],
    )

    loop.browser_executor.execute = lambda command_arg: {  # type: ignore[method-assign]
        "status": "success",
        "executor": "browser",
        "strategy": "playwright-first",
    }

    result = loop._execute_command(command, requested_backend="external_browser_agent")  # noqa: SLF001

    assert result["status"] == "success"
    assert result["execution_backend"] == "internal_browser"
    assert result["requested_backend"] == "external_browser_agent"
    assert result["backend_resolution_reason"] == "unsupported_external_intent:find_map_route"
    assert result["unsupported_requested_backend"] == "external_browser_agent"
    assert result["execution_summary"]["backend"] == "internal_browser"
    assert result["execution_summary"]["requested_backend"] == "external_browser_agent"
    assert result["execution_summary"]["routing_reason"] == "unsupported_external_intent:find_map_route"


def test_browser_normalized_action_plan_accepts_summarize_page_as_summary() -> None:
    loop = AgentLoop()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="Search Google for VisionNavi and summarize it",
        normalized_text="Search Google for VisionNavi and summarize it",
        task_domain="web",
        intent="search_and_read",
        risk_level="low",
        requires_confirmation=False,
        target_app="browser",
        notes=["test"],
    )
    planned = [
        ActionStep(action="search_web", target="google", text="visionnavi"),
        ActionStep(action="extract_top_result", target="google"),
        ActionStep(action="summarize_page", target="linked_page"),
    ]

    normalized, _ = loop._normalize_action_plan(command, planned)  # noqa: SLF001
    summary_steps = [step for step in normalized if step.action in {"summarize_page", "read_linked_page", "read_page_summary"}]

    assert len(summary_steps) == 1
    assert summary_steps[0].action in {"summarize_page", "read_page_summary"}


def test_browser_normalized_action_plan_prefers_result_card_summary_for_summary_only_query() -> None:
    loop = AgentLoop()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="Search Google for VisionNavi and summarize briefly",
        normalized_text="Search Google for VisionNavi and summarize briefly",
        task_domain="web",
        intent="search_and_read",
        risk_level="low",
        requires_confirmation=False,
        target_app="browser",
        notes=["test"],
    )
    planned = [
        ActionStep(action="search_web", target="naver", text="visionnavi"),
        ActionStep(action="extract_top_result", target="naver"),
        ActionStep(action="click_search_result", target="naver"),
        ActionStep(action="verify_page_loaded", target="linked_page"),
        ActionStep(action="summarize_page", target="linked_page"),
    ]

    normalized, _ = loop._normalize_action_plan(command, planned)  # noqa: SLF001
    actions = [step.action for step in normalized]

    assert "click_search_result" not in actions
    assert "read_page_summary" in actions
    assert "summarize_page" not in actions


def test_browser_normalized_action_plan_prefers_direct_url_navigation() -> None:
    loop = AgentLoop()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="Open https://example.com and summarize it",
        normalized_text="Open https://example.com and summarize it",
        task_domain="web",
        intent="search_and_read",
        risk_level="low",
        requires_confirmation=False,
        target_app="browser",
        notes=["test"],
    )
    planned = [
        ActionStep(action="search_web", target="google", text="example"),
        ActionStep(action="extract_top_result", target="google"),
        ActionStep(action="summarize_page", target="linked_page"),
    ]

    normalized, _ = loop._normalize_action_plan(command, planned)  # noqa: SLF001

    assert normalized[0].action == "open_browser_url"
    assert normalized[0].target == "https://example.com"
    assert all(step.action != "search_web" for step in normalized)


def test_browser_normalized_action_plan_uses_youtube_summary_for_youtube_target() -> None:
    loop = AgentLoop()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="YouTube에서 IVE 뮤비 찾아서 요약해줘",
        normalized_text="YouTube에서 IVE 뮤비 찾아서 요약해줘",
        task_domain="web",
        intent="search_and_read",
        risk_level="low",
        requires_confirmation=False,
        target_app="browser",
        notes=["test"],
    )
    planned = [
        ActionStep(action="search_web", target="google", text="ive music video"),
        ActionStep(action="extract_top_result", target="google"),
        ActionStep(action="summarize_page", target="linked_page"),
    ]

    normalized, _ = loop._normalize_action_plan(command, planned)  # noqa: SLF001
    search_steps = [step for step in normalized if step.action == "search_web"]
    summary_steps = [step for step in normalized if step.action in {"summarize_page", "read_page_summary"}]

    assert search_steps[0].target == "youtube"
    assert any(step.action == "read_page_summary" for step in summary_steps)
