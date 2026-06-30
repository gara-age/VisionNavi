import asyncio
import re
from dataclasses import asdict, dataclass
from typing import Any

from app.automation.browser.executor import BrowserExecutor
from app.automation.browser.external_agent_adapter import ExternalBrowserAgentAdapter
from app.automation.desktop.executor import DesktopExecutor
from app.automation.desktop.external_agent_adapter import ExternalDesktopAgentAdapter
from app.core.settings import Settings
from app.models.action_step import ActionStep
from app.models.agent_adapter import AgentAdapterRequest
from app.models.canonical_command import CanonicalCommand
from app.models.execution_backend import ExecutionBackend
from app.models.model_api import ActionPlanRequest, NextActionRequest
from app.services.model_client import RemoteModelClient
from app.services.session_store import SessionStore


@dataclass
class AgentStep:
    phase: str
    detail: str


@dataclass(frozen=True)
class BackendResolution:
    effective_backend: ExecutionBackend
    requested_backend: ExecutionBackend | None
    routing_reason: str | None = None
    unsupported_requested_backend: ExecutionBackend | None = None


class AgentLoop:
    def __init__(self) -> None:
        self.settings = Settings.from_env()
        self.browser_executor = BrowserExecutor()
        self.desktop_executor = DesktopExecutor()
        self.model_client = RemoteModelClient()
        self.external_browser_agent = ExternalBrowserAgentAdapter(
            self.browser_executor,
            self.model_client,
        )
        self.external_desktop_agent = ExternalDesktopAgentAdapter(
            self.desktop_executor,
            self.model_client,
        )

    def plan(self, command: CanonicalCommand) -> dict[str, object]:
        if command.task_domain == "desktop" and command.intent in {"open_notepad_and_type", "inspect_workspace_files"}:
            steps = [
                AgentStep(phase="observe", detail="Inspect desktop state and safe workspace context"),
                AgentStep(phase="plan", detail="Ask the LLM to generate desktop action steps for this task"),
                AgentStep(phase="act", detail="Execute planned desktop actions one step at a time"),
                AgentStep(phase="verify", detail="Verify desktop side effects and execution artifacts"),
                AgentStep(phase="recover", detail="Fallback to deterministic execution only if planning fails"),
            ]
        elif command.task_domain == "web" and command.intent == "search_and_read":
            steps = [
                AgentStep(phase="observe", detail="Inspect browser task context and search query"),
                AgentStep(phase="plan", detail="Ask the LLM to generate browser action steps for this reading task"),
                AgentStep(phase="act", detail="Execute planned browser actions one step at a time"),
                AgentStep(phase="verify", detail="Verify the search page and extracted result summary"),
                AgentStep(phase="recover", detail="Fallback to deterministic browser execution only if planning fails"),
            ]
        elif command.task_domain == "web" and command.intent == "find_map_route":
            map_site = command.target_app or "map"
            steps = [
                AgentStep(phase="observe", detail="Inspect map routing request and extract origin and destination"),
                AgentStep(phase="plan", detail=f"Use the deterministic {map_site} routing plan when that site is supported"),
                AgentStep(phase="act", detail="Open the requested map directions UI and enter the route request"),
                AgentStep(phase="verify", detail="Verify the directions page stays open with the requested route context"),
                AgentStep(phase="recover", detail="Retry only on supported map providers and deterministic route flows"),
            ]
        else:
            steps = [
                AgentStep(phase="observe", detail=f"Inspect current {command.task_domain} state"),
                AgentStep(phase="decide", detail=f"Select executor for intent '{command.intent}'"),
                AgentStep(phase="act", detail="Execute the selected automation path"),
                AgentStep(phase="verify", detail="Verify outcome via deterministic checks"),
                AgentStep(phase="recover", detail="Fallback path is reserved for future failures"),
            ]

        return {
            "status": "planned",
            "steps": [asdict(step) for step in steps],
        }

    async def run(
        self,
        session_id: str,
        command: CanonicalCommand,
        session_store: SessionStore,
        *,
        requested_backend: ExecutionBackend | None = None,
    ) -> None:
        plan = self.plan(command)
        steps: list[dict[str, str]] = plan["steps"]
        execution_result: dict[str, object] | None = None
        observation: dict[str, object] | None = None
        planned_actions: list[ActionStep] = []
        planning_notes: list[str] = []
        planning_trace: dict[str, object] = {}

        session_store.mark_running(session_id)
        session_store.append_event(
            session_id,
            event_type="session.started",
            phase="observe",
            detail=f"Starting '{command.normalized_text}'",
        )

        for step in steps:
            if session_store.is_canceled(session_id):
                session_store.append_event(
                    session_id,
                    event_type="session.canceled",
                    phase="canceled",
                    detail="Execution canceled before the next step",
                )
                return

            session_store.update_phase(session_id, step["phase"])
            session_store.append_event(
                session_id,
                event_type="session.phase",
                phase=step["phase"],
                detail=step["detail"],
            )

            if step["phase"] == "observe" and command.task_domain in {"desktop", "web"}:
                observation = await asyncio.to_thread(self._observe_command, command)
                session_store.append_event(
                    session_id,
                    event_type="session.observation",
                    phase="observe",
                    detail=self._summarize_observation(command, observation),
                    payload=observation,
                )
            elif step["phase"] == "plan" and command.task_domain in {"desktop", "web"}:
                planned_actions, planning_notes, planning_trace = await asyncio.to_thread(
                    self._plan_actions,
                    command,
                    observation or {},
                )
                session_store.merge_metadata(session_id, {"planner_trace": planning_trace})
                if planned_actions:
                    session_store.append_event(
                        session_id,
                        event_type="session.plan",
                        phase="plan",
                        detail=self._summarize_action_plan(planned_actions, planning_notes),
                        payload=planning_trace,
                    )
            elif step["phase"] == "act":
                execution_result = await asyncio.to_thread(
                    self._execute_command,
                    command,
                    planned_actions,
                    requested_backend,
                )
                session_store.merge_metadata(
                    session_id,
                    {
                        "requested_execution_backend": execution_result.get("requested_backend")
                        or requested_backend,
                        "effective_execution_backend": execution_result.get("execution_backend"),
                        "fallback_execution_backend": execution_result.get("fallback_backend"),
                        "backend_resolution_reason": execution_result.get("backend_resolution_reason"),
                        "unsupported_requested_backend": execution_result.get("unsupported_requested_backend"),
                    },
                )
                session_store.append_event(
                    session_id,
                    event_type="session.execution",
                    phase="act",
                    detail=f"Execution status: {execution_result.get('status', 'unknown')}",
                    payload=execution_result,
                )
            await asyncio.sleep(0.35)

        result = execution_result or {"status": "skipped"}
        final_snapshot = session_store.get(session_id)
        debug_trace = {
            "canonicalization": final_snapshot.metadata.get("canonicalization_trace", {}),
            "planning": final_snapshot.metadata.get("planner_trace", planning_trace),
            "session_metadata": final_snapshot.metadata,
        }
        if observation is not None:
            debug_trace["observation"] = observation
        result.setdefault("debug_trace", debug_trace)
        if result.get("status") == "failed":
            session_store.fail(session_id, result=result)
            session_store.append_event(
                session_id,
                event_type="session.failed",
                phase="complete",
                detail="Execution finished with a failure result",
            )
        else:
            session_store.complete(session_id, result=result)
            session_store.append_event(
                session_id,
                event_type="session.completed",
                phase="complete",
                detail="Execution plan completed",
            )

    def _execute_command(
        self,
        command: CanonicalCommand,
        planned_actions: list[ActionStep] | None = None,
        requested_backend: ExecutionBackend | None = None,
    ) -> dict[str, object]:
        resolution = self._resolve_execution_backend(command, requested_backend)
        execution_backend = resolution.effective_backend
        policy_flags = {
            "fallback_to_internal": self.settings.external_agent_fallback_to_internal,
        }

        if execution_backend == "external_browser_agent":
            observation = self.browser_executor.observe(command)
            adapter_result = self.external_browser_agent.execute(
                AgentAdapterRequest(
                    command=command,
                    observation=observation,
                    policy_flags=policy_flags,
                )
            )
            result = adapter_result.result or {
                "status": "failed",
                "reason": adapter_result.blocked_reason or "external_browser_agent_failed",
            }
            result["requested_backend"] = resolution.requested_backend
            result["backend_resolution_reason"] = resolution.routing_reason
            result["unsupported_requested_backend"] = resolution.unsupported_requested_backend
            result["execution_backend"] = adapter_result.execution_backend
            result["raw_agent_trace"] = adapter_result.raw_agent_trace
            result["normalized_agent_trace"] = adapter_result.normalized_agent_trace
            if result.get("status") == "success" or not self.settings.external_agent_fallback_to_internal:
                return self._finalize_execution_result(
                    command,
                    result,
                    blocked_reason=adapter_result.blocked_reason,
                )
            internal_result = self._execute_internal_browser(command, planned_actions)
            internal_result["execution_backend"] = adapter_result.execution_backend
            internal_result["fallback_backend"] = "internal_browser"
            internal_result["raw_agent_trace"] = adapter_result.raw_agent_trace
            internal_result["normalized_agent_trace"] = adapter_result.normalized_agent_trace
            internal_result["external_backend_result"] = result
            internal_result["requested_backend"] = resolution.requested_backend
            internal_result["backend_resolution_reason"] = resolution.routing_reason
            internal_result["unsupported_requested_backend"] = resolution.unsupported_requested_backend
            return self._finalize_execution_result(
                command,
                internal_result,
                blocked_reason=adapter_result.blocked_reason,
            )

        if execution_backend == "external_desktop_agent":
            observation = self.desktop_executor.observe(command)
            adapter_result = self.external_desktop_agent.execute(
                AgentAdapterRequest(
                    command=command,
                    observation=observation,
                    policy_flags=policy_flags,
                )
            )
            result = adapter_result.result or {
                "status": "failed",
                "reason": adapter_result.blocked_reason or "external_desktop_agent_failed",
            }
            result["requested_backend"] = resolution.requested_backend
            result["backend_resolution_reason"] = resolution.routing_reason
            result["unsupported_requested_backend"] = resolution.unsupported_requested_backend
            result["execution_backend"] = adapter_result.execution_backend
            result["raw_agent_trace"] = adapter_result.raw_agent_trace
            result["normalized_agent_trace"] = adapter_result.normalized_agent_trace
            if result.get("status") == "success" or not self.settings.external_agent_fallback_to_internal:
                return self._finalize_execution_result(
                    command,
                    result,
                    blocked_reason=adapter_result.blocked_reason,
                )
            internal_result = self._execute_internal_desktop(command, planned_actions)
            internal_result["execution_backend"] = adapter_result.execution_backend
            internal_result["fallback_backend"] = "internal_desktop"
            internal_result["raw_agent_trace"] = adapter_result.raw_agent_trace
            internal_result["normalized_agent_trace"] = adapter_result.normalized_agent_trace
            internal_result["external_backend_result"] = result
            internal_result["requested_backend"] = resolution.requested_backend
            internal_result["backend_resolution_reason"] = resolution.routing_reason
            internal_result["unsupported_requested_backend"] = resolution.unsupported_requested_backend
            return self._finalize_execution_result(
                command,
                internal_result,
                blocked_reason=adapter_result.blocked_reason,
            )

        if execution_backend == "internal_browser":
            result = self._execute_internal_browser(command, planned_actions)
            result.setdefault("requested_backend", resolution.requested_backend)
            result.setdefault("backend_resolution_reason", resolution.routing_reason)
            result.setdefault("unsupported_requested_backend", resolution.unsupported_requested_backend)
            result.setdefault("execution_backend", execution_backend)
            result.setdefault("raw_agent_trace", {})
            result.setdefault("normalized_agent_trace", [])
            return self._finalize_execution_result(command, result)
        if execution_backend == "internal_desktop":
            result = self._execute_internal_desktop(command, planned_actions)
            result.setdefault("requested_backend", resolution.requested_backend)
            result.setdefault("backend_resolution_reason", resolution.routing_reason)
            result.setdefault("unsupported_requested_backend", resolution.unsupported_requested_backend)
            result.setdefault("execution_backend", execution_backend)
            result.setdefault("raw_agent_trace", {})
            result.setdefault("normalized_agent_trace", [])
            return self._finalize_execution_result(command, result)

        result = self._execute_internal_hybrid(command)
        result.setdefault("requested_backend", resolution.requested_backend)
        result.setdefault("backend_resolution_reason", resolution.routing_reason)
        result.setdefault("unsupported_requested_backend", resolution.unsupported_requested_backend)
        result.setdefault("execution_backend", execution_backend)
        result.setdefault("raw_agent_trace", {})
        result.setdefault("normalized_agent_trace", [])
        return self._finalize_execution_result(command, result)

    def _execute_internal_browser(
        self,
        command: CanonicalCommand,
        planned_actions: list[ActionStep] | None = None,
    ) -> dict[str, object]:
        if command.task_domain == "web":
            if command.intent in {"search_and_read", "find_map_route"} and self.settings.iterative_browser_loop_enabled:
                return self.browser_executor.execute_iterative_browser_task(
                    command,
                    self.model_client,
                    max_steps=self.settings.iterative_browser_max_steps,
                )
            if command.intent in {"search_and_read", "find_map_route"}:
                effective_actions = planned_actions
                planning_notes: list[str] = []
                if not effective_actions:
                    observation = self.browser_executor.observe(command)
                    effective_actions, planning_notes, _ = self._plan_actions(command, observation)
                if effective_actions:
                    result = self.browser_executor.execute_action_plan(command, effective_actions)
                    result.setdefault("planning_notes", planning_notes)
                    result.setdefault("planned_steps", [step.model_dump() for step in effective_actions])
                    if result.get("status") == "success":
                        return result
            return self.browser_executor.execute(command)
        return {"status": "failed", "reason": "unsupported_internal_browser_command"}

    def _execute_internal_desktop(
        self,
        command: CanonicalCommand,
        planned_actions: list[ActionStep] | None = None,
    ) -> dict[str, object]:
        if command.task_domain == "desktop":
            if command.intent in {"open_notepad_and_type", "inspect_workspace_files"}:
                effective_actions = planned_actions
                planning_notes: list[str] = []
                if not effective_actions:
                    observation = self.desktop_executor.observe(command)
                    effective_actions, planning_notes, _ = self._plan_actions(command, observation)
                if effective_actions:
                    result = self.desktop_executor.execute_action_plan(command, effective_actions)
                    result.setdefault("planning_notes", planning_notes)
                    result.setdefault("planned_steps", [step.model_dump() for step in effective_actions])
                    if result.get("status") == "success":
                        return result
            return self.desktop_executor.execute(command)
        return {"status": "failed", "reason": "unsupported_internal_desktop_command"}

    def _execute_internal_hybrid(self, command: CanonicalCommand) -> dict[str, object]:
        browser_result = self.browser_executor.execute(command)
        desktop_result = self.desktop_executor.execute(command)
        return {
            "status": "success"
            if browser_result.get("status") == "success" or desktop_result.get("status") == "success"
            else "failed",
            "channel": "hybrid",
            "browser": browser_result,
            "desktop": desktop_result,
        }

    def _finalize_execution_result(
        self,
        command: CanonicalCommand,
        result: dict[str, object],
        *,
        blocked_reason: str | None = None,
    ) -> dict[str, object]:
        sanitized = self._json_safe_value(result)
        if not isinstance(sanitized, dict):
            return {
                "status": "failed",
                "reason": "invalid_execution_result_shape",
                "execution_backend": "internal_browser",
            }

        failure_reason = self._extract_failure_reason(sanitized, blocked_reason)
        step_count = self._extract_step_count(sanitized)
        duration_ms = self._extract_duration_ms(sanitized)
        sanitized["blocked_reason"] = blocked_reason or sanitized.get("blocked_reason")
        sanitized["failure_reason"] = failure_reason
        sanitized["execution_summary"] = {
            "task_domain": command.task_domain,
            "intent": command.intent,
            "requested_backend": sanitized.get("requested_backend"),
            "backend": sanitized.get("execution_backend"),
            "fallback_backend": sanitized.get("fallback_backend"),
            "routing_reason": sanitized.get("backend_resolution_reason"),
            "unsupported_requested_backend": sanitized.get("unsupported_requested_backend"),
            "status": sanitized.get("status"),
            "success": str(sanitized.get("status")).lower() == "success",
            "failure_reason": failure_reason,
            "duration_ms": duration_ms,
            "duration_s": round(duration_ms / 1000, 3) if duration_ms is not None else None,
            "step_count": step_count,
        }
        return sanitized

    def _extract_failure_reason(
        self,
        result: dict[str, object],
        blocked_reason: str | None,
    ) -> str | None:
        for key in ("failure_reason", "reason", "blocked_reason"):
            value = result.get(key)
            if isinstance(value, str) and value.strip():
                return value
        external_result = result.get("external_backend_result")
        if isinstance(external_result, dict):
            external_failure = self._extract_failure_reason(external_result, blocked_reason)
            if external_failure:
                return external_failure
        return blocked_reason

    def _extract_step_count(self, result: dict[str, object]) -> int | None:
        explicit = result.get("step_count")
        if isinstance(explicit, int):
            return explicit
        for key in ("normalized_agent_trace", "runtime_trace", "executed_steps", "planned_steps"):
            raw = result.get(key)
            if isinstance(raw, list):
                return len(raw)
        performance_summary = result.get("performance_summary")
        if isinstance(performance_summary, dict):
            count = performance_summary.get("step_count")
            if isinstance(count, int):
                return count
        return None

    def _extract_duration_ms(self, result: dict[str, object]) -> float | None:
        explicit = result.get("duration_ms")
        if isinstance(explicit, (int, float)):
            return float(explicit)
        raw_trace = result.get("raw_agent_trace")
        if isinstance(raw_trace, dict):
            trace_duration = raw_trace.get("duration_ms")
            if isinstance(trace_duration, (int, float)):
                return float(trace_duration)
            bridge_result = raw_trace.get("bridge_result")
            if isinstance(bridge_result, dict):
                bridge_duration = bridge_result.get("durationMs")
                if isinstance(bridge_duration, (int, float)):
                    return float(bridge_duration)
        performance_summary = result.get("performance_summary")
        if isinstance(performance_summary, dict):
            totals = performance_summary.get("totals_s")
            if isinstance(totals, dict):
                runtime_s = totals.get("runtime_s")
                if isinstance(runtime_s, (int, float)):
                    return round(float(runtime_s) * 1000, 1)
        return None

    def _json_safe_value(self, value: Any) -> Any:
        if value is None or isinstance(value, (str, int, float, bool)):
            return value
        if isinstance(value, dict):
            return {
                str(key): self._json_safe_value(item)
                for key, item in value.items()
            }
        if isinstance(value, list):
            return [self._json_safe_value(item) for item in value]
        if hasattr(value, "model_dump"):
            try:
                return self._json_safe_value(value.model_dump())
            except Exception:
                return str(value)
        return str(value)

    def _resolve_execution_backend(
        self,
        command: CanonicalCommand,
        requested_backend: ExecutionBackend | None,
    ) -> BackendResolution:
        if requested_backend is not None:
            if requested_backend == "external_browser_agent" and command.intent != "search_and_read":
                return BackendResolution(
                    effective_backend="internal_browser",
                    requested_backend=requested_backend,
                    routing_reason=f"unsupported_external_intent:{command.intent}",
                    unsupported_requested_backend=requested_backend,
                )
            if requested_backend == "external_desktop_agent" and command.intent != "open_notepad_and_type":
                return BackendResolution(
                    effective_backend="internal_desktop",
                    requested_backend=requested_backend,
                    routing_reason=f"unsupported_external_intent:{command.intent}",
                    unsupported_requested_backend=requested_backend,
                )
            return BackendResolution(
                effective_backend=requested_backend,
                requested_backend=requested_backend,
            )

        if command.task_domain == "web":
            if command.intent == "search_and_read":
                return BackendResolution(
                    effective_backend=self.settings.default_browser_execution_backend,
                    requested_backend=None,
                    routing_reason="auto_default_browser_backend",
                )
            return BackendResolution(
                effective_backend="internal_browser",
                requested_backend=None,
                routing_reason=f"internal_only_intent:{command.intent}",
            )
        if command.task_domain == "desktop":
            if command.intent == "open_notepad_and_type":
                return BackendResolution(
                    effective_backend=self.settings.default_desktop_execution_backend,
                    requested_backend=None,
                    routing_reason="auto_default_desktop_backend",
                )
            return BackendResolution(
                effective_backend="internal_desktop",
                requested_backend=None,
                routing_reason=f"internal_only_intent:{command.intent}",
            )
        return BackendResolution(
            effective_backend="internal_browser",
            requested_backend=None,
            routing_reason=f"internal_only_domain:{command.task_domain}",
        )

    def _plan_actions(
        self,
        command: CanonicalCommand,
        observation: dict[str, object],
    ) -> tuple[list[ActionStep], list[str], dict[str, object]]:
        request = ActionPlanRequest(
            command=command,
            observation=observation,
            prior_steps=[],
            last_result=None,
        )
        trace: dict[str, object] = {
            "command": command.model_dump(),
            "observation": observation,
            "llm_debug": self.model_client.build_action_plan_debug_payload(request),
            "next_action_debug": self.model_client.build_next_action_debug_payload(
                NextActionRequest(
                    command=command,
                    observation=observation,
                    candidate_targets=[],
                    history=[],
                    last_result=None,
                )
            ),
        }

        if command.intent == "find_map_route":
            fallback_steps = self._fallback_action_plan(command)
            route_request = self.browser_executor._parse_map_route_request(command.normalized_text)  # noqa: SLF001
            trace["path"] = "structured_map_route"
            trace["route_request"] = route_request.model_dump()
            trace["normalized_steps"] = [step.model_dump() for step in fallback_steps]
            if not fallback_steps:
                trace["notes"] = [f"unsupported_map_site:{route_request.provider}"]
                return ([], [f"unsupported_map_site:{route_request.provider}"], trace)
            trace["notes"] = ["structured_map_route"]
            return (fallback_steps, ["structured_map_route"], trace)

        try:
            plan = self.model_client.plan_action_steps(request)
        except Exception as exc:
            plan = None
            notes = [f"action_planner_fallback:{type(exc).__name__}"]
            trace["llm_error"] = f"{type(exc).__name__}: {exc}"
        else:
            notes = []

        if plan is not None and plan.steps:
            normalized_steps, adjustments = self._normalize_action_plan(command, plan.steps)
            trace["llm_response"] = plan.model_dump()
            trace["adjustments"] = adjustments
            trace["normalized_steps"] = [step.model_dump() for step in normalized_steps]
            trace["path"] = "llm_action_plan"
            final_notes = [*notes, *plan.notes]
            trace["notes"] = final_notes
            return (normalized_steps, final_notes, trace)

        fallback_steps = self._fallback_action_plan(command)
        final_notes = [*notes, "deterministic_action_plan"]
        trace["path"] = "deterministic_fallback"
        trace["normalized_steps"] = [step.model_dump() for step in fallback_steps]
        trace["notes"] = final_notes
        return (fallback_steps, final_notes, trace)

    def _fallback_action_plan(self, command: CanonicalCommand) -> list[ActionStep]:
        if command.intent == "search_and_read":
            search_request = self.browser_executor._extract_search_request(command.normalized_text)  # noqa: SLF001
            steps = [
                ActionStep(action="search_web", target=search_request["target"], text=search_request["query"]),
                ActionStep(action="verify_page_loaded", target=search_request["target"]),
                ActionStep(action="extract_top_result", target=search_request["target"]),
            ]
            if self.browser_executor._should_open_linked_page_for_search(command.normalized_text):  # noqa: SLF001
                steps.extend(
                    [
                        ActionStep(action="click_search_result", target=search_request["target"]),
                        ActionStep(action="verify_page_loaded", target="linked_page"),
                        ActionStep(action="summarize_page", target="linked_page"),
                    ]
                )
                return steps
            steps.append(ActionStep(action="read_page_summary", target=search_request["target"]))
            return steps

        if command.intent == "find_map_route":
            route_request = self.browser_executor._parse_map_route_request(command.normalized_text)  # noqa: SLF001
            return self.browser_executor.build_map_route_steps(route_request)

        if command.intent == "inspect_workspace_files":
            return [
                ActionStep(action="open_explorer", target="workspace"),
                ActionStep(action="list_directory", target="workspace"),
            ]

        if command.intent == "open_notepad_and_type":
            text = self.desktop_executor._extract_notepad_text(command.raw_text)  # noqa: SLF001
            return [
                ActionStep(action="observe_windows", target="desktop", reasoning="Capture current desktop state"),
                ActionStep(action="open_app", target="notepad", path_hint="visionnavi-agent-note.txt"),
                ActionStep(action="focus_window", target="notepad"),
                ActionStep(action="type_text", target="notepad", text=text),
                ActionStep(action="save_file", target="notepad"),
                ActionStep(action="verify_file_contains_text", expected_text=text),
            ]

        if command.intent == "change_system_setting":
            return [ActionStep(action="set_dark_mode", target="windows_settings")]

        return []

    def _normalize_action_plan(
        self,
        command: CanonicalCommand,
        steps: list[ActionStep],
    ) -> tuple[list[ActionStep], list[str]]:
        normalized_steps = list(steps)
        adjustments: list[str] = []

        if command.intent == "search_and_read":
            search_request = self.browser_executor._extract_search_request(command.normalized_text)  # noqa: SLF001
            explicit_url = self._extract_explicit_url(command.normalized_text)
            summary_only = self._prefers_result_card_summary(command.normalized_text)
            explicit_navigation = self._has_explicit_navigation_request(command.normalized_text)

            normalized_steps = self._align_browser_targets(normalized_steps, search_request["target"])
            adjustments.append(f"align_browser_targets:{search_request['target']}")
            if explicit_url:
                normalized_steps = self._prefer_direct_url_navigation(normalized_steps, explicit_url)
                adjustments.append(f"prefer_direct_url_navigation:{explicit_url}")

            has_search = any(step.action in {"search_web", "open_browser_url"} for step in normalized_steps)
            has_verify = any(step.action == "verify_page_loaded" for step in normalized_steps)
            has_extract = any(step.action == "extract_top_result" for step in normalized_steps)
            has_click = any(step.action == "click_search_result" for step in normalized_steps)
            has_summary = any(
                step.action in {"read_page_summary", "read_linked_page", "summarize_page", "read_section"}
                for step in normalized_steps
            )

            if not has_search:
                normalized_steps.insert(
                    0,
                    ActionStep(
                        action="search_web",
                        target=search_request["target"],
                        text=search_request["query"],
                    ),
                )
                adjustments.append("insert_missing_search")
            if not has_verify:
                normalized_steps.append(ActionStep(action="verify_page_loaded", target=search_request["target"]))
                adjustments.append("insert_missing_verify")
            if not has_extract:
                normalized_steps.append(ActionStep(action="extract_top_result", target=search_request["target"]))
                adjustments.append("insert_missing_extract")
            if not has_click:
                normalized_steps.append(ActionStep(action="click_search_result", target=search_request["target"]))
                adjustments.append("insert_missing_click")
            if not has_summary:
                normalized_steps.append(ActionStep(action="summarize_page", target="linked_page"))
                adjustments.append("insert_missing_summary")

            if summary_only and not explicit_navigation:
                normalized_steps = self._prefer_result_card_summary_plan(normalized_steps, search_request["target"])
                adjustments.append("prefer_result_card_summary")

            if search_request["target"] == "youtube":
                normalized_steps = self._prefer_site_native_summary(normalized_steps)
                adjustments.append("prefer_youtube_native_summary")

        if command.intent == "find_map_route":
            normalized_steps = self._fallback_action_plan(command)
            adjustments.append("replace_with_deterministic_map_route")

        if command.intent == "open_notepad_and_type":
            text = self.desktop_executor._extract_notepad_text(command.raw_text)  # noqa: SLF001
            has_type = any(step.action == "type_text" for step in normalized_steps)
            has_save = any(step.action == "save_file" for step in normalized_steps)
            has_verify = any(step.action == "verify_file_contains_text" for step in normalized_steps)

            if not has_type:
                normalized_steps.append(ActionStep(action="type_text", target="notepad", text=text))
                adjustments.append("insert_missing_type_text")
            if not has_save:
                normalized_steps.append(ActionStep(action="save_file", target="notepad"))
                adjustments.append("insert_missing_save")
            if not has_verify:
                normalized_steps.append(ActionStep(action="verify_file_contains_text", expected_text=text))
                adjustments.append("insert_missing_verify_file_contains_text")

        if command.intent == "inspect_workspace_files":
            has_open = any(step.action == "open_explorer" for step in normalized_steps)
            has_list = any(step.action == "list_directory" for step in normalized_steps)
            if not has_open:
                normalized_steps.insert(0, ActionStep(action="open_explorer", target="workspace"))
                adjustments.append("insert_missing_open_explorer")
            if not has_list:
                normalized_steps.append(ActionStep(action="list_directory", target="workspace"))
                adjustments.append("insert_missing_list_directory")

        return normalized_steps, adjustments

    def _map_route_mode_selector(self, mode: str) -> str | None:
        selectors = {
            "transit": "button.btn_search_tab:nth-of-type(1)",
            "car": "button.btn_search_tab:nth-of-type(2)",
            "walk": "button.btn_search_tab:nth-of-type(3)",
            "bike": "button.btn_search_tab:nth-of-type(4)",
        }
        return selectors.get(mode)

    def _align_browser_targets(self, steps: list[ActionStep], target: str) -> list[ActionStep]:
        aligned: list[ActionStep] = []
        for step in steps:
            if step.action in {"search_web", "extract_top_result", "click_search_result", "verify_page_loaded"}:
                if step.action == "verify_page_loaded" and step.target == "linked_page":
                    aligned.append(step)
                else:
                    aligned.append(step.model_copy(update={"target": target}))
            else:
                aligned.append(step)
        return aligned

    def _prefer_direct_url_navigation(self, steps: list[ActionStep], url: str) -> list[ActionStep]:
        rewritten: list[ActionStep] = []
        inserted_open = False
        for step in steps:
            if step.action == "search_web":
                if not inserted_open:
                    rewritten.append(ActionStep(action="open_browser_url", target=url))
                    inserted_open = True
                continue
            rewritten.append(step)
        if not inserted_open:
            rewritten.insert(0, ActionStep(action="open_browser_url", target=url))
        return rewritten

    def _prefer_result_card_summary_plan(self, steps: list[ActionStep], target: str) -> list[ActionStep]:
        filtered = [
            step
            for step in steps
            if step.action not in {"click_search_result", "read_linked_page", "summarize_page"}
            and not (step.action == "verify_page_loaded" and step.target == "linked_page")
        ]
        if not any(step.action == "read_page_summary" for step in filtered):
            filtered.append(ActionStep(action="read_page_summary", target=target))
        return filtered

    def _prefer_site_native_summary(self, steps: list[ActionStep]) -> list[ActionStep]:
        if any(step.action == "read_page_summary" for step in steps):
            return steps
        rewritten: list[ActionStep] = []
        for step in steps:
            if step.action == "summarize_page" and step.target == "linked_page":
                rewritten.append(ActionStep(action="read_page_summary", target="youtube"))
                continue
            rewritten.append(step)
        return rewritten

    def _extract_explicit_url(self, text: str) -> str | None:
        match = re.search(r"https?://\S+|www\.\S+", text, flags=re.IGNORECASE)
        if not match:
            return None
        url = match.group(0).rstrip(").,")
        if url.lower().startswith("www."):
            return f"https://{url}"
        return url

    def _prefers_result_card_summary(self, text: str) -> bool:
        lowered = text.lower()
        summary_markers = ["summary", "summarize", "brief", "요약", "정리", "간단히"]
        return any(marker in lowered for marker in summary_markers)

    def _has_explicit_navigation_request(self, text: str) -> bool:
        lowered = text.lower()
        navigation_markers = ["open", "go to", "enter", "click", "들어가", "열어", "클릭", "자세히"]
        return any(marker in lowered for marker in navigation_markers)

    def _observe_command(self, command: CanonicalCommand) -> dict[str, object]:
        if command.task_domain == "web":
            return self.browser_executor.observe(command)
        if command.task_domain == "desktop":
            return self.desktop_executor.observe(command)
        return {"task_domain": command.task_domain, "intent": command.intent}

    def _summarize_observation(self, command: CanonicalCommand, observation: dict[str, object]) -> str:
        if command.task_domain == "web":
            query = observation.get("query")
            return f"Prepared browser observation for query '{query}'"
        notepad_windows = observation.get("notepad_windows", [])
        if isinstance(notepad_windows, list):
            return f"Observed {len(notepad_windows)} Notepad window(s) before planning"
        return "Captured current desktop observation"

    def _summarize_action_plan(self, actions: list[ActionStep], notes: list[str]) -> str:
        action_names = ", ".join(step.action for step in actions)
        if notes:
            return f"Planned actions: {action_names} ({', '.join(notes)})"
        return f"Planned actions: {action_names}"
