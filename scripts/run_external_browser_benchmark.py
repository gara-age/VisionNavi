from __future__ import annotations

import argparse
import json
import re
import time
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

import httpx


DEFAULT_COMMANDS = [
    "Search Naver for VisionNavi and read a short summary.",
    "Search Naver for Incheon youth monthly rent support and read the conditions.",
    "Search Google for YouTube and summarize the results page.",
    "Search Naver for Seoul youth housing support and read the eligibility conditions.",
    "Search Google for OpenAI Codex and summarize the results page.",
]


def _infer_preferred_language(text: str) -> str:
    if re.search(r"[\u3040-\u30ff\u4e00-\u9faf]", text):
        return "ja"
    if re.search(r"[\uac00-\ud7a3]", text):
        return "ko"
    if re.search(r"[A-Za-z]", text):
        return "en"
    return "unknown"


@dataclass
class BrowserBenchmarkResult:
    command: str
    session_id: str
    requested_backend: str
    effective_backend: str | None
    fallback_backend: str | None
    outcome_class: str
    session_status: str | None
    result_status: str | None
    success: bool
    external_only_success: bool
    used_fallback: bool
    failure_reason: str | None
    duration_ms: float | int | None
    step_count: int | None
    matched_tokens: list[str]
    query_tokens: list[str]
    visited_domains: list[str]
    final_domain: str | None
    provider_match: bool | None
    query_preserved: bool | None
    language_match: bool | None
    attempted_repair: bool | None
    blocked_before_execution: bool


def _poll_session(
    client: httpx.Client,
    base_url: str,
    session_id: str,
    timeout_s: int,
) -> dict[str, Any]:
    deadline = time.time() + timeout_s
    last_snapshot: dict[str, Any] | None = None
    while time.time() < deadline:
        response = client.get(f"{base_url}/pipeline/sessions/{session_id}")
        response.raise_for_status()
        snapshot = response.json()
        last_snapshot = snapshot
        result = snapshot.get("result")
        if isinstance(result, dict) and result.get("status") in {"success", "failed"}:
            return snapshot
        time.sleep(2)
    if last_snapshot is None:
        raise RuntimeError("no_session_snapshot_received")
    return last_snapshot


def _extract_result(command: str, session_id: str, snapshot: dict[str, Any]) -> BrowserBenchmarkResult:
    result = snapshot.get("result") or {}
    summary = result.get("execution_summary") or {}
    validation = (result.get("raw_agent_trace") or {}).get("validation") or result.get("validation") or {}
    constraint_validation = result.get("constraint_validation") or validation
    matched_tokens = validation.get("matched_tokens") or []
    query_tokens = validation.get("query_tokens") or []
    visited_domains = validation.get("visited_domains") or []
    final_domain = validation.get("final_domain")
    provider_match = validation.get("reason") not in {
        "external_browser_agent_provider_mismatch",
        "external_browser_agent_off_target_navigation",
    }
    query_preserved = validation.get("reason") != "external_browser_agent_query_changed"
    language_match = validation.get("reason") != "external_browser_agent_unexpected_language"
    attempted_repair = constraint_validation.get("attempted_repair") if isinstance(constraint_validation, dict) else None
    failure_reason = summary.get("failure_reason") or result.get("failure_reason")
    result_status = result.get("status")
    fallback_backend = summary.get("fallback_backend")
    outcome_class = _classify_outcome(result_status, fallback_backend)
    blocked_before_execution = str(result.get("strategy") or "") == "command-constraint-validator"
    return BrowserBenchmarkResult(
        command=command,
        session_id=session_id,
        requested_backend="external_browser_agent",
        effective_backend=result.get("execution_backend"),
        fallback_backend=fallback_backend,
        outcome_class=outcome_class,
        session_status=snapshot.get("status"),
        result_status=result_status,
        success=bool(result_status == "success"),
        external_only_success=outcome_class == "external_only_success",
        used_fallback=bool(fallback_backend),
        failure_reason=failure_reason,
        duration_ms=summary.get("duration_ms") or result.get("duration_ms"),
        step_count=summary.get("step_count") or result.get("step_count"),
        matched_tokens=list(matched_tokens),
        query_tokens=list(query_tokens),
        visited_domains=list(visited_domains),
        final_domain=final_domain,
        provider_match=provider_match,
        query_preserved=query_preserved,
        language_match=language_match,
        attempted_repair=attempted_repair,
        blocked_before_execution=blocked_before_execution,
    )


def _classify_outcome(result_status: str | None, fallback_backend: str | None) -> str:
    if str(result_status).lower() != "success":
        return "failed"
    if fallback_backend:
        return "success_with_internal_fallback"
    return "external_only_success"


