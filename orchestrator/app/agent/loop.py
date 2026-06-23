import asyncio
from dataclasses import asdict, dataclass

from app.automation.browser.executor import BrowserExecutor
from app.automation.desktop.executor import DesktopExecutor
from app.models.action_step import ActionStep
from app.models.canonical_command import CanonicalCommand
from app.models.model_api import ActionPlanRequest
from app.services.model_client import RemoteModelClient
from app.services.session_store import SessionStore


@dataclass
class AgentStep:
    phase: str
    detail: str


class AgentLoop:
    def __init__(self) -> None:
        self.browser_executor = BrowserExecutor()
        self.desktop_executor = DesktopExecutor()
        self.model_client = RemoteModelClient()

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

    async def run(self, session_id: str, command: CanonicalCommand, session_store: SessionStore) -> None:
        plan = self.plan(command)
        steps: list[dict[str, str]] = plan["steps"]
        execution_result: dict[str, object] | None = None
        observation: dict[str, object] | None = None
        planned_actions: list[ActionStep] = []
        planning_notes: list[str] = []

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
                )
            elif step["phase"] == "plan" and command.task_domain in {"desktop", "web"}:
                planned_actions, planning_notes = await asyncio.to_thread(
                    self._plan_actions,
                    command,
                    observation or {},
                )
                if planned_actions:
                    session_store.append_event(
                        session_id,
                        event_type="session.plan",
                        phase="plan",
                        detail=self._summarize_action_plan(planned_actions, planning_notes),
                    )
            elif step["phase"] == "act":
                execution_result = await asyncio.to_thread(self._execute_command, command, planned_actions)
                session_store.append_event(
                    session_id,
                    event_type="session.execution",
                    phase="act",
                    detail=f"Execution status: {execution_result.get('status', 'unknown')}",
                )
            await asyncio.sleep(0.35)

        result = execution_result or {"status": "skipped"}
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
    ) -> dict[str, object]:
        if command.task_domain == "web":
            if command.intent == "search_and_read":
                effective_actions = planned_actions
                planning_notes: list[str] = []
                if not effective_actions:
                    observation = self.browser_executor.observe(command)
                    effective_actions, planning_notes = self._plan_actions(command, observation)
                if effective_actions:
                    result = self.browser_executor.execute_action_plan(command, effective_actions)
                    result.setdefault("planning_notes", planning_notes)
                    result.setdefault("planned_steps", [step.model_dump() for step in effective_actions])
                    if result.get("status") == "success":
                        return result
            return self.browser_executor.execute(command)
        if command.task_domain == "desktop":
            if command.intent in {"open_notepad_and_type", "inspect_workspace_files"}:
                effective_actions = planned_actions
                planning_notes: list[str] = []
                if not effective_actions:
                    observation = self.desktop_executor.observe(command)
                    effective_actions, planning_notes = self._plan_actions(command, observation)
                if effective_actions:
                    result = self.desktop_executor.execute_action_plan(command, effective_actions)
                    result.setdefault("planning_notes", planning_notes)
                    result.setdefault("planned_steps", [step.model_dump() for step in effective_actions])
                    if result.get("status") == "success":
                        return result
            return self.desktop_executor.execute(command)

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

    def _plan_actions(
        self,
        command: CanonicalCommand,
        observation: dict[str, object],
    ) -> tuple[list[ActionStep], list[str]]:
        request = ActionPlanRequest(
            command=command,
            observation=observation,
            prior_steps=[],
            last_result=None,
        )

        try:
            plan = self.model_client.plan_action_steps(request)
        except Exception as exc:
            plan = None
            notes = [f"action_planner_fallback:{type(exc).__name__}"]
        else:
            notes = []

        if plan is not None and plan.steps:
            normalized_steps = self._normalize_action_plan(command, plan.steps)
            return (normalized_steps, [*notes, *plan.notes])

        return (self._fallback_action_plan(command), [*notes, "deterministic_action_plan"])

    def _fallback_action_plan(self, command: CanonicalCommand) -> list[ActionStep]:
        if command.intent == "search_and_read":
            query = self.browser_executor._extract_search_query(command.normalized_text)  # noqa: SLF001
            return [
                ActionStep(action="search_web", target="naver", text=query),
                ActionStep(action="verify_page_loaded", target="naver"),
                ActionStep(action="extract_top_result", target="naver"),
                ActionStep(action="click_search_result", target="naver"),
                ActionStep(action="verify_page_loaded", target="linked_page"),
                ActionStep(action="read_linked_page", target="linked_page"),
            ]

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

    def _normalize_action_plan(self, command: CanonicalCommand, steps: list[ActionStep]) -> list[ActionStep]:
        normalized_steps = list(steps)

        if command.intent == "search_and_read":
            query = self.browser_executor._extract_search_query(command.normalized_text)  # noqa: SLF001
            has_search = any(step.action in {"search_web", "open_browser_url"} for step in normalized_steps)
            has_verify = any(step.action == "verify_page_loaded" for step in normalized_steps)
            has_extract = any(step.action == "extract_top_result" for step in normalized_steps)
            has_click = any(step.action == "click_search_result" for step in normalized_steps)
            has_summary = any(step.action in {"read_page_summary", "read_linked_page"} for step in normalized_steps)

            if not has_search:
                normalized_steps.insert(0, ActionStep(action="search_web", target="naver", text=query))
            if not has_verify:
                normalized_steps.append(ActionStep(action="verify_page_loaded", target="naver"))
            if not has_extract:
                normalized_steps.append(ActionStep(action="extract_top_result", target="naver"))
            if not has_click:
                normalized_steps.append(ActionStep(action="click_search_result", target="naver"))
            if not has_summary:
                normalized_steps.append(ActionStep(action="read_linked_page", target="linked_page"))

        if command.intent == "open_notepad_and_type":
            text = self.desktop_executor._extract_notepad_text(command.raw_text)  # noqa: SLF001
            has_type = any(step.action == "type_text" for step in normalized_steps)
            has_save = any(step.action == "save_file" for step in normalized_steps)
            has_verify = any(step.action == "verify_file_contains_text" for step in normalized_steps)

            if not has_type:
                normalized_steps.append(ActionStep(action="type_text", target="notepad", text=text))
            if not has_save:
                normalized_steps.append(ActionStep(action="save_file", target="notepad"))
            if not has_verify:
                normalized_steps.append(ActionStep(action="verify_file_contains_text", expected_text=text))

        if command.intent == "inspect_workspace_files":
            has_open = any(step.action == "open_explorer" for step in normalized_steps)
            has_list = any(step.action == "list_directory" for step in normalized_steps)
            if not has_open:
                normalized_steps.insert(0, ActionStep(action="open_explorer", target="workspace"))
            if not has_list:
                normalized_steps.append(ActionStep(action="list_directory", target="workspace"))

        return normalized_steps

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
