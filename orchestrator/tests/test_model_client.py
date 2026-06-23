from app.core.settings import Settings
from app.models.canonical_command import CanonicalCommand
from app.models.model_api import ActionPlanRequest, CanonicalCommandPredictionRequest
from app.services.model_client import RemoteModelClient


def test_ollama_prompt_mentions_expected_intents() -> None:
    client = RemoteModelClient(
        Settings(
            model_api_enabled=True,
            model_provider="ollama",
            ollama_model="qwen2.5:14b",
        )
    )
    prompt = client._build_ollama_prompt(  # noqa: SLF001
        CanonicalCommandPredictionRequest(
            input_mode="text",
            raw_text="Change Windows to dark mode",
            normalized_text="Change Windows to dark mode",
        )
    )

    assert "change_system_setting" in prompt
    assert "open_notepad_and_type" in prompt
    assert "search_and_read" in prompt


def test_ollama_action_plan_prompt_mentions_step_schema() -> None:
    client = RemoteModelClient(
        Settings(
            model_api_enabled=True,
            model_provider="ollama",
            ollama_model="qwen2.5:14b",
        )
    )
    prompt = client._build_action_plan_prompt(  # noqa: SLF001
        ActionPlanRequest(
            command=CanonicalCommand(
                input_mode="text",
                raw_text="Open Notepad and type my presentation notes for today.",
                normalized_text="Open Notepad and type my presentation notes for today.",
                task_domain="desktop",
                intent="open_notepad_and_type",
                risk_level="low",
                requires_confirmation=False,
                target_app="notepad",
            ),
            observation={"notepad_windows": []},
        )
    )

    assert "open_app" in prompt
    assert "focus_window" in prompt
    assert "search_web" in prompt
    assert "extract_top_result" in prompt
    assert "click_search_result" in prompt
    assert "move_file" in prompt
    assert "verify_file_contains_text" in prompt
    assert "ollama_action_planner" in prompt


def test_settings_reads_planner_overrides(monkeypatch) -> None:
    monkeypatch.setenv("OLLAMA_MODEL", "qwen2.5:14b")
    monkeypatch.setenv("OLLAMA_PLANNER_MODEL", "qwen2.5:7b")
    monkeypatch.setenv("OLLAMA_PLANNER_TEMPERATURE", "0.0")
    monkeypatch.setenv("OLLAMA_PLANNER_NUM_PREDICT", "512")

    settings = Settings.from_env()

    assert settings.ollama_model == "qwen2.5:14b"
    assert settings.ollama_planner_model == "qwen2.5:7b"
    assert settings.ollama_planner_temperature == 0.0
    assert settings.ollama_planner_num_predict == 512
