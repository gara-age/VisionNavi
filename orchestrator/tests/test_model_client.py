from app.core.settings import Settings
from app.models.canonical_command import CanonicalCommand
from app.models.model_api import (
    ActionPlanRequest,
    CanonicalCommandPredictionRequest,
    NextActionRequest,
    PopupSummaryRequest,
    RuntimeCandidate,
    VisionObservationRequest,
)
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
    assert "find_map_route" in prompt


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
    assert "Naver Map route tasks" in prompt
    assert "click_element" in prompt
    assert "fill_input" in prompt
    assert "read_section" in prompt
    assert "naver, google, or youtube" in prompt
    assert "move_file" in prompt
    assert "verify_file_contains_text" in prompt
    assert "ollama_action_planner" in prompt


def test_ollama_next_action_prompt_mentions_single_step_runtime_decision() -> None:
    client = RemoteModelClient(
        Settings(
            model_api_enabled=True,
            model_provider="ollama",
            ollama_model="qwen2.5:14b",
        )
    )
    prompt = client._build_next_action_prompt(  # noqa: SLF001
        NextActionRequest(
            command=CanonicalCommand(
                input_mode="text",
                raw_text="Search Naver for VisionNavi and summarize the top result.",
                normalized_text="Search Naver for VisionNavi and summarize the top result.",
                task_domain="web",
                intent="search_and_read",
                risk_level="low",
                requires_confirmation=False,
                target_app="browser",
            ),
            observation={"page_title": "Naver Search", "query": "VisionNavi"},
            candidate_targets=[
                RuntimeCandidate(
                    candidate_id="cand_search_box",
                    kind="input",
                    label="search box",
                    selector_hint="input[name=query]",
                )
            ],
            history=[{"action": "search_web", "status": "success"}],
        )
    )

    assert "Choose only the single best next action" in prompt
    assert "candidate_targets" in prompt
    assert "done" in prompt
    assert "needs_recovery" in prompt
    assert 'For "open_browser_url", put the URL in "target"' in prompt
    assert 'For "search_web", put the engine or site in "target"' in prompt
    assert "If the command explicitly names Naver Map or Kakao Map" in prompt
    assert 'Do not put words like "버스 경로", "지하철 경로", or "가는 경로" into the destination input' in prompt
    assert "progress_state" in prompt
    assert "suggested_next_step" in prompt
    assert "ollama_next_action" in prompt


def test_ollama_vision_prompt_mentions_route_state_and_visibility() -> None:
    client = RemoteModelClient(
        Settings(
            model_api_enabled=True,
            model_provider="ollama",
            ollama_model="qwen2.5:14b",
            ollama_vision_enabled=True,
            ollama_vision_model="qwen2.5vl:3b",
        )
    )
    prompt = client._build_vision_observation_prompt(  # noqa: SLF001
        VisionObservationRequest(
            command=CanonicalCommand(
                input_mode="text",
                raw_text="네이버지도에서 서울역에서 송내역 가는 버스 경로 찾아줘",
                normalized_text="네이버지도에서 서울역에서 송내역 가는 버스 경로 찾아줘",
                task_domain="web",
                intent="find_map_route",
                risk_level="low",
                requires_confirmation=False,
                target_app="naver_map",
            ),
            observation={"page_title": "길찾기 - 네이버 지도", "route_kind": "bus"},
        )
    )

    assert "visual runtime observer" in prompt
    assert "route entry, suggestion selection, route results visible, blocked, or ambiguous state" in prompt
    assert "If the screenshot already shows route results" in prompt
    assert "ollama_vision_observer" in prompt


