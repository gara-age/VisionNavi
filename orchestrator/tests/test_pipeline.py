from fastapi.testclient import TestClient

from app.api.routes import pipeline
from app.main import app
from app.models.model_api import CanonicalCommandPredictionResponse


client = TestClient(app)


class FakeModelClient:
    def __init__(self, response: CanonicalCommandPredictionResponse | None = None, should_fail: bool = False) -> None:
        self.response = response
        self.should_fail = should_fail

    def predict_canonical_command(self, request):  # noqa: ANN001
        if self.should_fail:
            raise RuntimeError("model unavailable")
        return self.response


def test_health_check() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


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
