from app.automation.browser.executor import BrowserExecutor
from app.models.action_step import ActionStep
from app.models.canonical_command import CanonicalCommand


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


def test_observe_browser_command_returns_query() -> None:
    executor = BrowserExecutor()

    observation = executor.observe(_build_browser_command())

    assert observation["task_domain"] == "web"
    assert observation["query"] == "incheon youth monthly rent support"


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

    monkeypatch.setattr(executor, "execute_action_step", fake_execute_action_step)

    result = executor.execute_action_plan(command, steps)

    assert result["status"] == "success"
    assert result["strategy"] == "llm-action-plan"
    assert result["top_result_title"] == "Incheon Youth Rent Support"
    assert result["linked_page_url"] == "https://example.com/rent-support"
    assert result["page_summary"] == "Eligibility and application details"
    assert len(result["executed_steps"]) == 5
