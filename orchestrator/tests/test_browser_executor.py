import asyncio
import sys
import types

from app.automation.browser.executor import BrowserExecutor
from app.core.settings import Settings
from app.models.action_step import ActionStep
from app.models.canonical_command import CanonicalCommand
from app.models.map_route import MapRouteRequest
from app.models.model_api import NextActionResponse


def _build_browser_command() -> CanonicalCommand:
    return CanonicalCommand(
        input_mode="text",
        raw_text="Search Naver for Incheon youth monthly rent support and read the conditions.",
        normalized_text="Search Naver for Incheon youth monthly rent support and read the conditions.",
        task_domain="web",
        intent="search_and_read",
        risk_level="low",
        requires_confirmation=False,
        target_app="browser",
    )


def test_extract_search_query_from_english_prompt() -> None:
    executor = BrowserExecutor()

    result = executor._extract_search_query(_build_browser_command().normalized_text)  # noqa: SLF001

    assert result == "incheon youth monthly rent support"


def test_extract_search_request_from_korean_google_command() -> None:
    executor = BrowserExecutor()

    result = executor._extract_search_request("구글에서 유튜브 검색해줘")  # noqa: SLF001

    assert result == {"target": "google", "query": "유튜브"}


def test_extract_search_request_from_korean_youtube_command() -> None:
    executor = BrowserExecutor()

    result = executor._extract_search_request("유튜브에서 아이브 뮤직비디오 찾아줘")  # noqa: SLF001

    assert result == {"target": "youtube", "query": "아이브 뮤직비디오"}


def test_observe_browser_command_returns_query() -> None:
    executor = BrowserExecutor()

    observation = executor.observe(_build_browser_command())

    assert observation["task_domain"] == "web"
    assert observation["query"] == "incheon youth monthly rent support"
    assert observation["preferred_search_target"] == "naver"


def test_extract_map_route_request_from_korean_naver_map_command() -> None:
    executor = BrowserExecutor()

    result = executor._extract_map_route_request(  # noqa: SLF001
        "\ub124\uc774\ubc84 \uc9c0\ub3c4\uc5d0\uc11c \uc11c\uc6b8\uc5ed\uc5d0\uc11c \uc1a1\ub0b4\uc5ed\uac00\ub294 \uacbd\ub85c \ucc3e\uc544\uc918"
    )

    assert result == {
        "site": "naver_map",
        "origin": "\uc11c\uc6b8\uc5ed",
        "destination": "\uc1a1\ub0b4\uc5ed",
        "mode": "transit",
        "route_kind": "general",
    }


def test_extract_map_route_request_separates_subway_route_kind_from_destination() -> None:
    executor = BrowserExecutor()

    result = executor._extract_map_route_request(  # noqa: SLF001
        "\ub124\uc774\ubc84 \uc9c0\ub3c4\uc5d0\uc11c \uc11c\uc6b8\uc5ed\uc5d0\uc11c \uc1a1\ub0b4\uc5ed\uac00\ub294 \uc9c0\ud558\ucca0\uacbd\ub85c \ucc3e\uc544\uc918"
    )

    assert result == {
        "site": "naver_map",
        "origin": "\uc11c\uc6b8\uc5ed",
        "destination": "\uc1a1\ub0b4\uc5ed",
        "mode": "transit",
        "route_kind": "subway",
    }


def test_extract_map_route_request_preserves_kakao_map_site_and_route_slots() -> None:
    executor = BrowserExecutor()

    result = executor._extract_map_route_request(  # noqa: SLF001
        "\uce74\uce74\uc624\ub9f5\uc5d0\uc11c \uc11c\uc6b8\uc5ed\uc5d0\uc11c \uc1a1\ub0b4\uc5ed \uac00\ub294 \uacbd\ub85c \ucc3e\uc544\uc918"
    )

    assert result == {
        "site": "kakao_map",
        "origin": "\uc11c\uc6b8\uc5ed",
        "destination": "\uc1a1\ub0b4\uc5ed",
        "mode": "transit",
        "route_kind": "general",
    }


def test_extract_map_route_request_strips_leading_naver_site_marker() -> None:
    executor = BrowserExecutor()

    result = executor._extract_map_route_request(  # noqa: SLF001
        "\ub124\uc774\ubc84\uc5d0\uc11c \uc11c\uc6b8\uc5ed\uc5d0\uc11c \uc1a1\ub0b4\uc5ed \uac00\ub294 \uacbd\ub85c \ucc3e\uc544\uc918"
    )

    assert result == {
        "site": "naver_map",
        "origin": "\uc11c\uc6b8\uc5ed",
        "destination": "\uc1a1\ub0b4\uc5ed",
        "mode": "transit",
        "route_kind": "general",
    }


def test_build_kakao_map_route_steps_uses_subway_target_and_sequential_typing() -> None:
    executor = BrowserExecutor()

    steps = executor.build_map_route_steps(
        MapRouteRequest(
            provider="kakao_map",
            origin="\uc11c\uc6b8\uc5ed",
            destination="\uc1a1\ub0b4\uc5ed",
            mode="transit",
            route_kind="general",
        )
    )

    assert steps[0].action == "open_browser_url"
    assert steps[0].target == "https://map.kakao.com/?target=car"
    assert any(
        step.action == "fill_input"
        and step.target == 'input[name="routePoint-0"]'
        and step.metadata.get("typing_mode") == "sequential"
        for step in steps
    )
    assert any(
        step.action == "click_element" and step.target == "#transit"
        for step in steps
    )
    assert any(
        step.action == "verify_page_loaded" and step.target == "kakao_map_transit_directions"
        for step in steps
    )


def test_build_kakao_map_subway_route_places_route_kind_filter_before_verify() -> None:
    executor = BrowserExecutor()

    steps = executor.build_map_route_steps(
        MapRouteRequest(
            provider="kakao_map",
            origin="\uc11c\uc6b8\uc5ed",
            destination="\uc1a1\ub0b4\uc5ed",
            mode="transit",
            route_kind="subway",
        )
    )

    filter_index = next(i for i, step in enumerate(steps) if step.target == "route_kind_filter")
    verify_index = next(i for i, step in enumerate(steps) if step.target == "kakao_map_transit_directions")
    assert filter_index < verify_index


