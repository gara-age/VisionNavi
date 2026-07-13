import asyncio

from app.automation.browser.executor import BrowserExecutor
from app.automation.browser.external_agent_adapter import ExternalBrowserAgentAdapter
from app.core.settings import Settings
from app.models.agent_adapter import AgentAdapterRequest
from app.models.canonical_command import CanonicalCommand


def _build_adapter() -> ExternalBrowserAgentAdapter:
    return ExternalBrowserAgentAdapter(
        browser_executor=BrowserExecutor(),
        model_client=object(),  # type: ignore[arg-type]
        settings=Settings.from_env(),
    )


def test_validate_run_output_accepts_grounded_summary() -> None:
    adapter = _build_adapter()
    request = AgentAdapterRequest(
        command=CanonicalCommand(
            input_mode="text",
            raw_text="Search Naver for VisionNavi and read a short summary.",
            normalized_text="Search Naver for VisionNavi and read a short summary.",
            task_domain="web",
            intent="search_and_read",
            risk_level="low",
            requires_confirmation=False,
            target_app="browser",
            notes=[],
        ),
        observation={},
    )

    result = adapter._validate_run_output(  # noqa: SLF001
        search_request={"target": "naver", "query": "VisionNavi"},
        summary="VisionNavi is an automation project that interprets commands and executes them in browser and desktop environments.",
        history_urls=["https://search.naver.com/search.naver?query=VisionNavi"],
        callback_steps=[{"title": "VisionNavi search results"}],
        request=request,
    )

    assert result["ok"] is True
    assert result["reason"] is None


def test_validate_run_output_rejects_off_target_navigation() -> None:
    adapter = _build_adapter()
    request = AgentAdapterRequest(
        command=CanonicalCommand(
            input_mode="text",
            raw_text="Search Google for VisionNavi and read a short summary.",
            normalized_text="Search Google for VisionNavi and read a short summary.",
            task_domain="web",
            intent="search_and_read",
            risk_level="low",
            requires_confirmation=False,
            target_app="browser",
            notes=[],
        ),
        observation={},
    )

    result = adapter._validate_run_output(  # noqa: SLF001
        search_request={"target": "google", "query": "VisionNavi"},
        summary="VisionNavi appears to be a browser automation tool.",
        history_urls=["https://www.amazon.com/s?k=laptop"],
        callback_steps=[{"title": "Amazon.com: laptops"}],
        request=request,
    )

    assert result["ok"] is False
    assert result["reason"] == "external_browser_agent_off_target_navigation"


def test_validate_run_output_rejects_navigation_drift_when_final_domain_is_wrong() -> None:
    adapter = _build_adapter()
    request = AgentAdapterRequest(
        command=CanonicalCommand(
            input_mode="text",
            raw_text="Search Naver for Incheon youth monthly rent support and read the conditions.",
            normalized_text="Search Naver for Incheon youth monthly rent support and read the conditions.",
            task_domain="web",
            intent="search_and_read",
            risk_level="low",
            requires_confirmation=False,
            target_app="browser",
            notes=[],
        ),
        observation={},
    )

    result = adapter._validate_run_output(  # noqa: SLF001
        search_request={"target": "naver", "query": "Incheon youth monthly rent support"},
        summary="Incheon youth monthly rent support information from Naver results.",
        history_urls=[
            "https://search.naver.com/search.naver?query=incheon+youth+monthly+rent+support",
            "https://duckduckgo.com/?q=seoul+rent+support",
        ],
        callback_steps=[{"title": "Naver result page"}],
        request=request,
    )

    assert result["ok"] is False
    assert result["reason"] == "external_browser_agent_off_target_navigation"
    assert result["final_domain"] == "duckduckgo.com"