def test_settings_reads_planner_overrides(monkeypatch) -> None:
    monkeypatch.setenv("OLLAMA_MODEL", "qwen2.5:14b")
    monkeypatch.setenv("OLLAMA_PLANNER_MODEL", "qwen2.5:7b")
    monkeypatch.setenv("OLLAMA_VISION_MODEL", "qwen2.5vl:3b")
    monkeypatch.setenv("OLLAMA_VISION_ENABLED", "true")
    monkeypatch.setenv("OLLAMA_VISION_NUM_PREDICT", "256")
    monkeypatch.setenv("OLLAMA_PLANNER_TEMPERATURE", "0.0")
    monkeypatch.setenv("OLLAMA_PLANNER_NUM_PREDICT", "512")
    monkeypatch.setenv("PLAYWRIGHT_USE_CDP", "true")
    monkeypatch.setenv("PLAYWRIGHT_CDP_URL", "http://127.0.0.1:9333")
    monkeypatch.setenv("ITERATIVE_BROWSER_LOOP_ENABLED", "true")
    monkeypatch.setenv("ITERATIVE_BROWSER_MAX_STEPS", "6")
    monkeypatch.setenv("DEFAULT_BROWSER_EXECUTION_BACKEND", "external_browser_agent")
    monkeypatch.setenv("DEFAULT_DESKTOP_EXECUTION_BACKEND", "external_desktop_agent")
    monkeypatch.setenv("EXTERNAL_AGENT_FALLBACK_TO_INTERNAL", "false")
    monkeypatch.setenv("EXTERNAL_BROWSER_AGENT_MODEL", "qwen2.5:14b")
    monkeypatch.setenv("EXTERNAL_BROWSER_AGENT_USE_VISION", "false")
    monkeypatch.setenv("EXTERNAL_BROWSER_AGENT_MAX_STEPS", "9")
    monkeypatch.setenv("EXTERNAL_BROWSER_AGENT_STEP_TIMEOUT_S", "95")
    monkeypatch.setenv("EXTERNAL_DESKTOP_AGENT_BASE_URL", "http://127.0.0.1:11434/v1")
    monkeypatch.setenv("EXTERNAL_DESKTOP_AGENT_API_KEY", "ollama")
    monkeypatch.setenv("EXTERNAL_DESKTOP_AGENT_MODEL", "qwen2.5vl:3b")
    monkeypatch.setenv("EXTERNAL_DESKTOP_AGENT_MAX_LOOPS", "10")
    monkeypatch.setenv("EXTERNAL_DESKTOP_AGENT_TIMEOUT_S", "135")
    monkeypatch.setenv("EXTERNAL_DESKTOP_AGENT_LOOP_INTERVAL_MS", "300")
    monkeypatch.setenv("EXTERNAL_DESKTOP_AGENT_BRIDGE_DIR", "runtime/external_agents/ui_tars_bridge")
    monkeypatch.setenv("EXTERNAL_DESKTOP_AGENT_BRIDGE_SCRIPT", "run_ui_tars.js")
    monkeypatch.setenv("EXTERNAL_DESKTOP_AGENT_PREOPEN_NOTEPAD", "true")

    settings = Settings.from_env()

    assert settings.ollama_model == "qwen2.5:14b"
    assert settings.ollama_planner_model == "qwen2.5:7b"
    assert settings.ollama_vision_model == "qwen2.5vl:3b"
    assert settings.ollama_vision_enabled is True
    assert settings.ollama_vision_num_predict == 256
    assert settings.ollama_planner_temperature == 0.0
    assert settings.ollama_planner_num_predict == 512
    assert settings.browser_use_cdp is True
    assert settings.browser_cdp_url == "http://127.0.0.1:9333"
    assert settings.iterative_browser_loop_enabled is True
    assert settings.iterative_browser_max_steps == 6
    assert settings.default_browser_execution_backend == "external_browser_agent"
    assert settings.default_desktop_execution_backend == "external_desktop_agent"
    assert settings.external_agent_fallback_to_internal is False
    assert settings.external_browser_agent_model == "qwen2.5:14b"
    assert settings.external_browser_agent_use_vision is False
    assert settings.external_browser_agent_max_steps == 9
    assert settings.external_browser_agent_step_timeout_s == 95
    assert settings.external_desktop_agent_base_url == "http://127.0.0.1:11434/v1"
    assert settings.external_desktop_agent_api_key == "ollama"
    assert settings.external_desktop_agent_model == "qwen2.5vl:3b"
    assert settings.external_desktop_agent_max_loops == 10
    assert settings.external_desktop_agent_timeout_s == 135
    assert settings.external_desktop_agent_loop_interval_ms == 300
    assert settings.external_desktop_agent_bridge_dir == "runtime/external_agents/ui_tars_bridge"
    assert settings.external_desktop_agent_bridge_script == "run_ui_tars.js"
    assert settings.external_desktop_agent_preopen_notepad is True


def test_settings_defaults_to_external_first_policy(monkeypatch) -> None:
    monkeypatch.delenv("DEFAULT_BROWSER_EXECUTION_BACKEND", raising=False)
    monkeypatch.delenv("DEFAULT_DESKTOP_EXECUTION_BACKEND", raising=False)

    settings = Settings.from_env()

    assert settings.default_browser_execution_backend == "external_browser_agent"
    assert settings.default_desktop_execution_backend == "external_desktop_agent"


def test_load_json_response_accepts_fenced_json() -> None:
    client = RemoteModelClient()

    parsed = client._load_json_response(  # noqa: SLF001
        """```json
{"steps": [], "notes": ["ok"]}
```"""
    )

    assert parsed["steps"] == []
    assert parsed["notes"] == ["ok"]


def test_load_json_response_repairs_trailing_commas() -> None:
    client = RemoteModelClient()

    parsed = client._load_json_response(  # noqa: SLF001
        '{"steps": [{"action": "search_web", "target": "naver", "text": "VisionNavi",}], "notes": ["ok",],}'
    )

    assert parsed["notes"] == ["ok"]
    assert parsed["steps"][0]["action"] == "search_web"


def test_popup_summary_prompt_requests_structured_popup_copy() -> None:
    client = RemoteModelClient(
        Settings(
            model_api_enabled=True,
            model_provider="ollama",
            ollama_model="qwen2.5:14b",
        )
    )

    prompt = client._build_popup_summary_prompt(  # noqa: SLF001
        PopupSummaryRequest(
            command=CanonicalCommand(
                input_mode="text",
                raw_text="Search Naver for Incheon youth monthly rent support and read the conditions.",
                normalized_text="Search Naver for Incheon youth monthly rent support and read the conditions.",
                task_domain="web",
                intent="search_and_read",
                risk_level="low",
                requires_confirmation=False,
                target_app="browser",
            ),
            language="ko",
            result={"status": "success"},
            popup_context={
                "intent": "search_and_read",
                "looks_like_welfare": True,
                "result_title": "Incheon Youth Monthly Rent Support",
                "summary": "Eligibility and application details were extracted.",
            },
        )
    )

    assert '"title"' in prompt
    assert '"message"' in prompt
    assert '"notes"' in prompt
    assert "Do not invent facts" in prompt
    assert "Do not output Chinese" in prompt
    assert "popup_context" in prompt