def test_execute_browser_action_plan_reports_success(monkeypatch) -> None:
    executor = BrowserExecutor()
    command = _build_browser_command()
    steps = [
        ActionStep(action="search_web", target="naver", text="incheon youth monthly rent support"),
        ActionStep(action="verify_page_loaded", target="naver"),
        ActionStep(action="extract_top_result", target="naver"),
        ActionStep(action="click_search_result", target="naver"),
        ActionStep(action="read_linked_page", target="linked_page"),
    ]

    def fake_execute_action_step(step: ActionStep, context: dict[str, object]) -> dict[str, object]:
        if step.action == "search_web":
            context["query"] = step.text
            context["page_url"] = "https://search.naver.com/search.naver?query=incheon"
            context["page_title"] = "Naver Search"
            return {"status": "success"}
        if step.action == "extract_top_result":
            context["top_result"] = {
                "title": "Incheon Youth Rent Support",
                "snippet": "Eligibility and conditions",
                "url": "https://example.com/rent-support",
            }
            return {"status": "success"}
        if step.action == "click_search_result":
            context["linked_page_url"] = "https://example.com/rent-support"
            context["page_url"] = "https://example.com/rent-support"
            context["page_title"] = "Rent Support Detail"
            return {"status": "success"}
        if step.action == "read_linked_page":
            context["page_summary"] = "Eligibility and application details"
            return {"status": "success"}
        return {"status": "success"}

    async def fake_execute_action_step_async(
        step: ActionStep,
        context: dict[str, object],
    ) -> dict[str, object]:
        return fake_execute_action_step(step, context)

    fake_async_api = types.ModuleType("playwright.async_api")
    fake_async_api.Error = RuntimeError

    class _FakeAsyncPlaywrightContext:
        async def __aenter__(self):
            return object()

        async def __aexit__(self, exc_type, exc, tb):
            return None

    fake_async_api.async_playwright = lambda: _FakeAsyncPlaywrightContext()
    monkeypatch.setitem(sys.modules, "playwright.async_api", fake_async_api)
    monkeypatch.setattr(executor, "_open_page", lambda playwright: _co_return(_FakePage()))
    monkeypatch.setattr(executor, "execute_action_step_async", fake_execute_action_step_async)

    result = executor.execute_action_plan(command, steps)

    assert result["status"] == "success"
    assert result["strategy"] == "llm-action-plan"
    assert result["top_result_title"] == "Incheon Youth Rent Support"
    assert result["linked_page_url"] == "https://example.com/rent-support"
    assert result["page_summary"] == "Eligibility and application details"
    assert len(result["executed_steps"]) == 5
    assert len(result["runtime_trace"]) == 5
    assert result["runtime_trace"][0]["selected_target"] == "naver"
    assert "runtime_observation" in result
    assert result["runtime_observation"]["candidate_targets"] == []


def test_capture_runtime_observation_includes_candidate_targets() -> None:
    executor = BrowserExecutor()
    page = _FakePage({"main": _FakeLocator("VisionNavi summary text for the page body.")})
    page.url = "https://search.naver.com/search.naver?query=visionnavi"
    page.title_text = "Naver Search"
    page.evaluate_result = [
        {
            "candidate_id": "cand_1",
            "kind": "input",
            "label": "search box",
            "role": "searchbox",
            "selector_hint": "input#query",
            "text_preview": "",
            "metadata": {"tag": "input", "type": "text"},
        },
        {
            "candidate_id": "cand_2",
            "kind": "clickable",
            "label": "search",
            "role": "button",
            "selector_hint": "button.search",
            "text_preview": "Search",
            "metadata": {"tag": "button", "type": None},
        },
    ]

    result = asyncio.run(
        executor._capture_runtime_observation_async(  # noqa: SLF001
            page,
            CanonicalCommand(
                input_mode="text",
                raw_text="Search Naver for VisionNavi",
                normalized_text="Search Naver for VisionNavi",
                task_domain="web",
                intent="search_and_read",
                risk_level="low",
                requires_confirmation=False,
                target_app="browser",
            ),
        )
    )

    assert result["page_title"] == "Naver Search"
    assert result["page_url"] == "https://search.naver.com/search.naver?query=visionnavi"
    assert result["candidate_targets"][0]["candidate_id"] == "cand_1"
    assert result["candidate_targets"][1]["selector_hint"] == "button.search"


def test_resolve_selector_uses_candidate_id_from_runtime_observation() -> None:
    executor = BrowserExecutor()

    selector = executor._resolve_selector(  # noqa: SLF001
        ActionStep(action="click_element", target="cand_2"),
        context={
            "runtime_observation": {
                "candidate_targets": [
                    {"candidate_id": "cand_1", "selector_hint": "input#query"},
                    {"candidate_id": "cand_2", "selector_hint": "button.search"},
                ]
            }
        },
    )

    assert selector == "button.search"


def test_resolve_next_step_decision_prefers_llm_step() -> None:
    executor = BrowserExecutor()
    decision = NextActionResponse(
        step=ActionStep(action="search_web", target="naver", text="visionnavi"),
        choice_reason="best next step",
    )

    step, source, fallback_reason = executor._resolve_next_step_decision(  # noqa: SLF001
        decision=decision,
        fallback_steps=[ActionStep(action="search_web", target="google", text="fallback")],
        executed_count=0,
    )

    assert step is not None
    assert step.target == "naver"
    assert source == "llm_next_action"
    assert fallback_reason is None


def test_resolve_next_step_decision_uses_fallback_reason_when_llm_returns_no_step() -> None:
    executor = BrowserExecutor()
    decision = NextActionResponse(
        step=None,
        done=False,
        needs_recovery=False,
        choice_reason="uncertain",
    )

    step, source, fallback_reason = executor._resolve_next_step_decision(  # noqa: SLF001
        decision=decision,
        fallback_steps=[ActionStep(action="extract_top_result", target="naver")],
        executed_count=0,
    )

    assert step is not None
    assert step.action == "extract_top_result"
    assert source == "fallback"
    assert fallback_reason == "llm_returned_no_step"


