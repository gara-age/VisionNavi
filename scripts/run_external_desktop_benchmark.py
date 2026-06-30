from __future__ import annotations

import argparse
import json
import time
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

import httpx


DEFAULT_COMMANDS = [
    "Open Notepad and type exactly VisionNavi external desktop verification, then save the file.",
    "Open Notepad and type exactly External desktop benchmark line one, then save the file.",
    "Open Notepad and type exactly VisionNavi retry taxonomy check, then save the file.",
]


@dataclass
class DesktopBenchmarkResult:
    command: str
    session_id: str
    requested_backend: str
    effective_backend: str | None
    fallback_backend: str | None
    session_status: str | None
    result_status: str | None
    success: bool
    failure_reason: str | None
    duration_ms: float | int | None
    step_count: int | None
    attempt_count: int | None
    expected_text: str | None
    observed_text: str | None
    exact_match: bool | None
    contains_expected_text: bool | None
    file_path: str | None


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


def _extract_result(command: str, session_id: str, snapshot: dict[str, Any]) -> DesktopBenchmarkResult:
    result = snapshot.get("result") or {}
    summary = result.get("execution_summary") or {}
    validation = (result.get("raw_agent_trace") or {}).get("validation") or result.get("validation") or {}
    expected_text = result.get("text")
    observed_text = result.get("observed_text")
    result_status = result.get("status")
    return DesktopBenchmarkResult(
        command=command,
        session_id=session_id,
        requested_backend="external_desktop_agent",
        effective_backend=result.get("execution_backend"),
        fallback_backend=summary.get("fallback_backend"),
        session_status=snapshot.get("status"),
        result_status=result_status,
        success=bool(result_status == "success"),
        failure_reason=summary.get("failure_reason") or result.get("failure_reason"),
        duration_ms=summary.get("duration_ms") or result.get("duration_ms"),
        step_count=summary.get("step_count") or result.get("step_count"),
        attempt_count=result.get("attempt_count"),
        expected_text=expected_text,
        observed_text=observed_text,
        exact_match=validation.get("exact_match"),
        contains_expected_text=validation.get("contains_expected_text"),
        file_path=result.get("file_path"),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Run VisionNavi external desktop benchmark.")
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
    output_path = output_dir / f"external-desktop-benchmark-{started_at}.json"

    all_results: list[DesktopBenchmarkResult] = []
    with httpx.Client(timeout=120.0) as client:
        for command in commands:
            for attempt in range(1, args.repeats + 1):
                response = client.post(
                    f"{args.base_url}/pipeline/run",
                    json={
                        "text": command,
                        "execution_backend": "external_desktop_agent",
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
        "results": [asdict(item) for item in all_results],
    }
    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"saved: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