def _build_summary(results: list[BrowserBenchmarkResult]) -> dict[str, Any]:
    if not results:
        return {
            "total_runs": 0,
            "successes": 0,
            "success_rate": 0.0,
            "external_only_successes": 0,
            "external_only_success_rate": 0.0,
            "fallback_successes": 0,
            "fallback_success_rate": 0.0,
            "failures": 0,
            "average_duration_ms": None,
            "average_step_count": None,
            "provider_match_rate": None,
            "query_preservation_rate": None,
            "language_match_rate": None,
            "repair_success_rate": None,
            "blocked_before_execution_count": 0,
            "by_command": [],
        }

    success_count = sum(1 for item in results if item.success)
    external_only_success_count = sum(1 for item in results if item.external_only_success)
    fallback_success_count = sum(1 for item in results if item.outcome_class == "success_with_internal_fallback")
    failure_count = sum(1 for item in results if item.outcome_class == "failed")
    durations = [float(item.duration_ms) for item in results if item.duration_ms is not None]
    step_counts = [item.step_count for item in results if item.step_count is not None]
    grouped: dict[str, list[BrowserBenchmarkResult]] = {}
    provider_matches = [item.provider_match for item in results if item.provider_match is not None]
    query_preserved = [item.query_preserved for item in results if item.query_preserved is not None]
    language_matches = [item.language_match for item in results if item.language_match is not None]
    repairs = [item for item in results if item.attempted_repair is True]
    for item in results:
        grouped.setdefault(item.command, []).append(item)

    by_command = []
    for command, items in grouped.items():
        command_successes = sum(1 for item in items if item.success)
        command_durations = [float(item.duration_ms) for item in items if item.duration_ms is not None]
        by_command.append(
            {
                "command": command,
                "runs": len(items),
                "successes": command_successes,
                "success_rate": round(command_successes / len(items), 4),
                "external_only_successes": sum(1 for item in items if item.external_only_success),
                "fallback_successes": sum(
                    1 for item in items if item.outcome_class == "success_with_internal_fallback"
                ),
                "failures": sum(1 for item in items if item.outcome_class == "failed"),
                "average_duration_ms": round(sum(command_durations) / len(command_durations), 2)
                if command_durations
                else None,
                "failure_reasons": sorted(
                    {
                        item.failure_reason
                        for item in items
                        if item.failure_reason
                    }
                ),
                "provider_match_rate": round(
                    sum(1 for item in items if item.provider_match is True) / len([item for item in items if item.provider_match is not None]),
                    4,
                ) if any(item.provider_match is not None for item in items) else None,
                "query_preservation_rate": round(
                    sum(1 for item in items if item.query_preserved is True) / len([item for item in items if item.query_preserved is not None]),
                    4,
                ) if any(item.query_preserved is not None for item in items) else None,
                "language_match_rate": round(
                    sum(1 for item in items if item.language_match is True) / len([item for item in items if item.language_match is not None]),
                    4,
                ) if any(item.language_match is not None for item in items) else None,
                "repair_success_rate": round(
                    sum(1 for item in items if item.attempted_repair and item.success) / len([item for item in items if item.attempted_repair is True]),
                    4,
                ) if any(item.attempted_repair is True for item in items) else None,
                "blocked_before_execution_count": sum(1 for item in items if item.blocked_before_execution),
            }
        )

    return {
        "total_runs": len(results),
        "successes": success_count,
        "success_rate": round(success_count / len(results), 4),
        "external_only_successes": external_only_success_count,
        "external_only_success_rate": round(external_only_success_count / len(results), 4),
        "fallback_successes": fallback_success_count,
        "fallback_success_rate": round(fallback_success_count / len(results), 4),
        "failures": failure_count,
        "average_duration_ms": round(sum(durations) / len(durations), 2) if durations else None,
        "average_step_count": round(sum(step_counts) / len(step_counts), 2) if step_counts else None,
        "provider_match_rate": round(sum(1 for item in provider_matches if item) / len(provider_matches), 4)
        if provider_matches
        else None,
        "query_preservation_rate": round(sum(1 for item in query_preserved if item) / len(query_preserved), 4)
        if query_preserved
        else None,
        "language_match_rate": round(sum(1 for item in language_matches if item) / len(language_matches), 4)
        if language_matches
        else None,
        "repair_success_rate": round(sum(1 for item in repairs if item.attempted_repair and item.success) / len(repairs), 4)
        if repairs
        else None,
        "blocked_before_execution_count": sum(1 for item in results if item.blocked_before_execution),
        "by_command": by_command,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Run VisionNavi external browser benchmark.")
    parser.add_argument("--base-url", default="http://127.0.0.1:8010")
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--timeout-s", type=int, default=420)
    parser.add_argument("--output-dir", default="logs/benchmarks")
    parser.add_argument("--command", action="append", dest="commands")
    args = parser.parse_args()

    commands = args.commands or DEFAULT_COMMANDS
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    started_at = datetime.now().strftime("%Y%m%d-%H%M%S")
    output_path = output_dir / f"external-browser-benchmark-{started_at}.json"

    all_results: list[BrowserBenchmarkResult] = []
    with httpx.Client(timeout=120.0) as client:
        for command in commands:
            for attempt in range(1, args.repeats + 1):
                response = client.post(
                    f"{args.base_url}/pipeline/run",
                    json={
                        "text": command,
                        "execution_backend": "external_browser_agent",
                        "preferred_language": _infer_preferred_language(command),
                    },
                )
                response.raise_for_status()
                session_id = response.json()["session_id"]
                snapshot = _poll_session(client, args.base_url, session_id, args.timeout_s)
                result = _extract_result(command, session_id, snapshot)
                all_results.append(result)
                print(
                    json.dumps(
                        {
                            "attempt": attempt,
                            **asdict(result),
                        },
                        ensure_ascii=False,
                    )
                )

    payload = {
        "started_at": started_at,
        "base_url": args.base_url,
        "repeats": args.repeats,
        "commands": commands,
        "summary": _build_summary(all_results),
        "results": [asdict(item) for item in all_results],
    }
    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(payload["summary"], ensure_ascii=False, indent=2))
    print(f"saved: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