def test_iterative_fallback_steps_uses_map_route_steps_for_route_command() -> None:
    executor = BrowserExecutor()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="네이버지도에서 서울역에서 송내역 가는 버스 경로 찾아줘",
        normalized_text="네이버지도에서 서울역에서 송내역 가는 버스 경로 찾아줘",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="naver_map",
    )

    steps = executor._iterative_fallback_steps(command)  # noqa: SLF001

    assert any(step.action == "open_browser_url" for step in steps)
    assert any(step.action == "fill_input" and step.text == "서울역" for step in steps)
    assert any(step.action == "fill_input" and step.text == "송내역" for step in steps)


def test_iterative_map_route_completion_requires_route_kind_filter_for_specific_route_kind() -> None:
    executor = BrowserExecutor()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="네이버지도에서 서울역에서 송내역 가는 버스 경로 찾아줘",
        normalized_text="네이버지도에서 서울역에서 송내역 가는 버스 경로 찾아줘",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="naver_map",
    )

    should_finish_after_verify = executor._should_complete_iterative_browser_task(  # noqa: SLF001
        command=command,
        chosen_step=ActionStep(action="verify_page_loaded", target="naver_map_directions"),
        step_result={"status": "success", "verification_result": "route_result_loaded"},
        context={"route_kind": "bus"},
    )
    should_finish_after_filter = executor._should_complete_iterative_browser_task(  # noqa: SLF001
        command=command,
        chosen_step=ActionStep(action="click_element", target="route_kind_filter", metadata={"route_kind_filter": "bus"}),
        step_result={"status": "success"},
        context={"route_kind": "bus"},
    )

    assert should_finish_after_verify is False
    assert should_finish_after_filter is True


def test_resolve_vision_analysis_trigger_skips_initial_route_observation() -> None:
    executor = BrowserExecutor(Settings(ollama_vision_enabled=True))
    command = CanonicalCommand(
        input_mode="text",
        raw_text="네이버지도에서 서울역에서 송내역 가는 버스 경로 찾아줘",
        normalized_text="네이버지도에서 서울역에서 송내역 가는 버스 경로 찾아줘",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="naver_map",
    )

    trigger_reason = executor._resolve_vision_analysis_trigger(  # noqa: SLF001
        command=command,
        observation={"progress_state": "initial", "page_url": "https://map.naver.com"},
        executed_steps=[],
        last_result=None,
        decision_trace=[],
    )

    assert trigger_reason is None


def test_resolve_vision_analysis_trigger_skips_blank_initial_state() -> None:
    executor = BrowserExecutor(Settings(ollama_vision_enabled=True))
    command = CanonicalCommand(
        input_mode="text",
        raw_text="route request",
        normalized_text="route request",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="naver_map",
    )

    trigger_reason = executor._resolve_vision_analysis_trigger(  # noqa: SLF001
        command=command,
        observation={"progress_state": "initial", "page_url": "about:blank"},
        executed_steps=[],
        last_result=None,
        decision_trace=[],
    )

    assert trigger_reason is None


def test_verify_map_route_with_retry_async_succeeds_on_second_attempt() -> None:
    executor = BrowserExecutor()

    class _RetryPage:
        def __init__(self) -> None:
            self.wait_calls: list[int] = []

        async def wait_for_timeout(self, timeout_ms: int) -> None:
            self.wait_calls.append(timeout_ms)

    page = _RetryPage()
    attempts = {"count": 0}

    async def verifier(_page, _context):  # noqa: ANN001
        attempts["count"] += 1
        return attempts["count"] >= 2

    result, verify_attempts = asyncio.run(
        executor._verify_map_route_with_retry_async(  # noqa: SLF001
            page,
            {},
            verifier=verifier,
        )
    )

    assert result is True
    assert verify_attempts == 2
    assert page.wait_calls == [1200]


def test_submit_form_selects_naver_map_first_suggestion_when_present() -> None:
    executor = BrowserExecutor()
    suggestion = _FakeLocator()
    page = _FakePage(
        {
            ".search_input_box_wrap.start input.input_search": _FakeLocator(),
            ".search_input_box_wrap.start .suggest_list_box li a": suggestion,
        }
    )
    context = {"page": page}

    result = executor.execute_action_step(
        ActionStep(
            action="submit_form",
            target=".search_input_box_wrap.start input.input_search",
            metadata={"selector": ".search_input_box_wrap.start input.input_search"},
        ),
        context=context,
    )

    assert result["status"] == "success"
    assert result["suggestion_selected"] is True
    assert suggestion.clicked is True


def test_recover_map_route_before_retry_clicks_search_button_for_naver_map() -> None:
    executor = BrowserExecutor()
    search_button = _FakeLocator()
    page = _FakePage(
        {
            "button.btn_direction.search": search_button,
        }
    )
    page.url = "https://map.naver.com/p/directions/-/-/-/transit?c=14.00,0,0,0,dh"

    asyncio.run(
        executor._recover_map_route_before_retry_async(  # noqa: SLF001
            page,
            {},
        )
    )

    assert search_button.clicked is True


def test_resolve_vision_analysis_trigger_waits_until_second_consecutive_no_step() -> None:
    executor = BrowserExecutor(Settings(ollama_vision_enabled=True))
    command = CanonicalCommand(
        input_mode="text",
        raw_text="네이버지도에서 서울역에서 송내역 가는 버스 경로 찾아줘",
        normalized_text="네이버지도에서 서울역에서 송내역 가는 버스 경로 찾아줘",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="naver_map",
    )

    trigger_reason = executor._resolve_vision_analysis_trigger(  # noqa: SLF001
        command=command,
        observation={"progress_state": "form_submitted", "consecutive_no_step_count": 1},
        executed_steps=[{"index": 1, "action": "open_browser_url", "status": "success"}],
        last_result={"status": "success"},
        decision_trace=[
            {
                "index": 1,
                "decision_source": "fallback",
                "fallback_reason": "llm_returned_no_step",
            }
        ],
    )

    assert trigger_reason is None


