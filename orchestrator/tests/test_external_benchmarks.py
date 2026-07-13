from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import sys


def _load_module(relative_path: str, module_name: str):
    project_root = Path(__file__).resolve().parents[2]
    module_path = project_root / relative_path
    spec = spec_from_file_location(module_name, module_path)
    assert spec is not None
    assert spec.loader is not None
    module = module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


browser_benchmark_module = _load_module("scripts/run_external_browser_benchmark.py", "browser_benchmark_module")
desktop_benchmark_module = _load_module("scripts/run_external_desktop_benchmark.py", "desktop_benchmark_module")

BrowserBenchmarkResult = browser_benchmark_module.BrowserBenchmarkResult
build_browser_summary = browser_benchmark_module._build_summary
build_desktop_summary = desktop_benchmark_module._build_summary
compute_text_validation = desktop_benchmark_module._compute_text_validation
extract_desktop_result = desktop_benchmark_module._extract_result


def test_desktop_benchmark_uses_final_text_validation_separately_from_external_attempt() -> None:
    snapshot = {
        "status": "complete",
        "result": {
            "status": "success",
            "execution_backend": "external_desktop_agent",
            "execution_summary": {
                "backend": "external_desktop_agent",
                "fallback_backend": "internal_desktop",
                "failure_reason": "external_desktop_agent_bridge_failed:agent_incomplete",
                "duration_ms": 1234.0,
                "step_count": 4,
            },
            "text": "VisionNavi external desktop verification",
            "observed_text": "VisionNavi external desktop verification",
            "external_backend_result": {
                "status": "failed",
                "validation": {
                    "exact_match": False,
                    "contains_expected_text": False,
                },
            },
            "raw_agent_trace": {
                "validation": {
                    "exact_match": False,
                    "contains_expected_text": False,
                }
            },
        },
    }

    result = extract_desktop_result("command", "session-1", snapshot)

    assert result.outcome_class == "success_with_internal_fallback"
    assert result.final_exact_match is True
    assert result.final_contains_expected_text is True
    assert result.external_exact_match is False
    assert result.external_contains_expected_text is False


def test_compute_text_validation_normalizes_line_endings_and_whitespace() -> None:
    validation = compute_text_validation("hello\r\nworld", "  hello\nworld  ")

    assert validation["exact_match"] is True
    assert validation["contains_expected_text"] is True


def test_browser_benchmark_summary_splits_external_only_and_fallback_success() -> None:
    summary = build_browser_summary(
        [
            BrowserBenchmarkResult(
                command="a",
                session_id="1",
                requested_backend="external_browser_agent",
                effective_backend="external_browser_agent",
                fallback_backend=None,
                outcome_class="external_only_success",
                session_status="complete",
                result_status="success",
                success=True,
                external_only_success=True,
                used_fallback=False,
                failure_reason=None,
                duration_ms=1000.0,
                step_count=2,
                matched_tokens=[],
                query_tokens=[],
                visited_domains=[],
                final_domain=None,
                provider_match=True,
                query_preserved=True,
                language_match=True,
                attempted_repair=False,
                blocked_before_execution=False,
            ),
            BrowserBenchmarkResult(
                command="a",
                session_id="2",
                requested_backend="external_browser_agent",
                effective_backend="external_browser_agent",
                fallback_backend="internal_browser",
                outcome_class="success_with_internal_fallback",
                session_status="complete",
                result_status="success",
                success=True,
                external_only_success=False,
                used_fallback=True,
                failure_reason="external_browser_agent_execution_failed",
                duration_ms=1500.0,
                step_count=3,
                matched_tokens=[],
                query_tokens=[],
                visited_domains=[],
                final_domain=None,
                provider_match=True,
                query_preserved=True,
                language_match=True,
                attempted_repair=True,
                blocked_before_execution=False,
            ),
            BrowserBenchmarkResult(
                command="b",
                session_id="3",
                requested_backend="external_browser_agent",
                effective_backend="external_browser_agent",
                fallback_backend=None,
                outcome_class="failed",
                session_status="complete",
                result_status="failed",
                success=False,
                external_only_success=False,
                used_fallback=False,
                failure_reason="external_browser_agent_off_target_navigation",
                duration_ms=2000.0,
                step_count=1,
                matched_tokens=[],
                query_tokens=[],
                visited_domains=[],
                final_domain=None,
                provider_match=False,
                query_preserved=True,
                language_match=True,
                attempted_repair=False,
                blocked_before_execution=True,
            ),
        ]
    )

    assert summary["successes"] == 2
    assert summary["external_only_successes"] == 1
    assert summary["fallback_successes"] == 1
    assert summary["failures"] == 1
    assert summary["provider_match_rate"] == 0.6667
    assert summary["repair_success_rate"] == 1.0
    assert summary["blocked_before_execution_count"] == 1


def test_desktop_benchmark_summary_splits_final_and_external_exact_match() -> None:
    snapshot = {
        "status": "complete",
        "result": {
            "status": "success",
            "execution_backend": "external_desktop_agent",
            "execution_summary": {
                "backend": "external_desktop_agent",
                "fallback_backend": "internal_desktop",
                "failure_reason": "external_desktop_agent_bridge_failed:agent_incomplete",
                "duration_ms": 1234.0,
                "step_count": 4,
            },
            "text": "VisionNavi external desktop verification",
            "observed_text": "VisionNavi external desktop verification",
            "external_backend_result": {
                "status": "failed",
                "validation": {
                    "exact_match": False,
                    "contains_expected_text": False,
                },
            },
        },
    }

    summary = build_desktop_summary([extract_desktop_result("command", "session-1", snapshot)])

    assert summary["external_only_successes"] == 0
    assert summary["fallback_successes"] == 1
    assert summary["by_command"][0]["final_exact_matches"] == 1
    assert summary["by_command"][0]["external_exact_matches"] == 0
