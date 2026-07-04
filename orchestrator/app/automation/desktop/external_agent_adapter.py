from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path
from typing import Any

from app.core.settings import Settings
from app.automation.desktop.executor import DesktopExecutor
from app.models.agent_adapter import AgentAdapterRequest, AgentAdapterResponse
from app.models.execution_backend import ExecutionBackend
from app.services.model_client import RemoteModelClient


class ExternalDesktopAgentAdapter:
    def __init__(
        self,
        desktop_executor: DesktopExecutor,
        model_client: RemoteModelClient,
        settings: Settings | None = None,
    ) -> None:
        self.desktop_executor = desktop_executor
        self.model_client = model_client
        self.settings = settings or Settings.from_env()
        self.execution_backend: ExecutionBackend = "external_desktop_agent"

    def supports(self, request: AgentAdapterRequest) -> bool:
        return request.command.task_domain == "desktop" and request.command.intent == "open_notepad_and_type"

    def execute(self, request: AgentAdapterRequest) -> AgentAdapterResponse:
        text = self.desktop_executor._extract_notepad_text(request.command.raw_text)  # noqa: SLF001
        if not text:
            return AgentAdapterResponse(
                status="failed",
                execution_backend=self.execution_backend,
                blocked_reason="external_desktop_agent_empty_text",
                raw_agent_trace={"adapter": self.execution_backend},
                normalized_agent_trace=[
                    {"phase": "observe", "detail": "Prepared desktop task input"},
                    {"phase": "decide", "detail": "Could not extract Notepad text from the command"},
                ],
            )

        note_path = self.desktop_executor._build_note_path(  # noqa: SLF001
            f"visionnavi-external-note-{int(time.time() * 1000)}.txt"
        )
        note_path.write_text("", encoding="utf-8")

        preopened_notepad = False
        notepad_pid: int | None = None
        if self.settings.external_desktop_agent_preopen_notepad:
            process = subprocess.Popen(["notepad.exe", str(note_path)])
            notepad_pid = process.pid
            preopened_notepad = True
            time.sleep(1.0)

        bridge_dir = self._resolve_bridge_dir()
        bridge_script = bridge_dir / self.settings.external_desktop_agent_bridge_script
        raw_trace: dict[str, object] = {
            "adapter": self.execution_backend,
            "runtime": "ui-tars",
            "request": {
                "command": request.command.model_dump(),
                "observation": request.observation,
                "policy_flags": request.policy_flags,
            },
            "bridge_dir": str(bridge_dir),
            "bridge_script": str(bridge_script),
            "note_path": str(note_path),
            "preopened_notepad": preopened_notepad,
            "notepad_pid": notepad_pid,
        }

        if not bridge_script.exists():
            return AgentAdapterResponse(
                status="failed",
                execution_backend=self.execution_backend,
                blocked_reason="external_desktop_agent_bridge_missing",
                raw_agent_trace=raw_trace,
                normalized_agent_trace=[
                    {"phase": "observe", "detail": "Prepared UI-TARS bridge request"},
                    {"phase": "decide", "detail": "UI-TARS bridge script is missing"},
                ],
            )

        attempts: list[dict[str, object]] = []
        normalized_trace = [
            {"phase": "observe", "detail": "Prepared UI-TARS instruction and target Notepad file"},
        ]
        final_outcome: dict[str, Any] | None = None

        for attempt_number in (1, 2):
            retry_mode = attempt_number > 1
            payload = self._build_payload(
                text,
                note_path,
                preopened_notepad=preopened_notepad,
                retry_mode=retry_mode,
            )
            attempt = self._run_bridge_attempt(
                bridge_dir=bridge_dir,
                bridge_script=bridge_script,
                payload=payload,
                note_path=note_path,
                expected_text=text,
                attempt_number=attempt_number,
            )
            attempts.append(attempt)
            normalized_trace.extend(
                [
                    {
                        "phase": "decide",
                        "detail": f"Ran UI-TARS desktop bridge attempt {attempt_number}"
                        + (" with stronger retry instruction" if retry_mode else ""),
                    },
                    {
                        "phase": "act",
                        "detail": f"UI-TARS attempt {attempt_number} finished with bridge status {attempt['bridge_result'].get('status', 'unknown')}",
                    },
                    {
                        "phase": "verify",
                        "detail": f"Attempt {attempt_number} verification status: {attempt['result_status']}",
                        "payload": self._safe_payload(attempt["validation"]),
                    },
                ]
            )
            final_outcome = attempt
            if attempt["result_status"] == "success":
                break
            if not self._should_retry_attempt(attempt):
                break
            time.sleep(0.6)

        assert final_outcome is not None
        raw_trace["attempts"] = attempts
        raw_trace["payload"] = attempts[0]["payload"]
        raw_trace["bridge_stdout"] = final_outcome["stdout"]
        raw_trace["bridge_stderr"] = final_outcome["stderr"]
        raw_trace["bridge_exit_code"] = final_outcome["bridge_exit_code"]
        raw_trace["bridge_result"] = final_outcome["bridge_result"]
        raw_trace["validation"] = final_outcome["validation"]

        observed_text = str(final_outcome["observed_text"])
        result_status = str(final_outcome["result_status"])
        duration_ms = final_outcome["duration_ms"]
        failure_reason = None if result_status == "success" else str(final_outcome["failure_reason"])
        normalized_trace = [
            *normalized_trace,
            {
                "phase": "recover",
                "detail": "No retry was needed" if len(attempts) == 1 else f"Retried once after {attempts[0]['failure_reason']}",
                "payload": {
                    "attempt_count": len(attempts),
                    "final_failure_reason": failure_reason,
                },
            },
        ]

        return AgentAdapterResponse(
            status=result_status,
            execution_backend=self.execution_backend,
            result={
                "status": result_status,
                "executor": "desktop",
                "strategy": "ui-tars",
                "file_path": str(note_path),
                "text": text,
                "observed_text": observed_text,
                "bridge_result": final_outcome["bridge_result"],
                "preopened_notepad": preopened_notepad,
                "duration_ms": duration_ms,
                "step_count": final_outcome["bridge_result"].get("eventCount"),
                "attempt_count": len(attempts),
                "validation": final_outcome["validation"],
                "failure_reason": failure_reason,
            },
            raw_agent_trace=raw_trace,
            normalized_agent_trace=normalized_trace,
            blocked_reason=failure_reason,
        )

    def _resolve_bridge_dir(self) -> Path:
        configured = Path(self.settings.external_desktop_agent_bridge_dir)
        if configured.is_absolute():
            return configured
        project_root = Path(__file__).resolve().parents[4]
        return project_root / configured

    def _build_payload(
        self,
        text: str,
        note_path: Path,
        *,
        preopened_notepad: bool,
        retry_mode: bool,
    ) -> dict[str, object]:
        return {
            "instruction": self._build_instruction(
                text,
                note_path,
                preopened_notepad=preopened_notepad,
                retry_mode=retry_mode,
            ),
            "model": {
                "baseURL": self.settings.external_desktop_agent_base_url,
                "apiKey": self.settings.external_desktop_agent_api_key,
                "model": self.settings.external_desktop_agent_model,
            },
            "maxLoopCount": self.settings.external_desktop_agent_max_loops + (4 if retry_mode else 0),
            "loopIntervalInMs": self.settings.external_desktop_agent_loop_interval_ms,
            "maxDurationMs": (self.settings.external_desktop_agent_timeout_s + (60 if retry_mode else 0)) * 1000,
        }

    def _build_instruction(
        self,
        text: str,
        note_path: Path,
        *,
        preopened_notepad: bool,
        retry_mode: bool = False,
    ) -> str:
        prefix = (
            f'The Notepad window for "{note_path}" is already open. '
            if preopened_notepad
            else "Open Windows Notepad. "
        )
        retry_clause = (
            "This is a retry. If the editor is empty, focus it and complete the task now. "
            "Use Ctrl+A only if unexpected text is already present, then replace it with the requested text. "
            if retry_mode
            else ""
        )
        return (
            f"{prefix}"
            f"{retry_clause}"
            "Focus the Notepad editor only. Click inside the editor if needed. "
            "Type exactly the requested text once, press Ctrl+S to save, "
            "wait until the save completes, and stop immediately after saving. "
            "Do not open a browser, do not switch applications, and do not rewrite the text. "
            f'Requested text: """{text}"""'
        )

    def _run_bridge_attempt(
        self,
        *,
        bridge_dir: Path,
        bridge_script: Path,
        payload: dict[str, object],
        note_path: Path,
        expected_text: str,
        attempt_number: int,
    ) -> dict[str, Any]:
        try:
            completed = subprocess.run(
                ["node", str(bridge_script)],
                cwd=str(bridge_dir),
                input=json.dumps(payload, ensure_ascii=False),
                text=True,
                capture_output=True,
                timeout=max(1, int(payload.get("maxDurationMs", 120000)) // 1000 + 5),
                check=False,
            )
            stdout = completed.stdout.strip()
            stderr = completed.stderr.strip()
            bridge_exit_code = completed.returncode
            bridge_result = self._parse_bridge_stdout(stdout)
            if bridge_result is None:
                bridge_result = {
                    "status": "failed",
                    "reason": "invalid_bridge_json",
                    "stdout": stdout,
                }
        except subprocess.TimeoutExpired as exc:
            stdout = (exc.stdout or "").strip() if isinstance(exc.stdout, str) else ""
            stderr = (exc.stderr or "").strip() if isinstance(exc.stderr, str) else ""
            bridge_exit_code = None
            bridge_result = {
                "status": "failed",
                "reason": "bridge_subprocess_timeout",
                "error": str(exc),
                "durationMs": int(self.settings.external_desktop_agent_timeout_s * 1000),
                "eventCount": 0,
            }
        except Exception as exc:
            stdout = ""
            stderr = ""
            bridge_exit_code = None
            bridge_result = {
                "status": "failed",
                "reason": "bridge_process_error",
                "error": f"{type(exc).__name__}: {exc}",
                "eventCount": 0,
            }

        observed_text = note_path.read_text(encoding="utf-8") if note_path.exists() else ""
        classification = self._classify_attempt(
            bridge_result=bridge_result,
            expected_text=expected_text,
            observed_text=observed_text,
        )
        return {
            "attempt_number": attempt_number,
            "payload": payload,
            "stdout": stdout,
            "stderr": stderr,
            "bridge_exit_code": bridge_exit_code,
            "bridge_result": bridge_result,
            "observed_text": observed_text,
            **classification,
        }

    def _classify_attempt(
        self,
        *,
        bridge_result: dict[str, object],
        expected_text: str,
        observed_text: str,
    ) -> dict[str, Any]:
        duration_ms = bridge_result.get("durationMs")
        bridge_status = str(bridge_result.get("status") or "failed").lower()
        bridge_reason = str(bridge_result.get("reason") or "").strip().lower()
        bridge_error = str(bridge_result.get("error") or "").strip().lower()
        normalized_expected = self._normalize_text_for_verification(expected_text)
        normalized_observed = self._normalize_text_for_verification(observed_text)
        exact_match = normalized_observed == normalized_expected
        contains_expected = bool(normalized_expected and normalized_expected in normalized_observed)
        observed_non_empty = bool(observed_text.strip())

        validation = {
            "expected_length": len(expected_text),
            "observed_length": len(observed_text),
            "normalized_expected_length": len(normalized_expected),
            "normalized_observed_length": len(normalized_observed),
            "exact_match": exact_match,
            "contains_expected_text": contains_expected,
            "observed_non_empty": observed_non_empty,
            "duration_ms": duration_ms,
        }

        if bridge_status == "success" and exact_match:
            return {
                "result_status": "success",
                "failure_reason": None,
                "duration_ms": duration_ms,
                "validation": validation,
            }

        if bridge_reason in {"bridge_subprocess_timeout", "timeout"} or "timed out" in bridge_error:
            failure_reason = "external_desktop_agent_timeout"
        elif bridge_reason == "invalid_bridge_json":
            failure_reason = "external_desktop_agent_invalid_bridge_json"
        elif bridge_reason == "bridge_process_error":
            failure_reason = "external_desktop_agent_bridge_process_error"
        elif bridge_reason:
            failure_reason = f"external_desktop_agent_bridge_failed:{bridge_reason}"
        elif bridge_error:
            failure_reason = "external_desktop_agent_bridge_error"
        elif contains_expected and not exact_match:
            failure_reason = "external_desktop_agent_partial_text_saved"
        elif observed_non_empty:
            failure_reason = "external_desktop_agent_verification_failed"
        else:
            failure_reason = "external_desktop_agent_no_output"

        if bridge_status == "success" and contains_expected and not exact_match:
            failure_reason = "external_desktop_agent_partial_text_saved"
        elif bridge_status == "success" and not observed_non_empty:
            failure_reason = "external_desktop_agent_empty_file_after_success"

        return {
            "result_status": "failed",
            "failure_reason": failure_reason,
            "duration_ms": duration_ms,
            "validation": validation,
        }

    def _normalize_text_for_verification(self, value: str) -> str:
        return value.replace("\r\n", "\n").replace("\r", "\n").strip()

    def _should_retry_attempt(self, attempt: dict[str, object]) -> bool:
        failure_reason = str(attempt.get("failure_reason") or "")
        validation = attempt.get("validation")
        observed_non_empty = False
        if isinstance(validation, dict):
            observed_non_empty = bool(validation.get("observed_non_empty"))
        return failure_reason in {
            "external_desktop_agent_timeout",
            "external_desktop_agent_no_output",
            "external_desktop_agent_empty_file_after_success",
            "external_desktop_agent_bridge_failed:agent_incomplete",
        } and not observed_non_empty

    def _safe_payload(self, value: object) -> object:
        if value is None or isinstance(value, (str, int, float, bool)):
            return value
        if isinstance(value, dict):
            return {str(key): self._safe_payload(item) for key, item in value.items()}
        if isinstance(value, list):
            return [self._safe_payload(item) for item in value]
        return str(value)

    def _parse_bridge_stdout(self, stdout: str) -> dict[str, object] | None:
        if not stdout:
            return {}
        candidates = [line.strip() for line in stdout.splitlines() if line.strip()]
        for candidate in reversed(candidates):
            if not candidate.startswith("{"):
                continue
            try:
                parsed = json.loads(candidate)
            except json.JSONDecodeError:
                continue
            if isinstance(parsed, dict):
                return parsed
        try:
            parsed = json.loads(stdout)
        except json.JSONDecodeError:
            return None
        return parsed if isinstance(parsed, dict) else None