def test_resolve_vision_analysis_trigger_skips_after_route_results_ready() -> None:
    executor = BrowserExecutor(Settings(ollama_vision_enabled=True))
    command = CanonicalCommand(
        input_mode="text",
        raw_text="네이버지도에서 서울역에서 송내역 가는 버스 경로 찾아줘",
        normalized_text="네이버지도에서 서울역에서 송내역 가는 버스 경로 찾아줘",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="naver_map",
    )

    trigger_reason = executor._resolve_vision_analysis_trigger(  # noqa: SLF001
        command=command,
        observation={"progress_state": "route_results_ready"},
        executed_steps=[{"index": 1, "action": "verify_page_loaded", "status": "success"}],
        last_result={"status": "success", "verification_result": "route_result_loaded"},
        decision_trace=[],
    )

    assert trigger_reason is None


def test_resolve_vision_analysis_trigger_requests_retry_after_second_consecutive_no_step() -> None:
    executor = BrowserExecutor(Settings(ollama_vision_enabled=True))
    command = CanonicalCommand(
        input_mode="text",
        raw_text="route request",
        normalized_text="route request",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="naver_map",
    )

    trigger_reason = executor._resolve_vision_analysis_trigger(  # noqa: SLF001
        command=command,
        observation={"progress_state": "form_submitted", "consecutive_no_step_count": 2},
        executed_steps=[{"index": 1, "action": "open_browser_url", "status": "success"}],
        last_result={"status": "success"},
        decision_trace=[
            {
                "index": 1,
                "decision_source": "fallback",
                "fallback_reason": "llm_returned_no_step",
            }
        ],
    )

    assert trigger_reason == "llm_returned_no_step"


def test_count_consecutive_no_step_fallbacks_counts_trailing_sequence() -> None:
    executor = BrowserExecutor()

    count = executor._count_consecutive_no_step_fallbacks(  # noqa: SLF001
        [
            {"decision_source": "llm_next_action", "fallback_reason": None},
            {"decision_source": "fallback", "fallback_reason": "llm_returned_no_step"},
            {"decision_source": "fallback", "fallback_reason": "llm_returned_no_step"},
        ]
    )

    assert count == 2


def test_build_performance_summary_counts_fallback_reasons() -> None:
    executor = BrowserExecutor()

    summary = executor._build_performance_summary(  # noqa: SLF001
        [
            {
                "index": 1,
                "action": "open_browser_url",
                "decision_source": "llm_next_action",
                "fallback_reason": None,
                "timings_ms": {
                    "total_step_ms": 1000,
                    "observation_ms": 100,
                    "vision_ms": 0,
                    "llm_ms": 200,
                    "action_ms": 300,
                },
            },
            {
                "index": 2,
                "action": "fill_input",
                "decision_source": "fallback",
                "fallback_reason": "llm_returned_no_step",
                "timings_ms": {
                    "total_step_ms": 1500,
                    "observation_ms": 150,
                    "vision_ms": 0,
                    "llm_ms": 250,
                    "action_ms": 350,
                },
            },
            {
                "index": 3,
                "action": "click_element",
                "decision_source": "deterministic_streak",
                "fallback_reason": "deterministic_streak_active",
                "timings_ms": {
                    "total_step_ms": 2000,
                    "observation_ms": 200,
                    "vision_ms": 0,
                    "llm_ms": 0,
                    "action_ms": 400,
                },
            },
        ]
    )

    assert summary["step_count"] == 3
    assert summary["decision_source_counts"]["fallback"] == 1
    assert summary["decision_source_counts"]["deterministic_streak"] == 1
    assert summary["fallback_reason_counts"]["llm_returned_no_step"] == 1
    assert summary["fallback_reason_counts"]["deterministic_streak_active"] == 1
    assert summary["llm_no_step_count"] == 1


def test_resolve_deterministic_streak_reason_for_linear_route_sequence() -> None:
    executor = BrowserExecutor()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="Find the bus route from Seoul Station to Songnae Station",
        normalized_text="Find the bus route from Seoul Station to Songnae Station",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="naver_map",
    )
    fallback_steps = [
        ActionStep(action="open_browser_url", target="https://map.naver.com"),
        ActionStep(action="wait_for_element", target=".origin"),
        ActionStep(action="fill_input", target=".origin", text="Seoul Station"),
        ActionStep(action="submit_form", target=".origin"),
        ActionStep(action="fill_input", target=".destination", text="Songnae Station"),
        ActionStep(action="submit_form", target=".destination"),
        ActionStep(action="click_element", target="button.search"),
        ActionStep(action="verify_page_loaded", target="naver_map_directions"),
        ActionStep(action="click_element", target="route_kind_filter", metadata={"route_kind_filter": "bus"}),
    ]

    reason = executor._resolve_deterministic_streak_reason(  # noqa: SLF001
        command=command,
        fallback_steps=fallback_steps,
        executed_count=2,
        last_result={"status": "success"},
        decision_trace=[
            {
                "index": 1,
                "decision_source": "fallback",
                "fallback_reason": "llm_returned_no_step",
            }
        ],
    )

    assert reason == "linear_route_fallback_sequence"


def test_resolve_deterministic_streak_reason_keeps_running_after_streak_started() -> None:
    executor = BrowserExecutor()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="Find the bus route from Seoul Station to Songnae Station",
        normalized_text="Find the bus route from Seoul Station to Songnae Station",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="naver_map",
    )
    fallback_steps = [
        ActionStep(action="open_browser_url", target="https://map.naver.com"),
        ActionStep(action="wait_for_element", target=".origin"),
        ActionStep(action="fill_input", target=".origin", text="Seoul Station"),
        ActionStep(action="submit_form", target=".origin"),
        ActionStep(action="fill_input", target=".destination", text="Songnae Station"),
        ActionStep(action="submit_form", target=".destination"),
        ActionStep(action="click_element", target="button.search"),
        ActionStep(action="verify_page_loaded", target="naver_map_directions"),
        ActionStep(action="click_element", target="route_kind_filter", metadata={"route_kind_filter": "bus"}),
    ]

    reason = executor._resolve_deterministic_streak_reason(  # noqa: SLF001
        command=command,
        fallback_steps=fallback_steps,
        executed_count=6,
        last_result={"status": "success"},
        decision_trace=[
            {
                "index": 1,
                "decision_source": "deterministic_streak",
                "fallback_reason": "deterministic_streak_active",
            }
        ],
    )

    assert reason == "linear_route_fallback_sequence"