def test_validate_run_output_rejects_off_target_summary() -> None:
    adapter = _build_adapter()
    request = AgentAdapterRequest(
        command=CanonicalCommand(
            input_mode="text",
            raw_text="Search Naver for Incheon youth monthly rent support and read the conditions.",
            normalized_text="Search Naver for Incheon youth monthly rent support and read the conditions.",
            task_domain="web",
            intent="search_and_read",
            risk_level="low",
            requires_confirmation=False,
            target_app="browser",
            notes=[],
        ),
        observation={},
    )

    result = adapter._validate_run_output(  # noqa: SLF001
        search_request={"target": "naver", "query": "Incheon youth monthly rent support"},
        summary="This page compares the latest gaming laptops and online shopping deals.",
        history_urls=["https://search.naver.com/search.naver?query=incheon+youth+monthly+rent+support"],
        callback_steps=[{"title": "Laptop deals"}],
        request=request,
    )

    assert result["ok"] is False
    assert result["reason"] == "external_browser_agent_off_target_summary"


def test_validate_run_output_keeps_single_token_query_like_youtube() -> None:
    adapter = _build_adapter()
    request = AgentAdapterRequest(
        command=CanonicalCommand(
            input_mode="text",
            raw_text="Search Google for YouTube and summarize the results page.",
            normalized_text="Search Google for YouTube and summarize the results page.",
            task_domain="web",
            intent="search_and_read",
            risk_level="low",
            requires_confirmation=False,
            target_app="browser",
            notes=[],
        ),
        observation={},
    )

    result = adapter._validate_run_output(  # noqa: SLF001
        search_request={"target": "google", "query": "YouTube"},
        summary="Google results page for YouTube with links to the official video platform.",
        history_urls=["https://www.google.com/search?q=youtube"],
        callback_steps=[{"title": "YouTube - Google Search"}],
        request=request,
    )

    assert result["ok"] is True
    assert result["matched_tokens"] == ["youtube"]


def test_prepare_clean_browser_session_resets_to_single_blank_page() -> None:
    adapter = _build_adapter()

    class FakePage:
        def __init__(self, url: str) -> None:
            self.url = url
            self.closed = False
            self.goto_calls: list[str] = []

        async def close(self) -> None:
            self.closed = True

        async def goto(self, url: str, wait_until: str | None = None) -> None:
            self.url = url
            self.goto_calls.append(url)

    class FakeContext:
        def __init__(self, pages: list[FakePage]) -> None:
            self.pages = pages

        async def new_page(self) -> FakePage:
            page = FakePage("about:blank")
            self.pages.append(page)
            return page

    class FakeBrowser:
        def __init__(self) -> None:
            self.contexts = [
                FakeContext(
                    [
                        FakePage("https://map.naver.com"),
                        FakePage("https://search.naver.com/search.naver?query=visionnavi"),
                    ]
                )
            ]
            self.closed = False

        async def new_context(self) -> FakeContext:
            context = FakeContext([])
            self.contexts.append(context)
            return context

        async def close(self) -> None:
            self.closed = True

    class FakeChromium:
        def __init__(self, browser: FakeBrowser) -> None:
            self.browser = browser

        async def connect_over_cdp(self, endpoint: str) -> FakeBrowser:
            assert endpoint == "http://127.0.0.1:9222"
            return self.browser

    class FakePlaywrightContext:
        def __init__(self, browser: FakeBrowser) -> None:
            self.browser = browser

        async def __aenter__(self):
            return type("FakePlaywright", (), {"chromium": FakeChromium(self.browser)})()

        async def __aexit__(self, exc_type, exc, tb) -> None:
            return None

    fake_browser = FakeBrowser()
    cleanup = asyncio.run(
        adapter._prepare_clean_browser_session(  # noqa: SLF001
            lambda: FakePlaywrightContext(fake_browser),
            "http://127.0.0.1:9222",
        )
    )

    remaining_pages = fake_browser.contexts[0].pages
    assert cleanup["closed_pages"] == 1
    assert cleanup["reset_pages"] == 1
    assert cleanup["created_page"] is False
    assert remaining_pages[0].goto_calls == ["about:blank"]
    assert remaining_pages[1].closed is True
    assert fake_browser.closed is True
