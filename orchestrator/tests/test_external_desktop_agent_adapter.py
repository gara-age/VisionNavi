from app.automation.desktop.executor import DesktopExecutor
from app.automation.desktop.external_agent_adapter import ExternalDesktopAgentAdapter
from app.core.settings import Settings


def _build_adapter() -> ExternalDesktopAgentAdapter:
    return ExternalDesktopAgentAdapter(
        desktop_executor=DesktopExecutor(),
        model_client=object(),  # type: ignore[arg-type]
        settings=Settings.from_env(),
    )


def test_classify_attempt_accepts_exact_match_after_success() -> None:
    adapter = _build_adapter()

    result = adapter._classify_attempt(  # noqa: SLF001
        bridge_result={"status": "success", "durationMs": 1500, "eventCount": 4},
        expected_text="VisionNavi external desktop verification",
        observed_text="VisionNavi external desktop verification",
    )

    assert result["result_status"] == "success"
    assert result["failure_reason"] is None
    assert result["validation"]["exact_match"] is True


def test_classify_attempt_marks_partial_saved_text() -> None:
    adapter = _build_adapter()

    result = adapter._classify_attempt(  # noqa: SLF001
        bridge_result={"status": "success", "durationMs": 1500, "eventCount": 4},
        expected_text="VisionNavi external desktop verification",
        observed_text="VisionNavi external desktop verification extra",
    )

    assert result["result_status"] == "failed"
    assert result["failure_reason"] == "external_desktop_agent_partial_text_saved"
    assert result["validation"]["contains_expected_text"] is True


def test_classify_attempt_marks_timeout() -> None:
    adapter = _build_adapter()

    result = adapter._classify_attempt(  # noqa: SLF001
        bridge_result={
            "status": "failed",
            "reason": "bridge_subprocess_timeout",
            "error": "Request timed out.",
            "durationMs": 180000,
        },
        expected_text="VisionNavi external desktop verification",
        observed_text="",
    )

    assert result["result_status"] == "failed"
    assert result["failure_reason"] == "external_desktop_agent_timeout"


def test_classify_attempt_normalizes_line_endings_and_outer_whitespace() -> None:
    adapter = _build_adapter()

    result = adapter._classify_attempt(  # noqa: SLF001
        bridge_result={"status": "success", "durationMs": 900},
        expected_text="VisionNavi external desktop verification\r\nline two",
        observed_text="  VisionNavi external desktop verification\nline two  ",
    )

    assert result["result_status"] == "success"
    assert result["validation"]["exact_match"] is True
    assert result["validation"]["contains_expected_text"] is True


def test_should_retry_attempt_only_for_empty_timeout_like_failures() -> None:
    adapter = _build_adapter()

    assert adapter._should_retry_attempt(  # noqa: SLF001
        {
            "failure_reason": "external_desktop_agent_timeout",
            "validation": {"observed_non_empty": False},
        }
    )
    assert not adapter._should_retry_attempt(  # noqa: SLF001
        {
            "failure_reason": "external_desktop_agent_partial_text_saved",
            "validation": {"observed_non_empty": True},
        }
    )
    assert adapter._should_retry_attempt(  # noqa: SLF001
        {
            "failure_reason": "external_desktop_agent_bridge_failed:agent_incomplete",
            "validation": {"observed_non_empty": False},
        }
    )