def test_resolve_deterministic_streak_reason_uses_initial_route_open() -> None:
    executor = BrowserExecutor()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="Find the bus route from Seoul Station to Songnae Station",
        normalized_text="Find the bus route from Seoul Station to Songnae Station",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="naver_map",
    )
    fallback_steps = [
        ActionStep(action="open_browser_url", target="https://map.naver.com"),
        ActionStep(action="wait_for_element", target=".origin"),
    ]

    reason = executor._resolve_deterministic_streak_reason(  # noqa: SLF001
        command=command,
        fallback_steps=fallback_steps,
        executed_count=0,
        last_result=None,
        decision_trace=[],
    )

    assert reason == "initial_route_open"


def test_resolve_deterministic_streak_reason_skips_verify_and_route_kind_filter() -> None:
    executor = BrowserExecutor()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="Find the bus route from Seoul Station to Songnae Station",
        normalized_text="Find the bus route from Seoul Station to Songnae Station",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="naver_map",
    )
    fallback_steps = [
        ActionStep(action="open_browser_url", target="https://map.naver.com"),
        ActionStep(action="wait_for_element", target=".origin"),
        ActionStep(action="fill_input", target=".origin", text="Seoul Station"),
        ActionStep(action="submit_form", target=".origin"),
        ActionStep(action="fill_input", target=".destination", text="Songnae Station"),
        ActionStep(action="submit_form", target=".destination"),
        ActionStep(action="click_element", target="button.search"),
        ActionStep(action="verify_page_loaded", target="naver_map_directions"),
        ActionStep(action="click_element", target="route_kind_filter", metadata={"route_kind_filter": "bus"}),
    ]

    verify_reason = executor._resolve_deterministic_streak_reason(  # noqa: SLF001
        command=command,
        fallback_steps=fallback_steps,
        executed_count=7,
        last_result={"status": "success"},
        decision_trace=[
            {
                "index": 1,
                "decision_source": "fallback",
                "fallback_reason": "llm_returned_no_step",
            }
        ],
    )
    filter_reason = executor._resolve_deterministic_streak_reason(  # noqa: SLF001
        command=command,
        fallback_steps=fallback_steps,
        executed_count=8,
        last_result={"status": "success", "verification_result": "route_result_loaded"},
        decision_trace=[
            {
                "index": 1,
                "decision_source": "fallback",
                "fallback_reason": "llm_returned_no_step",
            }
        ],
    )

    assert verify_reason is None
    assert filter_reason is None


def test_read_linked_page_uses_runtime_observation_summary_fallback() -> None:
    executor = BrowserExecutor()
    page = _FakePage()
    page.url = "https://example.com/detail"
    page.title_text = "Detail Page"

    async def run() -> dict[str, object]:
        return await executor.execute_action_step_async(
            ActionStep(action="read_linked_page", target="linked_page"),
            context={
                "page": page,
                "runtime_observation": {
                    "page_summary": "Observed summary captured during runtime observation.",
                },
            },
        )

    result = asyncio.run(run())

    assert result["status"] == "success"
    assert result["page_summary"] == "Observed summary captured during runtime observation."


def test_default_search_and_read_steps_prefer_result_page_summary() -> None:
    executor = BrowserExecutor()

    steps = executor._default_search_and_read_steps(  # noqa: SLF001
        CanonicalCommand(
            input_mode="text",
            raw_text="Search Naver for Incheon youth monthly rent support and read the conditions.",
            normalized_text="Search Naver for Incheon youth monthly rent support and read the conditions.",
            task_domain="web",
            intent="search_and_read",
            risk_level="low",
            requires_confirmation=False,
            target_app="browser",
        )
    )

    assert [step.action for step in steps] == [
        "search_web",
        "verify_page_loaded",
        "extract_top_result",
        "read_page_summary",
    ]


def test_default_search_and_read_steps_open_linked_page_for_explicit_detail_request() -> None:
    executor = BrowserExecutor()

    steps = executor._default_search_and_read_steps(  # noqa: SLF001
        CanonicalCommand(
            input_mode="text",
            raw_text="Search Naver for Incheon youth monthly rent support and open the original page to read the full article.",
            normalized_text="Search Naver for Incheon youth monthly rent support and open the original page to read the full article.",
            task_domain="web",
            intent="search_and_read",
            risk_level="low",
            requires_confirmation=False,
            target_app="browser",
        )
    )

    assert [step.action for step in steps] == [
        "search_web",
        "verify_page_loaded",
        "extract_top_result",
        "click_search_result",
        "verify_page_loaded",
        "read_linked_page",
    ]


def test_map_route_kind_filter_step_returns_subway_click_step() -> None:
    executor = BrowserExecutor()

    step = executor._map_route_kind_filter_step("subway")  # noqa: SLF001

    assert step is not None
    assert step.action == "click_element"
    assert step.metadata["route_kind_filter"] == "subway"


class _FakeLocator:
    def __init__(self, text: str = "", href: str | None = None) -> None:
        self._text = text
        self._href = href
        self.filled_text: str | None = None
        self.clicked = False
        self.pressed_key: str | None = None
        self.should_fail_wait = False

    @property
    def first(self) -> "_FakeLocator":
        return self

    async def count(self) -> int:
        return 1

    async def inner_text(self, timeout: int | None = None) -> str:
        return self._text

    async def get_attribute(self, name: str, timeout: int | None = None) -> str | None:
        if name == "href":
            return self._href
        return None

    async def click(self, timeout: int | None = None) -> None:
        self.clicked = True

    async def fill(self, text: str, timeout: int | None = None) -> None:
        self.filled_text = text

    async def press(self, key: str, timeout: int | None = None) -> None:
        self.pressed_key = key

    async def wait_for(self, state: str | None = None, timeout: int | None = None) -> None:
        if self.should_fail_wait:
            raise RuntimeError("timeout waiting for selector")
        return None


class _FakeKeyboard:
    def __init__(self) -> None:
        self.last_key: str | None = None

    async def press(self, key: str) -> None:
        self.last_key = key


class _FakeMouse:
    def __init__(self) -> None:
        self.wheel_calls: list[tuple[int, int]] = []

    async def wheel(self, dx: int, dy: int) -> None:
        self.wheel_calls.append((dx, dy))


class _FakePage:
    def __init__(self, locators: dict[str, _FakeLocator] | None = None) -> None:
        self._locators = locators or {}
        self.url = "https://example.com"
        self.title_text = "Example Page"
        self.evaluate_result = []
        self.keyboard = _FakeKeyboard()
        self.mouse = _FakeMouse()
        self.closed = False
        self.context = None
        self.brought_to_front = False

    async def title(self) -> str:
        return self.title_text

    async def wait_for_timeout(self, ms: int) -> None:
        return None

    async def goto(self, target_url: str, wait_until: str = "domcontentloaded") -> None:
        self.url = target_url

    def locator(self, selector: str) -> _FakeLocator:
        return self._locators.get(selector, _FakeLocator())

    async def evaluate(self, script: str):
        return self.evaluate_result

    def set_default_timeout(self, ms: int) -> None:
        return None

    def is_closed(self) -> bool:
        return self.closed

    async def close(self) -> None:
        self.closed = True
        if self.context is not None and self in self.context.pages:
            self.context.pages.remove(self)

    async def bring_to_front(self) -> None:
        self.brought_to_front = True


class _FakeContext:
    def __init__(self, pages: list[_FakePage] | None = None) -> None:
        self.pages = pages or []
        for page in self.pages:
            page.context = self

    async def new_page(self) -> _FakePage:
        page = _FakePage()
        page.context = self
        self.pages.append(page)
        return page


class _FakeBrowserWithContexts:
    def __init__(self, contexts: list[_FakeContext]) -> None:
        self.contexts = contexts


def test_fill_input_action_uses_selector_and_text() -> None:
    executor = BrowserExecutor()
    locator = _FakeLocator()
    page = _FakePage({"input[name=q]": locator})
    context = {"page": page}

    result = executor.execute_action_step(
        ActionStep(action="fill_input", target="input[name=q]", text="vision navi"),
        context=context,
    )

    assert result["status"] == "success"
    assert locator.filled_text == "vision navi"
    assert context["last_input_selector"] == "input[name=q]"


def test_route_kind_filter_action_fails_when_filter_state_is_not_applied(monkeypatch) -> None:
    executor = BrowserExecutor()
    page = _FakePage()
    page.url = "https://map.naver.com/p/directions/-/-/-/transit?c=15.00,0,0,0,dh"
    page.title_text = "길찾기 - 네이버 지도"
    context = {"page": page}

    async def fake_click_filter(_page, _route_kind):
        return "route_kind:bus"

    monkeypatch.setattr(executor, "_click_map_route_kind_filter_v2_async", fake_click_filter)

    result = executor.execute_action_step(
        ActionStep(action="click_element", target="route_kind_filter", metadata={"route_kind_filter": "bus"}),
        context=context,
    )

    assert result["status"] == "failed"
    assert result["reason"] == "route_kind_filter_not_applied"


def test_route_kind_filter_action_accepts_visible_bus_results(monkeypatch) -> None:
    executor = BrowserExecutor()
    body_locator = _FakeLocator(text="전체 6 버스 3 지하철 3 버스+ 지하철 0 요금 상세보기")
    page = _FakePage({"body": body_locator})
    page.url = "https://map.naver.com/p/directions/3zhqqF,2ALByS/start/3z8dr9,2AIJR0/goal/-/transit?c=14.00,0,0,0,dh"
    page.title_text = "길찾기 - 네이버 지도"
    context = {"page": page}

    async def fake_click_filter(_page, _route_kind):
        return "route_kind:bus"

    monkeypatch.setattr(executor, "_click_map_route_kind_filter_v2_async", fake_click_filter)

    result = executor.execute_action_step(
        ActionStep(action="click_element", target="route_kind_filter", metadata={"route_kind_filter": "bus"}),
        context=context,
    )

    assert result["status"] == "success"
    assert context["route_kind_selected"] == "bus"


def test_submit_form_action_presses_enter_on_selector() -> None:
    executor = BrowserExecutor()
    locator = _FakeLocator()
    page = _FakePage({"input[name=q]": locator})
    context = {"page": page}

    result = executor.execute_action_step(
        ActionStep(action="submit_form", target="input[name=q]"),
        context=context,
    )

    assert result["status"] == "success"
    assert locator.pressed_key == "Enter"


def test_scroll_page_action_uses_metadata_amount() -> None:
    executor = BrowserExecutor()
    page = _FakePage()
    context = {"page": page}

    result = executor.execute_action_step(
        ActionStep(action="scroll_page", metadata={"amount": 1200}),
        context=context,
    )

    assert result["status"] == "success"
    assert page.mouse.wheel_calls == [(0, 1200)]


def test_read_section_action_extracts_normalized_text() -> None:
    executor = BrowserExecutor()
    locator = _FakeLocator("Eligibility\n\nApplication period\nDetails")
    page = _FakePage({"main article": locator})
    context = {"page": page}

    result = executor.execute_action_step(
        ActionStep(action="read_section", target="main article"),
        context=context,
    )

    assert result["status"] == "success"
    assert context["section_text"] == "Eligibility Application period Details"
    assert context["page_summary"] == "Eligibility Application period Details"


def test_search_web_action_uses_google_target() -> None:
    executor = BrowserExecutor()
    page = _FakePage()
    context = {"page": page, "preferred_search_target": "google"}

    result = executor.execute_action_step(
        ActionStep(action="search_web", target="google", text="youtube"),
        context=context,
    )

    assert result["status"] == "success"
    assert page.url == "https://www.google.com/search?q=youtube"
    assert context["search_target"] == "google"


def test_open_browser_url_action_accepts_url_from_text_field() -> None:
    executor = BrowserExecutor()
    page = _FakePage()
    context = {"page": page}

    result = executor.execute_action_step(
        ActionStep(action="open_browser_url", text="https://search.naver.com/search.naver?query=visionnavi"),
        context=context,
    )

    assert result["status"] == "success"
    assert page.url == "https://search.naver.com/search.naver?query=visionnavi"


def test_search_web_action_uses_youtube_results_when_target_is_youtube() -> None:
    executor = BrowserExecutor()
    page = _FakePage()
    context = {"page": page, "preferred_search_target": "youtube"}

    result = executor.execute_action_step(
        ActionStep(action="search_web", target="youtube", text="ive music video"),
        context=context,
    )

    assert result["status"] == "success"
    assert page.url == "https://www.youtube.com/results?search_query=ive+music+video"
    assert context["search_target"] == "youtube"


def test_wait_for_element_action_succeeds_with_selector() -> None:
    executor = BrowserExecutor()
    page = _FakePage({"#search": _FakeLocator()})
    context = {"page": page}

    result = executor.execute_action_step(
        ActionStep(action="wait_for_element", target="#search"),
        context=context,
    )

    assert result["status"] == "success"
    assert result["selector"] == "#search"


def test_wait_for_element_action_reports_failure_detail() -> None:
    executor = BrowserExecutor()
    locator = _FakeLocator()
    locator.should_fail_wait = True
    page = _FakePage({"#slow": locator})
    context = {"page": page}

    result = executor.execute_action_step(
        ActionStep(action="wait_for_element", target="#slow"),
        context=context,
    )

    assert result["status"] == "failed"
    assert result["selector"] == "#slow"
    assert "timeout waiting for selector" in result["detail"]


def test_switch_tab_action_uses_last_target() -> None:
    executor = BrowserExecutor()
    first = _FakePage()
    second = _FakePage()
    first.url = "https://first.example.com"
    second.url = "https://second.example.com"
    fake_context = _FakeContext([first, second])
    context = {"page": first}

    result = executor.execute_action_step(
        ActionStep(action="switch_tab", target="last"),
        context=context,
    )

    assert result["status"] == "success"
    assert context["page"] is second
    assert second.brought_to_front is True
    assert result["url"] == "https://second.example.com"


def test_switch_tab_action_fails_when_no_other_tab_exists() -> None:
    executor = BrowserExecutor()
    only_page = _FakePage()
    _FakeContext([only_page])
    context = {"page": only_page}

    result = executor.execute_action_step(
        ActionStep(action="switch_tab", target="last"),
        context=context,
    )

    assert result["status"] == "failed"
    assert result["reason"] == "tab_not_found"


def test_close_tab_action_switches_to_remaining_page() -> None:
    executor = BrowserExecutor()
    first = _FakePage()
    second = _FakePage()
    first.url = "https://first.example.com"
    second.url = "https://second.example.com"
    _FakeContext([first, second])
    context = {"page": second}

    result = executor.execute_action_step(
        ActionStep(action="close_tab"),
        context=context,
    )

    assert result["status"] == "success"
    assert context["page"] is first
    assert first.brought_to_front is True


def test_summarize_page_action_reads_body_summary() -> None:
    executor = BrowserExecutor()
    page = _FakePage({"main": _FakeLocator("This is a concise body summary for the page.")})
    context = {"page": page}

    result = executor.execute_action_step(
        ActionStep(action="summarize_page"),
        context=context,
    )

    assert result["status"] == "success"
    assert context["page_summary"] == "This is a concise body summary for the page."


def test_extract_top_result_reports_not_found_when_page_is_empty(monkeypatch) -> None:
    executor = BrowserExecutor()
    page = _FakePage()
    context = {"page": page}

    async def fake_extract(page_arg):
        return {"title": None, "snippet": None, "url": None}

    monkeypatch.setattr(executor, "_extract_first_result_async", fake_extract)

    result = executor.execute_action_step(
        ActionStep(action="extract_top_result"),
        context=context,
    )

    assert result["status"] == "failed"
    assert result["reason"] == "top_result_not_found"


def test_click_search_result_uses_download_only_mode_for_pdf() -> None:
    executor = BrowserExecutor()
    page = _FakePage()
    context = {
        "page": page,
        "top_result": {
            "title": "Guide PDF",
            "snippet": "Download the PDF guide",
            "url": "https://example.com/guide.pdf",
        },
    }

    result = executor.execute_action_step(
        ActionStep(action="click_search_result"),
        context=context,
    )

    assert result["status"] == "success"
    assert result["mode"] == "download_only"
    assert context["download_only"] is True


def test_read_linked_page_falls_back_to_top_result_for_download_only() -> None:
    executor = BrowserExecutor()
    page = _FakePage()
    context = {
        "page": page,
        "download_only": True,
        "top_result": {
            "title": "Guide PDF",
            "snippet": "Download the PDF guide",
            "url": "https://example.com/guide.pdf",
        },
    }

    result = executor.execute_action_step(
        ActionStep(action="read_linked_page"),
        context=context,
    )

    assert result["status"] == "success"
    assert context["page_summary"] == "Download the PDF guide"


def test_verify_page_loaded_requires_naver_map_route_result_url() -> None:
    executor = BrowserExecutor()
    page = _FakePage()
    page.url = "https://map.naver.com/p/directions/-/-/-/transit?c=15.00,0,0,0,dh"
    page.title_text = "\uae38\ucc3e\uae30 - \ub124\uc774\ubc84\uc9c0\ub3c4"
    context = {
        "page": page,
        "route_origin": "\uc11c\uc6b8\uc5ed",
        "route_destination": "\uc1a1\ub0b4\uc5ed",
    }

    result = executor.execute_action_step(
        ActionStep(action="verify_page_loaded", target="naver_map_directions"),
        context=context,
    )

    assert result["status"] == "failed"
    assert result["reason"] == "route_result_not_loaded_after_retry"
    assert result["verify_attempts"] == 3


def test_verify_page_loaded_accepts_naver_map_resolved_route_url() -> None:
    executor = BrowserExecutor()
    page = _FakePage()
    page.url = "https://map.naver.com/p/directions/14140434.2528277,4518360.2812695,%EC%84%9C%EC%9A%B8%EC%97%AD,10043607,PLACE_POI/14134478.8897681,4538080.8939994,%EC%86%A1%EB%82%B4%EC%97%AD,11664044,PLACE_POI/transit?c=14.00,0,0,0,dh"
    page.title_text = "\uae38\ucc3e\uae30 - \ub124\uc774\ubc84\uc9c0\ub3c4"
    context = {
        "page": page,
        "route_origin": "\uc11c\uc6b8\uc5ed",
        "route_destination": "\uc1a1\ub0b4\uc5ed",
    }

    result = executor.execute_action_step(
        ActionStep(action="verify_page_loaded", target="naver_map_directions"),
        context=context,
    )

    assert result["status"] == "success"
    assert context["route_verified"] is True


def test_resolve_debug_profile_dir_prefers_project_runtime(monkeypatch) -> None:
    monkeypatch.setenv("VOICE_NAVIGATOR_ROOT", r"C:\VisionNavi")
    executor = BrowserExecutor()

    profile_dir = executor._resolve_debug_profile_dir()  # noqa: SLF001

    assert str(profile_dir) == r"C:\VisionNavi\runtime\chrome_debug_profile"


def test_resolve_page_for_session_reuses_last_non_devtools_page() -> None:
    executor = BrowserExecutor()
    executor._reused_browser = True  # noqa: SLF001
    context = _FakeContext(
        [
            _FakePage(),
            _FakePage(),
            _FakePage(),
        ]
    )
    context.pages[0].url = "devtools://devtools/bundled/inspector.html"
    context.pages[1].url = "https://www.naver.com"
    context.pages[2].url = "https://www.google.com"

    page = executor._resolve_page_for_session(context)  # noqa: SLF001

    assert page.url == "https://www.google.com"


def test_resolve_chrome_path_prefers_explicit_setting(tmp_path) -> None:
    chrome_path = tmp_path / "chrome.exe"
    chrome_path.write_text("", encoding="utf-8")
    executor = BrowserExecutor(
        Settings(
            browser_chrome_executable=str(chrome_path),
        )
    )

    resolved = executor._resolve_chrome_path()  # noqa: SLF001

    assert resolved == str(chrome_path)


def test_browser_is_usable_checks_cdp_endpoint(monkeypatch) -> None:
    executor = BrowserExecutor()
    executor._browser_mode = "cdp"  # noqa: SLF001

    class _FakeBrowser:
        def is_connected(self) -> bool:
            return True

    executor._browser = _FakeBrowser()  # noqa: SLF001
    monkeypatch.setattr(executor, "_is_debug_browser_ready", lambda endpoint: False)

    assert executor._browser_is_usable() is False  # noqa: SLF001


def test_recoverable_playwright_error_retries_once(monkeypatch) -> None:
    executor = BrowserExecutor()
    command = _build_browser_command()
    steps = [ActionStep(action="search_web", target="google", text="youtube")]
    calls = {"count": 0, "reset": 0}

    class _FakePlaywrightError(Exception):
        pass

    fake_async_api = types.ModuleType("playwright.async_api")
    fake_async_api.Error = _FakePlaywrightError

    class _FakeAsyncPlaywrightContext:
        async def __aenter__(self):
            return object()

        async def __aexit__(self, exc_type, exc, tb):
            return None

    fake_async_api.async_playwright = lambda: _FakeAsyncPlaywrightContext()
    monkeypatch.setitem(sys.modules, "playwright.async_api", fake_async_api)

    async def fake_run_once(command_arg, steps_arg, playwright_arg):
        calls["count"] += 1
        if calls["count"] == 1:
            raise _FakePlaywrightError("Target page, context or browser has been closed")
        return {
            "status": "success",
            "executor": "browser",
            "strategy": "llm-action-plan",
            "executed_steps": [],
        }

    monkeypatch.setattr(executor, "_run_action_plan_once", fake_run_once)
    monkeypatch.setattr(
        executor,
        "_restart_debug_browser_runtime",
        lambda: calls.__setitem__("reset", calls["reset"] + 1),
    )

    result = executor.execute_action_plan(command, steps)

    assert result["status"] == "success"
    assert result["recovered_after_browser_restart"] is True
    assert calls == {"count": 2, "reset": 1}


def test_has_reusable_browser_page_ignores_devtools_pages() -> None:
    executor = BrowserExecutor()
    context = _FakeContext([_FakePage(), _FakePage()])
    context.pages[0].url = "devtools://devtools/bundled/inspector.html"
    context.pages[1].url = "https://www.google.com"
    browser = _FakeBrowserWithContexts([context])

    assert executor._has_reusable_browser_page(browser) is True  # noqa: SLF001


def test_connect_or_bootstrap_restarts_when_no_page(monkeypatch) -> None:
    executor = BrowserExecutor()
    restarts = {"count": 0}
    waits = {"count": 0}
    browser = _FakeBrowserWithContexts([_FakeContext([])])

    class _FakeChromium:
        async def connect_over_cdp(self, endpoint: str):
            return browser

    class _FakePlaywright:
        chromium = _FakeChromium()

    monkeypatch.setattr(executor, "_is_debug_browser_ready", lambda endpoint: True)
    monkeypatch.setattr(
        executor,
        "_restart_debug_browser_runtime",
        lambda: restarts.__setitem__("count", restarts["count"] + 1),
    )
    monkeypatch.setattr(
        executor,
        "_has_reusable_browser_page",
        lambda browser_arg: waits.__setitem__("count", waits["count"] + 1) and False,
    )

    result = asyncio.run(executor._connect_or_bootstrap_cdp_browser_async(_FakePlaywright()))  # noqa: SLF001

    assert result is browser
    assert restarts["count"] == 1
    assert waits["count"] == 1


async def _co_return(value):
    return value
