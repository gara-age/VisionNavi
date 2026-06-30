from __future__ import annotations

import asyncio
import base64
import os
import queue
import re
import subprocess
import threading
import time
from pathlib import Path
from typing import Any
from urllib.error import URLError
from urllib.parse import quote_plus
from urllib.request import urlopen

from app.core.settings import Settings
from app.models.action_step import ActionStep
from app.models.canonical_command import CanonicalCommand
from app.models.map_route import MapRouteRequest
from app.models.model_api import NextActionRequest, NextActionResponse, RuntimeCandidate
from app.services.map_route_parser import parse_map_route_request


class BrowserExecutor:
    def __init__(self, settings: Settings | None = None) -> None:
        self.settings = settings or Settings.from_env()
        self._playwright_manager = None
        self._playwright = None
        self._browser = None
        self._browser_context = None
        self._page = None
        self._browser_mode = "launch"
        self._reused_browser = False
        self._browser_worker_thread: threading.Thread | None = None
        self._browser_worker_queue: queue.Queue[tuple[object, queue.Queue[dict[str, object]]]] | None = None

    def execute(self, command: CanonicalCommand) -> dict[str, object]:
        if command.intent == "search_and_read":
            return self._execute_search_and_read(command)
        if command.intent == "find_map_route":
            return self._execute_map_route(command)

        return {
            "status": "stubbed",
            "executor": "browser",
            "strategy": "playwright-first",
            "normalized_text": command.normalized_text,
        }

    def execute_iterative_search_and_read(
        self,
        command: CanonicalCommand,
        model_client,
        *,
        max_steps: int = 8,
    ) -> dict[str, object]:
        return self.execute_iterative_browser_task(command, model_client, max_steps=max_steps)

    def execute_iterative_browser_task(
        self,
        command: CanonicalCommand,
        model_client,
        *,
        max_steps: int = 8,
    ) -> dict[str, object]:
        return asyncio.run(self.execute_iterative_browser_task_async(command, model_client, max_steps=max_steps))

    def observe(self, command: CanonicalCommand) -> dict[str, object]:
        if command.intent == "find_map_route":
            route_request = self._parse_map_route_request(command.normalized_text)
            payload = {
                "task_domain": command.task_domain,
                "intent": command.intent,
                "site": route_request.provider,
                "origin": route_request.origin,
                "destination": route_request.destination,
                "mode": route_request.mode,
                "route_kind": route_request.route_kind,
            }
            page_snapshot = self._current_page_snapshot()
            if page_snapshot:
                payload.update(page_snapshot)
            return payload
        search_request = self._extract_search_request(command.normalized_text)
        payload = {
            "task_domain": command.task_domain,
            "intent": command.intent,
            "query": search_request["query"],
            "preferred_search_target": search_request["target"],
            "default_engine": search_request["target"],
        }
        page_snapshot = self._current_page_snapshot()
        if page_snapshot:
            payload.update(page_snapshot)
        return payload

    def execute_action_plan(
        self,
        command: CanonicalCommand,
        steps: list[ActionStep],
    ) -> dict[str, object]:
        return asyncio.run(self.execute_action_plan_async(command, steps))

    async def execute_action_plan_async(
        self,
        command: CanonicalCommand,
        steps: list[ActionStep],
    ) -> dict[str, object]:
        try:
            from playwright.async_api import Error as PlaywrightError
            from playwright.async_api import async_playwright
        except Exception:
            return {
                "status": "failed",
                "executor": "browser",
                "strategy": "llm-action-plan",
                "reason": "playwright_not_installed",
            }

        try:
            async with async_playwright() as playwright:
                return await self._run_action_plan_once(command, steps, playwright)
        except PlaywrightError as exc:
            if self._is_recoverable_browser_error(exc):
                try:
                    self._restart_debug_browser_runtime()
                    async with async_playwright() as playwright:
                        result = await self._run_action_plan_once(command, steps, playwright)
                        result["recovered_after_browser_restart"] = True
                        return result
                except PlaywrightError as retry_exc:
                    return {
                        "status": "failed",
                        "executor": "browser",
                        "strategy": "llm-action-plan",
                        "reason": f"playwright_error:{type(retry_exc).__name__}",
                        "detail": str(retry_exc),
                        "recovered_after_browser_restart": False,
                    }
            return {
                "status": "failed",
                "executor": "browser",
                "strategy": "llm-action-plan",
                "reason": f"playwright_error:{type(exc).__name__}",
                "detail": str(exc),
            }
        except Exception as exc:
            return {
                "status": "failed",
                "executor": "browser",
                "strategy": "llm-action-plan",
                "reason": f"browser_error:{type(exc).__name__}",
                "detail": str(exc),
            }

    async def execute_iterative_search_and_read_async(
        self,
        command: CanonicalCommand,
        model_client,
        *,
        max_steps: int = 8,
    ) -> dict[str, object]:
        return await self.execute_iterative_browser_task_async(command, model_client, max_steps=max_steps)

    async def execute_iterative_browser_task_async(
        self,
        command: CanonicalCommand,
        model_client,
        *,
        max_steps: int = 8,
    ) -> dict[str, object]:
        try:
            from playwright.async_api import Error as PlaywrightError
            from playwright.async_api import async_playwright
        except Exception:
            return {
                "status": "failed",
                "executor": "browser",
                "strategy": "iterative-next-action",
                "reason": "playwright_not_installed",
            }

        try:
            async with async_playwright() as playwright:
                page = await self._open_page(playwright)
                route_request = self._parse_map_route_request(command.normalized_text) if command.intent == "find_map_route" else None
                fallback_steps = self._iterative_fallback_steps(command, route_request=route_request)
                context: dict[str, object] = {
                    "page": page,
                    "command": command.normalized_text,
                    "intent": command.intent,
                    "browser_mode": self._browser_mode,
                    "executed_steps": [],
                    "runtime_trace": [],
                    "decision_trace": [],
                }
                if command.intent == "search_and_read":
                    search_request = self._extract_search_request(command.normalized_text)
                    context["query"] = search_request["query"]
                    context["preferred_search_target"] = search_request["target"]
                elif route_request is not None:
                    context["route_origin"] = route_request.origin
                    context["route_destination"] = route_request.destination
                    context["route_mode"] = route_request.mode
                    context["route_kind"] = route_request.route_kind
                    context["route_provider"] = route_request.provider
                last_result: dict[str, object] | None = None

                for index in range(1, max_steps + 1):
                    executed_count = len(context["executed_steps"])
                    step_started_at = time.perf_counter()
                    observation_started_at = time.perf_counter()
                    observation = await self._capture_runtime_observation_async(page, command)
                    observation_duration_ms = round((time.perf_counter() - observation_started_at) * 1000, 1)
                    progress_state = self._describe_runtime_progress(
                        executed_steps=context["executed_steps"],
                        last_result=last_result,
                    )
                    observation["progress_state"] = progress_state
                    if executed_count < len(fallback_steps):
                        observation["suggested_next_step"] = fallback_steps[
                            executed_count
                        ].model_dump()
                    consecutive_no_step_count = self._count_consecutive_no_step_fallbacks(
                        context["decision_trace"]
                    )
                    observation["consecutive_no_step_count"] = consecutive_no_step_count
                    skip_llm_reason = self._resolve_deterministic_streak_reason(
                        command=command,
                        fallback_steps=fallback_steps,
                        executed_count=executed_count,
                        last_result=last_result,
                        decision_trace=context["decision_trace"],
                    )
                    if skip_llm_reason is not None:
                        observation["deterministic_streak_reason"] = skip_llm_reason
                    vision_trigger_reason = self._resolve_vision_analysis_trigger(
                        command=command,
                        observation=observation,
                        executed_steps=context["executed_steps"],
                        last_result=last_result,
                        decision_trace=context["decision_trace"],
                    )
                    if vision_trigger_reason is not None:
                        observation["vision_trigger_reason"] = vision_trigger_reason
                        vision_started_at = time.perf_counter()
                        observation = await self._enrich_observation_with_vision_async(
                            page,
                            command,
                            observation,
                            model_client,
                        )
                        vision_duration_ms = round((time.perf_counter() - vision_started_at) * 1000, 1)
                    else:
                        vision_duration_ms = 0.0
                        observation["vision_skipped_reason"] = "vision_not_needed_for_this_turn"
                    context["runtime_observation"] = observation
                    candidates = [
                        RuntimeCandidate.model_validate(candidate)
                        for candidate in observation.get("candidate_targets", [])
                        if isinstance(candidate, dict)
                    ]
                    request = NextActionRequest(
                        command=command,
                        observation=observation,
                        candidate_targets=candidates,
                        history=list(context["runtime_trace"]),
                        last_result=last_result,
                    )
                    if skip_llm_reason is not None:
                        decision = None
                        llm_duration_ms = 0.0
                        if executed_count < len(fallback_steps):
                            chosen_step = fallback_steps[executed_count]
                            decision_source = "deterministic_streak"
                            fallback_reason = "deterministic_streak_active"
                        else:
                            chosen_step = None
                            decision_source = "deterministic_streak"
                            fallback_reason = "no_next_action_available"
                    else:
                        llm_started_at = time.perf_counter()
                        decision = await asyncio.to_thread(model_client.decide_next_action, request)
                        llm_duration_ms = round((time.perf_counter() - llm_started_at) * 1000, 1)
                        chosen_step, decision_source, fallback_reason = self._resolve_next_step_decision(
                            decision=decision,
                            fallback_steps=fallback_steps,
                            executed_count=executed_count,
                        )
                    decision_payload = decision.model_dump() if isinstance(decision, NextActionResponse) else None
                    pre_action_total_ms = round((time.perf_counter() - step_started_at) * 1000, 1)
                    decision_timings = {
                        "observation_ms": observation_duration_ms,
                        "vision_ms": vision_duration_ms,
                        "llm_ms": llm_duration_ms,
                        "pre_action_total_ms": pre_action_total_ms,
                    }
                    context["decision_trace"].append(
                        {
                            "index": index,
                            "decision_source": decision_source,
                            "fallback_reason": fallback_reason,
                            "consecutive_no_step_count": consecutive_no_step_count,
                            "timings_ms": decision_timings,
                            "timings_s": self._timings_seconds(decision_timings),
                            "observation": observation,
                            "decision": decision_payload,
                            "chosen_step": chosen_step.model_dump() if isinstance(chosen_step, ActionStep) else None,
                        }
                    )

                    if isinstance(decision, NextActionResponse) and decision.done and chosen_step is None:
                        result = self._build_browser_result_payload(
                            command,
                            context,
                            strategy="iterative-next-action",
                        )
                        result["completion_reason"] = decision.completion_reason
                        result["decision_source"] = "llm_done"
                        return result

                    if chosen_step is None:
                        return {
                            "status": "failed",
                            "executor": "browser",
                            "strategy": "iterative-next-action",
                            "reason": "no_next_action_available",
                            "runtime_trace": context["runtime_trace"],
                            "runtime_observation": observation,
                            "performance_summary": self._build_performance_summary(context["runtime_trace"]),
                        }

                    if decision_source in {"fallback", "deterministic_streak"}:
                        choice_reason = "deterministic_fallback_next_step"
                    else:
                        choice_reason = decision.choice_reason if isinstance(decision, NextActionResponse) else None

                    action_started_at = time.perf_counter()
                    step_result = await self.execute_action_step_async(chosen_step, context=context)
                    action_duration_ms = round((time.perf_counter() - action_started_at) * 1000, 1)
                    total_step_duration_ms = round((time.perf_counter() - step_started_at) * 1000, 1)
                    context["executed_steps"].append(
                        {
                            "index": index,
                            "action": chosen_step.action,
                            "target": chosen_step.target,
                            "status": step_result.get("status"),
                        }
                    )
                    context["runtime_trace"].append(
                        {
                            "index": index,
                            "action": chosen_step.action,
                            "target": chosen_step.target,
                            "selected_target": step_result.get("selector") or chosen_step.target,
                            "choice_reason": choice_reason,
                            "decision_source": decision_source,
                            "fallback_reason": fallback_reason,
                            "consecutive_no_step_count": consecutive_no_step_count,
                            "llm_decision": decision_payload,
                            "verification_result": step_result.get("verification_result"),
                            "candidate_count": len(observation.get("candidate_targets", [])),
                            "status": step_result.get("status"),
                            "timings_ms": {
                                **decision_timings,
                                "action_ms": action_duration_ms,
                                "total_step_ms": total_step_duration_ms,
                            },
                            "timings_s": self._timings_seconds(
                                {
                                    **decision_timings,
                                    "action_ms": action_duration_ms,
                                    "total_step_ms": total_step_duration_ms,
                                }
                            ),
                        }
                    )
                    last_result = step_result

                    if step_result.get("status") != "success":
                        return {
                            "status": "failed",
                            "executor": "browser",
                            "strategy": "iterative-next-action",
                            "failed_step": chosen_step.model_dump(),
                            "step_result": step_result,
                            "executed_steps": context["executed_steps"],
                            "runtime_trace": context["runtime_trace"],
                            "decision_trace": context["decision_trace"],
                            "runtime_observation": observation,
                            "performance_summary": self._build_performance_summary(context["runtime_trace"]),
                        }

                    if self._should_complete_iterative_browser_task(
                        command=command,
                        chosen_step=chosen_step,
                        step_result=step_result,
                        context=context,
                    ):
                        return self._build_browser_result_payload(
                            command,
                            context,
                            strategy="iterative-next-action",
                        )

                return {
                    "status": "failed",
                    "executor": "browser",
                    "strategy": "iterative-next-action",
                    "reason": "max_steps_exceeded",
                    "executed_steps": context["executed_steps"],
                    "runtime_trace": context["runtime_trace"],
                    "decision_trace": context["decision_trace"],
                    "runtime_observation": context.get("runtime_observation"),
                    "performance_summary": self._build_performance_summary(context["runtime_trace"]),
                }
        except PlaywrightError as exc:
            return {
                "status": "failed",
                "executor": "browser",
                "strategy": "iterative-next-action",
                "reason": f"playwright_error:{type(exc).__name__}",
                "detail": str(exc),
            }
        except Exception as exc:
            return {
                "status": "failed",
                "executor": "browser",
                "strategy": "iterative-next-action",
                "reason": f"browser_error:{type(exc).__name__}",
                "detail": str(exc),
            }

    async def _enrich_observation_with_vision_async(
        self,
        page: Any,
        command: CanonicalCommand,
        observation: dict[str, object],
        model_client,
    ) -> dict[str, object]:
        if command.intent != "find_map_route":
            return observation
        if not self.settings.ollama_vision_enabled:
            return observation

        try:
            screenshot_bytes = await page.screenshot(type="jpeg", quality=55, full_page=False)
            screenshot_base64 = base64.b64encode(screenshot_bytes).decode("utf-8")
        except Exception as exc:
            observation["vision_error"] = f"screenshot_capture_failed:{type(exc).__name__}"
            return observation

        compact_observation = {
            "page_title": observation.get("page_title"),
            "page_url": observation.get("page_url"),
            "page_summary": observation.get("page_summary"),
            "origin": observation.get("origin"),
            "destination": observation.get("destination"),
            "mode": observation.get("mode"),
            "route_kind": observation.get("route_kind"),
            "candidate_targets": observation.get("candidate_targets", [])[:12],
        }

        from app.models.model_api import VisionObservationRequest

        request = VisionObservationRequest(
            command=command,
            observation=compact_observation,
        )
        try:
            vision_response = await asyncio.to_thread(
                model_client.analyze_visual_observation,
                request,
                screenshot_base64,
            )
        except Exception as exc:
            observation["vision_error"] = f"vision_model_failed:{type(exc).__name__}"
            return observation

        if vision_response is not None:
            observation["vision_analysis"] = vision_response.model_dump()
        return observation

    def _resolve_vision_analysis_trigger(
        self,
        *,
        command: CanonicalCommand,
        observation: dict[str, object],
        executed_steps: list[dict[str, object]],
        last_result: dict[str, object] | None,
        decision_trace: list[dict[str, object]],
    ) -> str | None:
        if command.intent != "find_map_route":
            return None
        if not self.settings.ollama_vision_enabled:
            return None

        progress_state = str(observation.get("progress_state") or "").strip().lower()
        page_url = str(observation.get("page_url") or "").strip().lower()
        verification_result = ""
        if isinstance(last_result, dict):
            verification_result = str(last_result.get("verification_result") or "").strip().lower()

        if progress_state == "route_results_ready" or verification_result == "route_result_loaded":
            return None
        if not executed_steps:
            return None
        if verification_result == "route_result_not_loaded":
            return "verification_failed"

        if decision_trace:
            last_decision = decision_trace[-1]
            fallback_reason = str(last_decision.get("fallback_reason") or "").strip().lower()
            decision_source = str(last_decision.get("decision_source") or "").strip().lower()
            consecutive_no_step_count = int(observation.get("consecutive_no_step_count") or 0)
            if (
                decision_source == "fallback"
                and fallback_reason == "llm_returned_no_step"
                and consecutive_no_step_count >= 2
            ):
                return "llm_returned_no_step"
            if fallback_reason == "llm_requested_recovery":
                return "llm_requested_recovery"

        return None

    def _count_consecutive_no_step_fallbacks(self, decision_trace: list[dict[str, object]]) -> int:
        count = 0
        for item in reversed(decision_trace):
            fallback_reason = str(item.get("fallback_reason") or "").strip().lower()
            decision_source = str(item.get("decision_source") or "").strip().lower()
            if decision_source == "fallback" and fallback_reason == "llm_returned_no_step":
                count += 1
                continue
            break
        return count

    def _resolve_deterministic_streak_reason(
        self,
        *,
        command: CanonicalCommand,
        fallback_steps: list[ActionStep],
        executed_count: int,
        last_result: dict[str, object] | None,
        decision_trace: list[dict[str, object]],
    ) -> str | None:
        if command.intent != "find_map_route":
            return None
        if executed_count >= len(fallback_steps):
            return None
        next_step = fallback_steps[executed_count]
        if executed_count == 0 and next_step.action == "open_browser_url":
            return "initial_route_open"
        if not decision_trace:
            return None
        if isinstance(last_result, dict):
            verification_result = str(last_result.get("verification_result") or "").strip().lower()
            if verification_result in {"route_result_loaded", "route_result_not_loaded"}:
                return None

        if not self._supports_deterministic_streak_continuation(decision_trace):
            return None
        if next_step.target == "route_kind_filter" or next_step.action == "verify_page_loaded":
            return None
        if next_step.action not in {"wait_for_element", "fill_input", "submit_form", "click_element"}:
            return None
        return "linear_route_fallback_sequence"

    def _supports_deterministic_streak_continuation(self, decision_trace: list[dict[str, object]]) -> bool:
        if not decision_trace:
            return False
        last_decision = decision_trace[-1]
        decision_source = str(last_decision.get("decision_source") or "").strip().lower()
        fallback_reason = str(last_decision.get("fallback_reason") or "").strip().lower()
        if decision_source == "fallback" and fallback_reason == "llm_returned_no_step":
            return True
        if decision_source == "deterministic_streak" and fallback_reason == "deterministic_streak_active":
            return True
        return False

    def _iterative_fallback_steps(
        self,
        command: CanonicalCommand,
        *,
        route_request: MapRouteRequest | None = None,
    ) -> list[ActionStep]:
        if command.intent == "find_map_route":
            resolved_route_request = route_request or self._parse_map_route_request(command.normalized_text)
            return self.build_map_route_steps(resolved_route_request)
        return self._default_search_and_read_steps(command)

    def _should_complete_iterative_browser_task(
        self,
        *,
        command: CanonicalCommand,
        chosen_step: ActionStep,
        step_result: dict[str, object],
        context: dict[str, object],
    ) -> bool:
        if step_result.get("status") != "success":
            return False

        if command.intent == "search_and_read":
            return chosen_step.action in {"read_page_summary", "summarize_page", "read_linked_page", "read_section"}

        if command.intent == "find_map_route":
            requested_route_kind = str(context.get("route_kind") or "general").strip().lower()
            if requested_route_kind in {"", "general"}:
                return step_result.get("verification_result") == "route_result_loaded"
            if chosen_step.target == "route_kind_filter":
                return True
            return False

        return False

    async def _run_action_plan_once(
        self,
        command: CanonicalCommand,
        steps: list[ActionStep],
        playwright,
    ) -> dict[str, object]:
        page = await self._open_page(playwright)

        context: dict[str, object] = {
            "page": page,
            "command": command.normalized_text,
            "intent": command.intent,
            "query": self._extract_search_request(command.normalized_text)["query"],
            "preferred_search_target": self._extract_search_request(command.normalized_text)["target"],
            "browser_mode": self._browser_mode,
            "executed_steps": [],
            "runtime_trace": [],
        }
        if command.intent == "find_map_route":
            route_request = self._extract_map_route_request(command.normalized_text)
            context["route_origin"] = route_request["origin"]
            context["route_destination"] = route_request["destination"]
            context["route_mode"] = route_request["mode"]
            context["route_kind"] = route_request["route_kind"]
        context["runtime_observation"] = await self._capture_runtime_observation_async(page, command)

        for index, step in enumerate(steps, start=1):
            step_result = await self.execute_action_step_async(step, context=context)
            context["executed_steps"].append(
                {
                    "index": index,
                    "action": step.action,
                    "target": step.target,
                    "status": step_result.get("status"),
                }
            )
            context["runtime_trace"].append(
                {
                    "index": index,
                    "action": step.action,
                    "target": step.target,
                    "selected_target": step_result.get("selector") or step.target,
                    "choice_reason": step.reasoning or step_result.get("reasoning"),
                    "verification_result": step_result.get("verification_result"),
                    "candidate_count": len(context.get("runtime_observation", {}).get("candidate_targets", [])),
                    "status": step_result.get("status"),
                }
            )
            if step_result.get("status") != "success":
                return {
                    "status": "failed",
                    "executor": "browser",
                    "strategy": "llm-action-plan",
                    "failed_step": step.model_dump(),
                    "step_result": step_result,
                    "executed_steps": context["executed_steps"],
                    "runtime_trace": context["runtime_trace"],
                    "runtime_observation": context.get("runtime_observation"),
                    "performance_summary": self._build_performance_summary(context["runtime_trace"]),
                }
            context["runtime_observation"] = await self._capture_runtime_observation_async(page, command)

        result_card = context.get("top_result") if isinstance(context.get("top_result"), dict) else {}
        return {
            "status": "success",
            "executor": "browser",
            "strategy": "llm-action-plan",
            "intent": command.intent,
            "query": context.get("query"),
            "route_origin": context.get("route_origin"),
            "route_destination": context.get("route_destination"),
            "route_mode": context.get("route_mode"),
            "route_kind": context.get("route_kind"),
            "url": context.get("page_url"),
            "page_title": context.get("page_title"),
            "browser_mode": context.get("browser_mode"),
            "top_result_title": result_card.get("title") if isinstance(result_card, dict) else None,
            "top_result_snippet": result_card.get("snippet") if isinstance(result_card, dict) else None,
            "top_result_url": result_card.get("url") if isinstance(result_card, dict) else None,
            "page_summary": context.get("page_summary"),
            "linked_page_url": context.get("linked_page_url"),
            "section_text": context.get("section_text"),
            "executed_steps": context["executed_steps"],
            "runtime_trace": context["runtime_trace"],
            "decision_trace": context.get("decision_trace", []),
            "runtime_observation": context.get("runtime_observation"),
            "performance_summary": self._build_performance_summary(context["runtime_trace"]),
        }

    def _build_browser_result_payload(
        self,
        command: CanonicalCommand,
        context: dict[str, object],
        *,
        strategy: str,
    ) -> dict[str, object]:
        result_card = context.get("top_result") if isinstance(context.get("top_result"), dict) else {}
        return {
            "status": "success",
            "executor": "browser",
            "strategy": strategy,
            "intent": command.intent,
            "query": context.get("query"),
            "route_origin": context.get("route_origin"),
            "route_destination": context.get("route_destination"),
            "route_mode": context.get("route_mode"),
            "route_kind": context.get("route_kind"),
            "url": context.get("page_url"),
            "page_title": context.get("page_title"),
            "browser_mode": context.get("browser_mode"),
            "top_result_title": result_card.get("title") if isinstance(result_card, dict) else None,
            "top_result_snippet": result_card.get("snippet") if isinstance(result_card, dict) else None,
            "top_result_url": result_card.get("url") if isinstance(result_card, dict) else None,
            "page_summary": context.get("page_summary"),
            "linked_page_url": context.get("linked_page_url"),
            "section_text": context.get("section_text"),
            "executed_steps": context["executed_steps"],
            "runtime_trace": context["runtime_trace"],
            "decision_trace": context.get("decision_trace", []),
            "runtime_observation": context.get("runtime_observation"),
            "performance_summary": self._build_performance_summary(context["runtime_trace"]),
        }

    def _timings_seconds(self, timings_ms: dict[str, object]) -> dict[str, float]:
        converted: dict[str, float] = {}
        for key, value in timings_ms.items():
            if isinstance(value, (int, float)):
                converted[key.replace("_ms", "_s")] = round(float(value) / 1000, 3)
        return converted

    def _build_performance_summary(self, runtime_trace: list[dict[str, object]]) -> dict[str, object]:
        step_summaries: list[dict[str, object]] = []
        total_runtime_ms = 0.0
        total_observation_ms = 0.0
        total_vision_ms = 0.0
        total_llm_ms = 0.0
        total_action_ms = 0.0
        decision_source_counts: dict[str, int] = {}
        fallback_reason_counts: dict[str, int] = {}

        for item in runtime_trace:
            timings_ms = item.get("timings_ms")
            if not isinstance(timings_ms, dict):
                continue

            step_total_ms = float(timings_ms.get("total_step_ms") or 0.0)
            observation_ms = float(timings_ms.get("observation_ms") or 0.0)
            vision_ms = float(timings_ms.get("vision_ms") or 0.0)
            llm_ms = float(timings_ms.get("llm_ms") or 0.0)
            action_ms = float(timings_ms.get("action_ms") or 0.0)

            total_runtime_ms += step_total_ms
            total_observation_ms += observation_ms
            total_vision_ms += vision_ms
            total_llm_ms += llm_ms
            total_action_ms += action_ms
            decision_source = str(item.get("decision_source") or "").strip()
            fallback_reason = str(item.get("fallback_reason") or "").strip()
            if decision_source:
                decision_source_counts[decision_source] = decision_source_counts.get(decision_source, 0) + 1
            if fallback_reason:
                fallback_reason_counts[fallback_reason] = fallback_reason_counts.get(fallback_reason, 0) + 1

            step_summaries.append(
                {
                    "index": item.get("index"),
                    "action": item.get("action"),
                    "target": item.get("target"),
                    "status": item.get("status"),
                    "decision_source": item.get("decision_source"),
                    "fallback_reason": item.get("fallback_reason"),
                    "total_step_s": round(step_total_ms / 1000, 3),
                    "observation_s": round(observation_ms / 1000, 3),
                    "vision_s": round(vision_ms / 1000, 3),
                    "llm_s": round(llm_ms / 1000, 3),
                    "action_s": round(action_ms / 1000, 3),
                }
            )

        return {
            "step_count": len(step_summaries),
            "totals_s": {
                "runtime_s": round(total_runtime_ms / 1000, 3),
                "observation_s": round(total_observation_ms / 1000, 3),
                "vision_s": round(total_vision_ms / 1000, 3),
                "llm_s": round(total_llm_ms / 1000, 3),
                "action_s": round(total_action_ms / 1000, 3),
            },
            "decision_source_counts": decision_source_counts,
            "fallback_reason_counts": fallback_reason_counts,
            "llm_no_step_count": fallback_reason_counts.get("llm_returned_no_step", 0),
            "steps": step_summaries,
        }

    async def _open_page(self, playwright):  # noqa: ANN001
        browser, browser_mode, reused_browser = await self._connect_or_launch_browser_async(playwright)
        self._browser_mode = browser_mode
        self._reused_browser = reused_browser
        context = await self._ensure_browser_context_async(browser)
        page = await self._resolve_page_for_session_async(context, reused_browser)
        page.set_default_timeout(self.settings.browser_timeout_ms)
        return page

    async def execute_action_step_async(self, step: ActionStep, context: dict[str, object]) -> dict[str, object]:
        page = context.get("page")
        if page is None:
            return {"status": "failed", "reason": "missing_page_context"}

        if step.action == "open_browser_url":
            target_url = step.target or step.text or context.get("target_url")
            if not isinstance(target_url, str) or not target_url:
                return {"status": "failed", "reason": "missing_target_url"}
            await page.goto(target_url, wait_until="domcontentloaded")
            await page.wait_for_timeout(1200)
            context["page_url"] = page.url
            context["page_title"] = await page.title()
            return {"status": "success", "url": page.url}

        if step.action == "search_web":
            query = step.text or context.get("query")
            if not isinstance(query, str) or not query:
                return {"status": "failed", "reason": "missing_search_query"}
            search_target = self._normalize_search_target_safe(step.target or context.get("preferred_search_target"))
            target_url = self._build_search_url(search_target, query)
            await page.goto(target_url, wait_until="domcontentloaded")
            await page.wait_for_timeout(1500)
            context["query"] = query
            context["search_target"] = search_target
            context["target_url"] = target_url
            context["page_url"] = page.url
            context["page_title"] = await page.title()
            return {"status": "success", "query": query, "url": page.url, "target": search_target}

        if step.action == "click_element":
            route_kind_filter = step.metadata.get("route_kind_filter") if isinstance(step.metadata, dict) else None
            if isinstance(route_kind_filter, str) and route_kind_filter:
                selected_filter = await self._click_map_route_kind_filter_v2_async(page, route_kind_filter)
                context["page_url"] = page.url
                context["page_title"] = await page.title()
                filter_applied = await self._verify_route_kind_filter_applied_async(page, route_kind_filter)
                if not filter_applied:
                    return {
                        "status": "failed",
                        "reason": "route_kind_filter_not_applied",
                        "requested_route_kind": route_kind_filter,
                        "selector": selected_filter,
                        "url": page.url,
                        "page_title": await page.title(),
                    }
                context["route_kind_selected"] = route_kind_filter
                return {"status": "success", "selector": selected_filter, "url": page.url}
            selector = self._resolve_selector(step, context)
            if not selector:
                return {"status": "failed", "reason": "missing_selector"}
            locator = page.locator(selector).first
            if await locator.count() == 0:
                return {"status": "failed", "reason": "selector_not_found", "selector": selector}
            await locator.click(timeout=self.settings.browser_timeout_ms)
            await page.wait_for_timeout(800)
            context["page_url"] = page.url
            context["page_title"] = await page.title()
            if selector == "button.btn_direction.search":
                context["route_submitted"] = True
            if selector == "#transit":
                context["route_submitted"] = True
                await page.wait_for_timeout(2500)
            return {"status": "success", "selector": selector, "url": page.url}

        if step.action == "fill_input":
            selector = self._resolve_selector(step, context)
            if not selector:
                return {"status": "failed", "reason": "missing_selector"}
            text = step.text or step.expected_text
            if not text:
                return {"status": "failed", "reason": "missing_input_text"}
            locator = page.locator(selector).first
            if await locator.count() == 0:
                return {"status": "failed", "reason": "selector_not_found", "selector": selector}
            typing_mode = self._resolve_step_metadata_value(step, "typing_mode")
            if typing_mode == "sequential":
                await locator.click(timeout=self.settings.browser_timeout_ms)
                await locator.clear(timeout=self.settings.browser_timeout_ms)
                await locator.press_sequentially(text, delay=120)
            else:
                await locator.fill(text, timeout=self.settings.browser_timeout_ms)
            wait_after_input_ms = self._resolve_step_metadata_int(step, "wait_after_input_ms", default=0)
            if wait_after_input_ms > 0:
                await page.wait_for_timeout(wait_after_input_ms)
            for key in self._resolve_step_metadata_keys(step, "post_input_keys"):
                await locator.press(key, timeout=self.settings.browser_timeout_ms)
            wait_after_keys_ms = self._resolve_step_metadata_int(step, "wait_after_keys_ms", default=0)
            if wait_after_keys_ms > 0:
                await page.wait_for_timeout(wait_after_keys_ms)
            context["last_input_selector"] = selector
            context["last_input_text"] = text
            if "search_input_box_wrap.start" in selector:
                context["route_origin"] = text
            if "search_input_box_wrap.goal" in selector:
                context["route_destination"] = text
            if 'info.subway.searchBox.origin' in selector or 'routePoint-0' in selector:
                context["route_origin"] = text
            if 'info.subway.searchBox.dest' in selector or 'routePoint-1' in selector:
                context["route_destination"] = text
            return {"status": "success", "selector": selector}

        if step.action == "submit_form":
            selector = self._resolve_selector(step, context)
            if selector:
                locator = page.locator(selector).first
                if await locator.count() == 0:
                    return {"status": "failed", "reason": "selector_not_found", "selector": selector}
                await locator.press("Enter", timeout=self.settings.browser_timeout_ms)
            else:
                await page.keyboard.press("Enter")
            await page.wait_for_timeout(1200)
            suggestion_selected = False
            if isinstance(selector, str) and "search_input_box_wrap." in selector:
                suggestion_selected = await self._select_naver_map_first_suggestion_async(page, selector)
            context["page_url"] = page.url
            context["page_title"] = await page.title()
            return {"status": "success", "url": page.url, "suggestion_selected": suggestion_selected}

        if step.action == "scroll_page":
            amount = self._resolve_scroll_amount(step)
            await page.mouse.wheel(0, amount)
            await page.wait_for_timeout(500)
            context["scroll_offset"] = amount
            return {"status": "success", "scroll_offset": amount}

        if step.action == "wait_for_element":
            selector = self._resolve_selector(step, context)
            if not selector:
                return {"status": "failed", "reason": "missing_selector"}
            locator = page.locator(selector).first
            try:
                await locator.wait_for(state="visible", timeout=self.settings.browser_timeout_ms)
            except Exception as exc:
                return {
                    "status": "failed",
                    "reason": f"browser_error:{type(exc).__name__}",
                    "detail": str(exc),
                    "selector": selector,
                }
            return {"status": "success", "selector": selector}

        if step.action == "switch_tab":
            switched_page = await self._switch_tab_async(page, step)
            if switched_page is None:
                return {"status": "failed", "reason": "tab_not_found"}
            context["page"] = switched_page
            context["page_url"] = switched_page.url
            context["page_title"] = await switched_page.title()
            return {"status": "success", "url": switched_page.url}

        if step.action == "close_tab":
            try:
                await page.close()
            except Exception as exc:
                return {"status": "failed", "reason": f"browser_error:{type(exc).__name__}", "detail": str(exc)}
            remaining_page = await self._resolve_remaining_page_async(page)
            if remaining_page is not None:
                context["page"] = remaining_page
                context["page_url"] = remaining_page.url
                context["page_title"] = await remaining_page.title()
            return {"status": "success", "url": context.get("page_url")}

        if step.action == "extract_top_result":
            result_card = await self._extract_first_result_async(page)
            if not any(result_card.values()):
                return {"status": "failed", "reason": "top_result_not_found"}
            context["top_result"] = result_card
            return {"status": "success", "top_result": result_card}

        if step.action == "click_search_result":
            result_card = context.get("top_result")
            if not isinstance(result_card, dict):
                result_card = await self._extract_first_result_async(page)
                context["top_result"] = result_card
            result_url = result_card.get("url") if isinstance(result_card, dict) else None
            if not isinstance(result_url, str) or not result_url:
                return {"status": "failed", "reason": "missing_result_url"}
            if self._looks_like_download_url(result_url):
                context["linked_page_url"] = result_url
                context["download_only"] = True
                return {"status": "success", "url": result_url, "mode": "download_only"}
            await page.goto(result_url, wait_until="domcontentloaded")
            await page.wait_for_timeout(1500)
            context["linked_page_url"] = page.url
            context["page_url"] = page.url
            context["page_title"] = await page.title()
            return {"status": "success", "url": page.url}

        if step.action == "read_page_summary":
            result_card = context.get("top_result")
            if not isinstance(result_card, dict):
                result_card = await self._extract_first_result_async(page)
                context["top_result"] = result_card
            summary = None
            if isinstance(result_card, dict):
                summary = result_card.get("snippet") or result_card.get("title")
            if not isinstance(summary, str) or not summary.strip():
                return {"status": "failed", "reason": "page_summary_not_found"}
            context["page_summary"] = summary.strip()
            return {"status": "success", "page_summary": context["page_summary"]}

        if step.action == "summarize_page":
            summary = await self._extract_page_body_summary_async(page)
            if not summary:
                observation = context.get("runtime_observation")
                if isinstance(observation, dict):
                    observed_summary = observation.get("page_summary")
                    if isinstance(observed_summary, str) and observed_summary.strip():
                        summary = observed_summary.strip()
            if not summary:
                result_card = context.get("top_result")
                if isinstance(result_card, dict):
                    summary = result_card.get("snippet") or result_card.get("title")
            if not isinstance(summary, str) or not summary.strip():
                return {"status": "failed", "reason": "page_summary_not_found"}
            context["page_summary"] = summary.strip()
            context["page_url"] = page.url
            context["page_title"] = await page.title()
            return {"status": "success", "page_summary": context["page_summary"]}

        if step.action == "read_linked_page":
            if context.get("download_only") is True:
                result_card = context.get("top_result")
                if isinstance(result_card, dict):
                    summary = result_card.get("snippet") or result_card.get("title")
                    if isinstance(summary, str) and summary.strip():
                        context["page_summary"] = summary.strip()
                        return {"status": "success", "page_summary": context["page_summary"]}
            summary = await self._extract_page_body_summary_async(page)
            if not summary:
                observation = context.get("runtime_observation")
                if isinstance(observation, dict):
                    observed_summary = observation.get("page_summary")
                    if isinstance(observed_summary, str) and observed_summary.strip():
                        summary = observed_summary.strip()
            if not summary:
                return {"status": "failed", "reason": "linked_page_summary_not_found"}
            context["page_summary"] = summary
            context["page_title"] = await page.title()
            context["page_url"] = page.url
            return {"status": "success", "page_summary": summary}

        if step.action == "read_section":
            selector = self._resolve_selector(step, context)
            if not selector:
                return {"status": "failed", "reason": "missing_selector"}
            locator = page.locator(selector).first
            try:
                if await locator.count() == 0:
                    return {"status": "failed", "reason": "selector_not_found", "selector": selector}
                text = (await locator.inner_text(timeout=1500)).strip()
            except Exception as exc:
                return {"status": "failed", "reason": f"browser_error:{type(exc).__name__}", "detail": str(exc)}
            normalized = re.sub(r"\s+", " ", text)
            if not normalized:
                return {"status": "failed", "reason": "empty_section_text", "selector": selector}
            context["section_text"] = normalized[:800]
            context["page_summary"] = normalized[:400]
            return {"status": "success", "selector": selector, "section_text": context["section_text"]}

        if step.action == "verify_page_loaded":
            page_title = (await page.title()).strip()
            page_url = page.url
            context["page_title"] = page_title
            context["page_url"] = page_url
            if not page_title or not page_url:
                return {"status": "failed", "reason": "page_verification_failed"}
            if step.target == "naver_map_directions":
                route_verified, attempts = await self._verify_map_route_with_retry_async(
                    page,
                    context,
                    verifier=self._verify_naver_map_route_async,
                )
                if route_verified is not True:
                    return {
                        "status": "failed",
                        "reason": "route_result_not_loaded_after_retry",
                        "url": page_url,
                        "page_title": page_title,
                        "route_origin": context.get("route_origin"),
                        "route_destination": context.get("route_destination"),
                        "verify_attempts": attempts,
                        "verification_result": "route_result_not_loaded",
                    }
                return {
                    "status": "success",
                    "page_title": page_title,
                    "url": page_url,
                    "verify_attempts": attempts,
                    "verification_result": "route_result_loaded",
                }
            if step.target == "kakao_map_transit_directions":
                route_verified, attempts = await self._verify_map_route_with_retry_async(
                    page,
                    context,
                    verifier=self._verify_kakao_map_transit_route_v2_async,
                )
                if route_verified is not True:
                    return {
                        "status": "failed",
                        "reason": "route_result_not_loaded_after_retry",
                        "url": page_url,
                        "page_title": page_title,
                        "route_origin": context.get("route_origin"),
                        "route_destination": context.get("route_destination"),
                        "verify_attempts": attempts,
                        "verification_result": "route_result_not_loaded",
                    }
                return {
                    "status": "success",
                    "page_title": page_title,
                    "url": page_url,
                    "verify_attempts": attempts,
                    "verification_result": "route_result_loaded",
                }
            expected_text = step.expected_text
            if expected_text:
                body_text = await self._extract_page_body_summary_async(page)
                if not body_text or expected_text.lower() not in body_text.lower():
                    return {"status": "failed", "reason": "expected_text_not_found", "expected_text": expected_text}
            return {"status": "success", "page_title": page_title, "url": page_url, "verification_result": "page_loaded"}

        return {"status": "failed", "reason": "unsupported_action_step"}

    async def _verify_map_route_with_retry_async(
        self,
        page: Any,
        context: dict[str, object],
        *,
        verifier,
    ) -> tuple[bool, int]:
        attempts = 0
        retry_waits_ms = (0, 1200, 1800)
        for wait_ms in retry_waits_ms:
            if wait_ms > 0:
                await page.wait_for_timeout(wait_ms)
                await self._recover_map_route_before_retry_async(page, context)
            attempts += 1
            verified = await verifier(page, context)
            if verified is True:
                return True, attempts
        return False, attempts

    async def _recover_map_route_before_retry_async(self, page: Any, context: dict[str, object]) -> None:
        page_url = getattr(page, "url", "") or ""
        if "map.naver.com" not in page_url:
            return

        await self._select_naver_map_first_suggestion_async(
            page,
            ".search_input_box_wrap.start input.input_search",
        )
        await self._select_naver_map_first_suggestion_async(
            page,
            ".search_input_box_wrap.goal input.input_search",
        )

        search_button = page.locator("button.btn_direction.search").first
        try:
            if await search_button.count() > 0:
                await search_button.click(timeout=self.settings.browser_timeout_ms)
                await page.wait_for_timeout(900)
        except Exception:
            return

    async def _select_naver_map_first_suggestion_async(self, page: Any, selector: str) -> bool:
        if "search_input_box_wrap.start" in selector:
            candidate_selectors = [
                ".search_input_box_wrap.start .suggest_list_box li a",
                ".search_input_box_wrap.start .suggest_list_box li",
                ".search_input_box_wrap.start .search_list li a",
                ".search_input_box_wrap.start .search_list li",
            ]
        elif "search_input_box_wrap.goal" in selector:
            candidate_selectors = [
                ".search_input_box_wrap.goal .suggest_list_box li a",
                ".search_input_box_wrap.goal .suggest_list_box li",
                ".search_input_box_wrap.goal .search_list li a",
                ".search_input_box_wrap.goal .search_list li",
            ]
        else:
            return False

        for candidate_selector in candidate_selectors:
            locator = page.locator(candidate_selector).first
            try:
                if await locator.count() > 0:
                    await locator.click(timeout=self.settings.browser_timeout_ms)
                    await page.wait_for_timeout(700)
                    return True
            except Exception:
                continue
        return False

    def execute_action_step(self, step: ActionStep, context: dict[str, object]) -> dict[str, object]:
        return asyncio.run(self.execute_action_step_async(step, context))

    def _execute_search_and_read(self, command: CanonicalCommand) -> dict[str, object]:
        steps = self._default_search_and_read_steps(command)
        return self.execute_action_plan(command, steps)

    def _execute_map_route(self, command: CanonicalCommand) -> dict[str, object]:
        route_request = self._parse_map_route_request(command.normalized_text)
        if not self._supports_map_provider(route_request.provider):
            return {
                "status": "failed",
                "executor": "browser",
                "strategy": "structured-map-route",
                "reason": f"unsupported_map_site:{route_request.provider}",
                "route_origin": route_request.origin,
                "route_destination": route_request.destination,
                "route_mode": route_request.mode,
                "route_kind": route_request.route_kind,
            }
        steps = self.build_map_route_steps(route_request)
        result = self.execute_action_plan(command, steps)
        result.setdefault("route_origin", route_request.origin)
        result.setdefault("route_destination", route_request.destination)
        result.setdefault("route_mode", route_request.mode)
        result.setdefault("route_kind", route_request.route_kind)
        result.setdefault("route_provider", route_request.provider)
        return result

    def _build_search_url(self, target: str, query: str) -> str:
        normalized_target = self._normalize_search_target_safe(target)
        if normalized_target == "google":
            return f"https://www.google.com/search?q={quote_plus(query)}"
        if normalized_target == "youtube":
            return f"https://www.youtube.com/results?search_query={quote_plus(query)}"
        return f"https://search.naver.com/search.naver?query={quote_plus(query)}"

    def _supports_map_provider(self, provider: str) -> bool:
        return provider in {"naver_map", "kakao_map"}

    def build_map_route_steps(self, route_request: MapRouteRequest) -> list[ActionStep]:
        if route_request.provider == "naver_map":
            return self._build_naver_map_route_steps(route_request)
        if route_request.provider == "kakao_map":
            return self._build_kakao_map_route_steps(route_request)
        return []

    def _build_naver_map_route_steps(self, route_request: MapRouteRequest) -> list[ActionStep]:
        steps = [
            ActionStep(
                action="open_browser_url",
                target="https://map.naver.com/p/directions/-/-/-/transit?c=15.00,0,0,0,dh",
            ),
            ActionStep(
                action="wait_for_element",
                target=".search_input_box_wrap.start input.input_search",
                metadata={"selector": ".search_input_box_wrap.start input.input_search"},
            ),
            ActionStep(
                action="fill_input",
                target=".search_input_box_wrap.start input.input_search",
                text=route_request.origin,
                metadata={"selector": ".search_input_box_wrap.start input.input_search"},
            ),
            ActionStep(
                action="submit_form",
                target=".search_input_box_wrap.start input.input_search",
                metadata={"selector": ".search_input_box_wrap.start input.input_search"},
            ),
            ActionStep(
                action="fill_input",
                target=".search_input_box_wrap.goal input.input_search",
                text=route_request.destination,
                metadata={"selector": ".search_input_box_wrap.goal input.input_search"},
            ),
            ActionStep(
                action="submit_form",
                target=".search_input_box_wrap.goal input.input_search",
                metadata={"selector": ".search_input_box_wrap.goal input.input_search"},
            ),
        ]
        if route_request.mode != "transit":
            mode_selector = self._map_route_mode_selector(route_request.mode)
            if mode_selector is not None:
                steps.append(
                    ActionStep(
                        action="click_element",
                        target=mode_selector,
                        metadata={"selector": mode_selector},
                    )
                )
        steps.extend(
            [
                ActionStep(
                    action="click_element",
                    target="button.btn_direction.search",
                    metadata={"selector": "button.btn_direction.search"},
                ),
                ActionStep(
                    action="verify_page_loaded",
                    target=self._map_route_verification_target(route_request.provider),
                ),
            ]
        )
        route_kind_step = self._map_route_kind_filter_step(route_request.route_kind)
        if route_kind_step is not None:
            steps.append(route_kind_step)
        return steps

    def _map_route_verification_target(self, provider: str) -> str:
        if provider == "naver_map":
            return "naver_map_directions"
        if provider == "kakao_map":
            return "kakao_map_transit_directions"
        return "map_route_results"

    def _build_kakao_map_route_steps(self, route_request: MapRouteRequest) -> list[ActionStep]:
        target_url = "https://map.kakao.com/?target=car"
        steps = [
            ActionStep(action="open_browser_url", target=target_url),
            ActionStep(
                action="wait_for_element",
                target='input[name="routePoint-0"]',
                metadata={"selector": 'input[name="routePoint-0"]'},
            ),
            ActionStep(
                action="fill_input",
                target='input[name="routePoint-0"]',
                text=route_request.origin,
                metadata={
                    "selector": 'input[name="routePoint-0"]',
                    "typing_mode": "sequential",
                    "wait_after_input_ms": 1200,
                },
            ),
            ActionStep(
                action="click_element",
                target="div.WaypointBoxView.origin .suggest_list_target li a",
                metadata={"selector": "div.WaypointBoxView.origin .suggest_list_target li a"},
            ),
            ActionStep(
                action="fill_input",
                target='input[name="routePoint-1"]',
                text=route_request.destination,
                metadata={
                    "selector": 'input[name="routePoint-1"]',
                    "typing_mode": "sequential",
                    "wait_after_input_ms": 1200,
                },
            ),
            ActionStep(
                action="click_element",
                target="div.WaypointBoxView.dest .suggest_list_target li a",
                metadata={"selector": "div.WaypointBoxView.dest .suggest_list_target li a"},
            ),
            ActionStep(
                action="click_element",
                target="#transit",
                metadata={"selector": "#transit"},
            ),
        ]
        route_kind_step = self._map_route_kind_filter_step(route_request.route_kind)
        if route_kind_step is not None:
            steps.append(route_kind_step)
        steps.append(
            ActionStep(
                action="verify_page_loaded",
                target=self._map_route_verification_target(route_request.provider),
            )
        )
        return steps

    def _extract_search_query(self, text: str) -> str:
        return self._extract_search_request(text)["query"]

    def _extract_search_request(self, text: str) -> dict[str, str]:
        stripped = text.strip()
        lowered = stripped.lower()
        normalized_target = self._normalize_search_target_from_text_safe(lowered)

        patterns = [
            r"(?:search|find)\s+(?:on\s+)?(?:naver|google|youtube)\s+for\s+(.+?)(?:\s+and\s+read)?$",
            r"(?:search|find)\s+for\s+(.+?)(?:\s+on\s+(?:naver|google|youtube))?(?:\s+and\s+read)?$",
            r"(?:naver|google|youtube)\s+for\s+(.+?)(?:\s+and\s+read)?$",
            r"(.+?)\s+(?:검색해줘|검색해 줘|검색해|찾아줘|찾아 줘|찾아|읽어줘|읽어 줘)$",
        ]

        extracted = ""
        for pattern in patterns:
            match = re.search(pattern, stripped, flags=re.IGNORECASE)
            if match:
                extracted = match.group(1).strip(" .")
                break

        if not extracted:
            extracted = stripped

        extracted = self._strip_search_wrappers(extracted)
        if not extracted:
            extracted = stripped
        if extracted.isascii():
            extracted = extracted.lower()

        return {"target": normalized_target, "query": extracted}

    def _parse_map_route_request(self, text: str) -> MapRouteRequest:
        return parse_map_route_request(text)

    def _extract_map_route_request(self, text: str) -> dict[str, str]:
        route_request = self._parse_map_route_request(text)
        return {
            "site": route_request.provider,
            "origin": route_request.origin,
            "destination": route_request.destination,
            "mode": route_request.mode,
            "route_kind": route_request.route_kind,
        }

    def _extract_map_route_request_legacy(self, text: str) -> dict[str, str]:
        stripped = text.strip()
        lowered = stripped.lower()
        site = "naver_map"
        if "kakao map" in lowered or "kakaomap" in lowered or "카카오맵" in stripped or "카카오 지도" in stripped:
            site = "kakao_map"
        elif "naver map" in lowered or "네이버지도" in stripped or "네이버 지도" in stripped:
            site = "naver_map"
        mode = "transit"
        route_kind = "general"
        if any(token in lowered for token in ["car", "drive", "\uc790\ub3d9\ucc28"]):
            mode = "car"
        elif any(token in lowered for token in ["walk", "walking", "\ub3c4\ubcf4"]):
            mode = "walk"
        elif any(token in lowered for token in ["bike", "bicycle", "\uc790\uc804\uac70"]):
            mode = "bike"
        elif any(token in lowered for token in ["\uc9c0\ud558\ucca0", "subway", "metro"]):
            mode = "transit"
            route_kind = "subway"
        elif any(token in lowered for token in ["\ubc84\uc2a4", "bus"]):
            mode = "transit"
            route_kind = "bus"
        elif any(token in lowered for token in ["\uae30\ucc28", "train", "rail"]):
            mode = "transit"
            route_kind = "train"

        cleaned = re.sub(
            r"^(?:on\s+)?naver\s*map(?:s)?\s+",
            "",
            stripped,
            flags=re.IGNORECASE,
        ).strip()
        cleaned = re.sub(
            r"^(?:on\s+)?kakao\s*map(?:s)?\s+",
            "",
            cleaned,
            flags=re.IGNORECASE,
        ).strip()
        cleaned = re.sub(
            r"^(?:\ub124\uc774\ubc84\s*\uc9c0\ub3c4(?:\uc5d0\uc11c|\uc5d0)?|\uc9c0\ub3c4(?:\uc5d0\uc11c|\uc5d0)?)\s*",
            "",
            cleaned,
            flags=re.IGNORECASE,
        ).strip()
        cleaned = re.sub(
            r"^(?:\uce74\uce74\uc624\s*\ub9f5(?:\uc5d0\uc11c|\uc5d0)?|\uce74\uce74\uc624\s*\uc9c0\ub3c4(?:\uc5d0\uc11c|\uc5d0)?)\s*",
            "",
            cleaned,
            flags=re.IGNORECASE,
        ).strip()
        cleaned = re.sub(
            r"^(?:\ub124\uc774\ubc84|\uce74\uce74\uc624\ub9f5|\uce74\uce74\uc624|\uad6c\uae00)(?:\uc5d0\uc11c|\uc5d0)?\s*",
            "",
            cleaned,
            flags=re.IGNORECASE,
        ).strip()

        patterns = [
            r"(?P<origin>.+?)\s*(?:\uc5d0\uc11c|from)\s+(?P<destination>.+?)\s*(?:\uae4c\uc9c0|\uac00\ub294|\ub85c\s*\uac00\ub294|\uc73c\ub85c\s*\uac00\ub294)?\s*(?:\uacbd\ub85c|\uae38\ucc3e\uae30|directions|route).*$",
            r"(?:find|show|get)\s+(?:the\s+)?(?:route|directions)\s+from\s+(?P<origin>.+?)\s+to\s+(?P<destination>.+)$",
            r"(?P<origin>.+?)\s*->\s*(?P<destination>.+)$",
        ]
        for pattern in patterns:
            match = re.search(pattern, cleaned, flags=re.IGNORECASE)
            if match:
                origin = self._sanitize_route_endpoint(match.group("origin"), is_destination=False)
                destination = self._sanitize_route_endpoint(match.group("destination"), is_destination=True)
                if origin and destination:
                    return {
                        "site": site,
                        "origin": origin,
                        "destination": destination,
                        "mode": mode,
                        "route_kind": route_kind,
                    }

        return {
            "site": site,
            "origin": "",
            "destination": self._sanitize_route_endpoint(cleaned, is_destination=True),
            "mode": mode,
            "route_kind": route_kind,
        }

    def _sanitize_route_endpoint(self, value: str, *, is_destination: bool) -> str:
        normalized = re.sub(r"\s+", " ", value).strip(" .")
        normalized = re.sub(
            r"(?:\ucc3e\uc544\uc918|\ucc3e\uc544\uc8fc\uc138\uc694|\uc54c\ub824\uc918|\uc54c\ub824\uc8fc\uc138\uc694|\ubcf4\uc5ec\uc918|\ubcf4\uc5ec\uc8fc\uc138\uc694)$",
            "",
            normalized,
            flags=re.IGNORECASE,
        ).strip(" .")
        if is_destination:
            cleanup_patterns = [
                r"(?P<place>.+?)\s*(?:\uae4c\uc9c0)?\s*(?:\ub85c\s*)?\uac00\ub294\s*(?:\uc9c0\ud558\ucca0|subway|metro|\ub300\uc911\uad50\ud1b5|transit|\ubc84\uc2a4|bus|\uae30\ucc28|train|\uc790\ub3d9\ucc28|car|\ub3c4\ubcf4|walk|\uc790\uc804\uac70|bike)?\s*(?:\uacbd\ub85c|\uae38\ucc3e\uae30)?$",
                r"(?P<place>.+?)\s*(?:\uc9c0\ud558\ucca0|subway|metro|\ub300\uc911\uad50\ud1b5|transit|\ubc84\uc2a4|bus|\uae30\ucc28|train|\uc790\ub3d9\ucc28|car|\ub3c4\ubcf4|walk|\uc790\uc804\uac70|bike)\s*(?:\uacbd\ub85c|\uae38\ucc3e\uae30)?$",
                r"(?P<place>.+?)\s*(?:\uacbd\ub85c|\uae38\ucc3e\uae30)$",
            ]
            for pattern in cleanup_patterns:
                match = re.match(pattern, normalized, flags=re.IGNORECASE)
                if match:
                    place = match.groupdict().get("place")
                    if isinstance(place, str) and place.strip():
                        normalized = place.strip(" .")
                        break
        normalized = re.sub(r"(?:\uacbd\ub85c|\uae38\ucc3e\uae30)\s*$", "", normalized, flags=re.IGNORECASE).strip(" .")
        return normalized

    def _normalize_search_target(self, target: object) -> str:
        if not isinstance(target, str):
            return "naver"
        lowered = target.lower().strip()
        if lowered in {"google", "youtube", "naver"}:
            return lowered
        if "google" in lowered or "구글" in lowered:
            return "google"
        if "youtube" in lowered or "유튜브" in lowered:
            return "youtube"
        return "naver"

    def _normalize_search_target_from_text(self, lowered_text: str) -> str:
        if any(token in lowered_text for token in ["google", "구글"]):
            return "google"
        if any(token in lowered_text for token in ["naver", "네이버"]):
            return "naver"
        if any(token in lowered_text for token in ["youtube", "유튜브"]):
            return "youtube"
        return "naver"

    def _strip_search_wrappers(self, text: str) -> str:
        cleaned = text.strip()
        replacements = [
            (r"^(?:네이버|구글|유튜브)(?:에서|에)\s*", ""),
            (r"^(?:search|find)\s+(?:on\s+)?(?:naver|google|youtube)\s+(?:for\s+)?", ""),
            (r"^(?:search|find)\s+(?:for\s+)?", ""),
            (r"\s*(?:검색해줘|검색해 줘|검색해|찾아줘|찾아 줘|찾아|읽어줘|읽어 줘|요약해줘|요약해 줘|요약해)$", ""),
            (r"\s*(?:and summarize(?: the)? results page|summarize(?: the)? results page)$", ""),
            (r"\s*(?:and summarize briefly|summarize briefly)$", ""),
            (r"\s*(?:and read|and summarize|read the conditions|read details)$", ""),
            (r"\s+and$", ""),
            (r"\s*(?:에서|에)\s*$", ""),
        ]
        for pattern, replacement in replacements:
            cleaned = re.sub(pattern, replacement, cleaned, flags=re.IGNORECASE).strip(" .")
        return cleaned

    def _normalize_search_target_safe(self, target: object) -> str:
        if not isinstance(target, str):
            return "naver"
        lowered = target.lower().strip()
        if lowered in {"google", "youtube", "naver"}:
            return lowered
        if "google" in lowered or "\uad6c\uae00" in lowered:
            return "google"
        if "youtube" in lowered or "\uc720\ud29c\ube0c" in lowered:
            return "youtube"
        if "naver" in lowered or "\ub124\uc774\ubc84" in lowered:
            return "naver"
        return "naver"

    def _normalize_search_target_from_text_safe(self, lowered_text: str) -> str:
        if any(token in lowered_text for token in ["google", "\uad6c\uae00"]):
            return "google"
        if any(token in lowered_text for token in ["naver", "\ub124\uc774\ubc84"]):
            return "naver"
        if any(token in lowered_text for token in ["youtube", "\uc720\ud29c\ube0c"]):
            return "youtube"
        return "naver"

    async def _extract_first_result_async(self, page: Any) -> dict[str, str | None]:
        search_target = self._normalize_search_target(getattr(page, "url", ""))
        result_selectors = [
            ".total_group .bx",
            ".api_subject_bx",
            ".search_result .bx",
            "div.g",
            ".MjjYud",
            "ytd-video-renderer",
            "ytd-channel-renderer",
            "main .bx",
        ]

        for selector in result_selectors:
            cards = page.locator(selector)
            try:
                count = await cards.count()
            except Exception:
                continue

            for index in range(min(count, 5)):
                card = cards.nth(index)
                data = await self._extract_result_from_card_async(card)
                if data.get("title") or data.get("snippet"):
                    return data

        return {
            "title": await self._read_first_async(page, self._result_title_selectors(search_target)),
            "snippet": await self._read_first_async(page, self._result_snippet_selectors(search_target)),
            "url": await self._read_href_async(page, self._result_link_selectors(search_target)),
        }

    async def _extract_result_from_card_async(self, card: Any) -> dict[str, str | None]:
        title = await self._read_first_async(card, self._result_title_selectors("generic"))
        snippet = await self._read_first_async(card, self._result_snippet_selectors("generic"))
        url = await self._read_href_async(card, self._result_link_selectors("generic"))
        return {"title": title, "snippet": snippet, "url": url}

    def _result_title_selectors(self, search_target: str) -> list[str]:
        if search_target == "youtube":
            return ["#video-title", "yt-formatted-string#video-title", "a#video-title", "h3", "a"]
        if search_target == "google":
            return ["h3", "a h3", ".LC20lb", "a"]
        return ["a.title_link", "a.link_tit", ".total_tit", "h3", "a"]

    def _result_snippet_selectors(self, search_target: str) -> list[str]:
        if search_target == "youtube":
            return ["#description-text", "#metadata-line", "#channel-info", "yt-formatted-string", "p"]
        if search_target == "google":
            return [".VwiC3b", ".yXK7lf", ".MUxGbd", "span", "p"]
        return [".desc", ".total_dsc", ".api_txt_lines", ".news_dsc", ".dsc_txt_wrap", "p"]

    def _result_link_selectors(self, search_target: str) -> list[str]:
        if search_target == "youtube":
            return ["a#video-title", "#video-title", "a"]
        if search_target == "google":
            return ["a:has(h3)", "a"]
        return ["a.title_link", "a.link_tit", ".total_tit a", "a"]

    async def _extract_page_body_summary_async(self, page: Any) -> str | None:
        for selector in ["main", "article", "#content", ".content", "body"]:
            locator = page.locator(selector).first
            try:
                if await locator.count() > 0:
                    text = (await locator.inner_text(timeout=1500)).strip()
                    normalized = re.sub(r"\s+", " ", text)
                    if normalized:
                        return normalized[:400]
            except Exception:
                continue
        return None

    async def _extract_page_body_text_async(self, page: Any) -> str | None:
        locator = page.locator("body").first
        try:
            if await locator.count() == 0:
                return None
            text = (await locator.inner_text(timeout=2500)).strip()
            normalized = re.sub(r"\s+", " ", text)
            return normalized or None
        except Exception:
            return None

    async def _capture_runtime_observation_async(
        self,
        page: Any,
        command: CanonicalCommand,
    ) -> dict[str, object]:
        page_title = ""
        page_url = ""
        try:
            page_title = (await page.title()).strip()
        except Exception:
            page_title = ""
        try:
            page_url = page.url or ""
        except Exception:
            page_url = ""

        summary = await self._extract_page_body_summary_async(page)
        candidates = await self._extract_candidate_targets_async(page)

        payload: dict[str, object] = {
            "task_domain": command.task_domain,
            "intent": command.intent,
            "page_title": page_title,
            "page_url": page_url,
            "page_summary": summary,
            "candidate_targets": [candidate.model_dump() for candidate in candidates],
        }
        if command.intent == "search_and_read":
            search_request = self._extract_search_request(command.normalized_text)
            payload["query"] = search_request["query"]
            payload["preferred_search_target"] = search_request["target"]
        if command.intent == "find_map_route":
            route_request = self._extract_map_route_request(command.normalized_text)
            payload["site"] = route_request["site"]
            payload["origin"] = route_request["origin"]
            payload["destination"] = route_request["destination"]
            payload["mode"] = route_request["mode"]
            payload["route_kind"] = route_request["route_kind"]
        return payload

    async def _extract_candidate_targets_async(self, page: Any) -> list[RuntimeCandidate]:
        try:
            raw_candidates = await page.evaluate(
                """
() => {
  const toSelectorHint = (el) => {
    if (!el || !el.tagName) return null;
    const tag = el.tagName.toLowerCase();
    const id = el.id ? `#${el.id}` : '';
    const cls = Array.from(el.classList || []).slice(0, 2).map((name) => `.${name}`).join('');
    return `${tag}${id}${cls}` || tag;
  };
  const isVisible = (el) => {
    const style = window.getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    return style && style.visibility !== 'hidden' && style.display !== 'none' && rect.width > 0 && rect.height > 0;
  };
  const textPreview = (el) => (el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim().slice(0, 120);
  const label = (el) => el.getAttribute('aria-label') || el.getAttribute('placeholder') || textPreview(el) || el.getAttribute('title') || '';
  const roleOf = (el) => el.getAttribute('role') || el.tagName.toLowerCase();
  const candidates = [];
  const pushCandidate = (kind, el) => {
    if (!el || !isVisible(el)) return;
    candidates.push({
      kind,
      label: label(el),
      role: roleOf(el),
      selector_hint: toSelectorHint(el),
      text_preview: textPreview(el),
      metadata: {
        tag: el.tagName.toLowerCase(),
        type: el.getAttribute('type'),
      },
    });
  };

  document.querySelectorAll('input, textarea, [contenteditable="true"], [role="textbox"], [role="searchbox"], [role="combobox"]').forEach((el) => pushCandidate('input', el));
  document.querySelectorAll('button, a, [role="button"], [role="link"], [role="tab"]').forEach((el) => pushCandidate('clickable', el));
  document.querySelectorAll('main, article, .result, .results, .total_group, .api_subject_bx, div.g, .MjjYud').forEach((el) => pushCandidate('result_region', el));

  return candidates.slice(0, 24).map((item, index) => ({
    candidate_id: `cand_${index + 1}`,
    ...item,
  }));
}
"""
            )
        except Exception:
            return []

        candidates: list[RuntimeCandidate] = []
        for raw in raw_candidates or []:
            try:
                candidates.append(RuntimeCandidate.model_validate(raw))
            except Exception:
                continue
        return candidates

    def _current_page_snapshot(self) -> dict[str, object]:
        if not self._page_is_usable():
            return {}
        try:
            return {
                "page_url": getattr(self._page, "url", None),
            }
        except Exception:
            return {}

    async def _verify_naver_map_route_async(self, page: Any, context: dict[str, object]) -> bool:
        page_title = (await page.title()).strip().lower()
        page_url = page.url
        if "map.naver.com" not in page_url or "directions" not in page_url:
            return False
        if "%2F-%2F-%2F" in page_url or "/directions/-/-/-/" in page_url:
            return False
        if "\uae38\ucc3e\uae30" not in page_title and "directions" not in page_title:
            return False
        context["route_verified"] = True
        return True

    async def _verify_kakao_map_transit_route_async(self, page: Any, context: dict[str, object]) -> bool:
        page_url = page.url
        if "map.kakao.com" not in page_url:
            return False
        body_text = await self._extract_page_body_summary_async(page)
        if not body_text:
            return False
        origin = str(context.get("route_origin") or "").strip()
        destination = str(context.get("route_destination") or "").strip()
        required_markers = ["상세보기", "요금"]
        if not all(marker in body_text for marker in required_markers):
            return False
        if origin and origin not in body_text:
            return False
        destination_stem = re.sub(r"\s+1호선$", "", destination).strip()
        if destination and destination not in body_text and destination_stem not in body_text:
            return False
        context["route_verified"] = True
        context["page_summary"] = body_text[:400]
        return True

    async def _verify_kakao_map_transit_route_v2_async(self, page: Any, context: dict[str, object]) -> bool:
        page_url = page.url
        if "map.kakao.com" not in page_url:
            return False

        body_text = await self._extract_page_body_text_async(page)
        if not body_text:
            return False

        transit_tab = page.locator("#transit").first
        transit_selected = False
        try:
            if await transit_tab.count() > 0:
                transit_selected = (await transit_tab.get_attribute("aria-selected")) == "true"
        except Exception:
            transit_selected = False
        if not transit_selected:
            return False

        route_list_markers = ["상세보기", "요금", "버스+", "환승", "도보"]
        if not any(marker in body_text for marker in route_list_markers):
            return False

        route_count_visible = bool(re.search(r"전체\s+\d+", body_text))
        if not route_count_visible and "지하철 경로" not in body_text and "버스+" not in body_text:
            return False

        destination = str(context.get("route_destination") or "").strip()
        destination_stem = re.sub(r"\s+1호선$", "", destination).strip()
        if destination and destination not in body_text and destination_stem not in body_text:
            if not route_count_visible:
                return False

        context["route_verified"] = True
        context["page_summary"] = body_text[:400]
        return True

    async def _verify_route_kind_filter_applied_async(self, page: Any, route_kind: str) -> bool:
        page_url = page.url
        page_title = (await page.title()).strip()
        body_text = await self._extract_page_body_text_async(page)

        if "map.naver.com" in page_url:
            normalized_title = page_title.lower()
            if route_kind == "bus":
                return (
                    "bus-route" in page_url
                    or "\uBC84\uC2A4" in page_title
                    or "bus" in normalized_title
                    or self._body_has_route_kind_results(body_text, "\uBC84\uC2A4")
                )
            if route_kind == "subway":
                return (
                    "/subway" in page_url
                    or "\uC9C0\uD558\uCCA0" in page_title
                    or "subway" in normalized_title
                    or self._body_has_route_kind_results(body_text, "\uC9C0\uD558\uCCA0")
                )
            if route_kind == "train":
                return (
                    "/train" in page_url
                    or "\uAE30\uCC28" in page_title
                    or "train" in normalized_title
                    or self._body_has_route_kind_results(body_text, "\uAE30\uCC28")
                )
            return True

        if "map.kakao.com" in page_url:
            if not body_text:
                return False
            if route_kind == "subway":
                return "\uC9C0\uD558\uCCA0" in body_text
            if route_kind == "bus":
                return "\uBC84\uC2A4" in body_text
            if route_kind == "train":
                return "\uAE30\uCC28" in body_text
            return True

        return True

    def _body_has_route_kind_results(self, body_text: str | None, label: str) -> bool:
        if not body_text:
            return False
        normalized = re.sub(r"\s+", " ", body_text)
        count_match = re.search(rf"{re.escape(label)}\s+(\d+)", normalized)
        if count_match and int(count_match.group(1)) > 0:
            return True

        if label == "\uBC84\uC2A4":
            return any(marker in normalized for marker in ["\uBC84\uC2A4+", "\uD658\uC2B9", "\uC694\uAE08"])
        if label == "\uC9C0\uD558\uCCA0":
            return any(marker in normalized for marker in ["\uC9C0\uD558\uCCA0 \uACBD\uB85C", "1\uD638\uC120", "2\uD638\uC120", "\uD658\uC2B9"])
        if label == "\uAE30\uCC28":
            return any(marker in normalized for marker in ["KTX", "ITX", "\uBB34\uAD81\uD654", "\uC0C8\uB9C8\uC744"])
        return False

    def _resolve_step_metadata_value(self, step: ActionStep, key: str) -> object | None:
        if not isinstance(step.metadata, dict):
            return None
        return step.metadata.get(key)

    def _resolve_step_metadata_int(self, step: ActionStep, key: str, *, default: int = 0) -> int:
        value = self._resolve_step_metadata_value(step, key)
        if isinstance(value, int):
            return value
        if isinstance(value, str) and value.isdigit():
            return int(value)
        return default

    def _resolve_step_metadata_keys(self, step: ActionStep, key: str) -> list[str]:
        value = self._resolve_step_metadata_value(step, key)
        if isinstance(value, list):
            return [item for item in value if isinstance(item, str) and item.strip()]
        if isinstance(value, str) and value.strip():
            return [value.strip()]
        return []

    def _looks_like_download_url(self, url: str) -> bool:
        lowered = url.lower()
        return lowered.endswith(".pdf") or "filedown" in lowered or "download" in lowered

    async def _connect_or_launch_browser_async(self, playwright):  # noqa: ANN001
        if self.settings.browser_use_cdp:
            try:
                browser = await self._connect_or_bootstrap_cdp_browser_async(playwright)
                return browser, "cdp", True
            except Exception:
                pass
        return await playwright.chromium.launch(headless=self.settings.browser_headless), "launch", False

    async def _connect_or_bootstrap_cdp_browser_async(self, playwright):  # noqa: ANN001
        endpoint = self._resolve_cdp_endpoint()
        reused_browser = self._is_debug_browser_ready(endpoint)
        if not reused_browser:
            self._launch_debug_browser_window()
            self._wait_for_debug_browser(endpoint, self.settings.browser_debug_startup_timeout_ms)

        browser = await playwright.chromium.connect_over_cdp(endpoint)
        if not self._has_reusable_browser_page(browser):
            self._restart_debug_browser_runtime()
            browser = await playwright.chromium.connect_over_cdp(endpoint)
        return browser

    async def _ensure_browser_context_async(self, browser):  # noqa: ANN001
        try:
            contexts = browser.contexts
        except Exception:
            contexts = []
        if contexts:
            return contexts[0]
        return await browser.new_context()

    async def _resolve_page_for_session_async(self, context: Any, reused_browser: bool) -> Any:
        try:
            pages = context.pages
        except Exception:
            pages = []

        if reused_browser and pages:
            for page in reversed(pages):
                try:
                    url = (page.url or "").strip().lower()
                    if url.startswith("devtools://"):
                        continue
                    return page
                except Exception:
                    continue
            return pages[-1]

        if pages:
            for page in pages:
                try:
                    url = (page.url or "").strip().lower()
                    if url in ("", "about:blank", "chrome://newtab/"):
                        return page
                except Exception:
                    continue
            return pages[0]

        return await context.new_page()

    def _resolve_page_for_session(self, context: Any) -> Any:
        return asyncio.run(self._resolve_page_for_session_async(context, self._reused_browser))

    async def _switch_tab_async(self, current_page: Any, step: ActionStep) -> Any | None:
        context = getattr(current_page, "context", None)
        if context is None:
            return None
        pages = getattr(context, "pages", [])
        if not pages:
            return None
        if len(pages) <= 1:
            return None

        target = (step.target or "").strip().lower()
        metadata = step.metadata if isinstance(step.metadata, dict) else {}
        index = metadata.get("index")

        if isinstance(index, int) and 0 <= index < len(pages):
            page = pages[index]
            await page.bring_to_front()
            return page

        if target in {"last", "latest", "newest"}:
            page = pages[-1]
            await page.bring_to_front()
            return page

        if target in {"first", "initial"}:
            page = pages[0]
            await page.bring_to_front()
            return page

        for page in pages:
            try:
                title = (await page.title()).lower()
                url = (page.url or "").lower()
                if target and (target in title or target in url):
                    await page.bring_to_front()
                    return page
            except Exception:
                continue

        if current_page in pages and len(pages) > 1:
            current_index = pages.index(current_page)
            next_index = (current_index + 1) % len(pages)
            page = pages[next_index]
            await page.bring_to_front()
            return page

        return None

    async def _resolve_remaining_page_async(self, closed_page: Any) -> Any | None:
        context = getattr(closed_page, "context", None)
        if context is None:
            return None
        pages = getattr(context, "pages", [])
        for page in reversed(pages):
            try:
                if page is not closed_page and not page.is_closed():
                    await page.bring_to_front()
                    return page
            except Exception:
                continue
        return None

    def _browser_is_usable(self) -> bool:
        if self._browser is None:
            return False
        try:
            is_connected = bool(self._browser.is_connected())
        except Exception:
            return False
        if not is_connected:
            return False
        if self._browser_mode == "cdp":
            return self._is_debug_browser_ready(self._resolve_cdp_endpoint())
        return True

    def _page_is_usable(self) -> bool:
        if self._page is None or not self._browser_is_usable():
            return False
        try:
            if self._page.is_closed():
                return False
            _ = self._page.url
            return True
        except Exception:
            return False

    def _reset_browser_state(self) -> None:
        try:
            if self._page is not None and not self._page.is_closed():
                self._page.close()
        except Exception:
            pass
        try:
            if self._browser is not None and self._browser.is_connected():
                if self._browser_mode == "cdp":
                    self._browser.close()
                else:
                    self._browser.close()
        except Exception:
            pass
        try:
            if self._playwright_manager is not None:
                self._playwright_manager.stop()
        except Exception:
            pass

        self._page = None
        self._browser = None
        self._browser_context = None
        self._playwright = None
        self._playwright_manager = None
        self._browser_mode = "launch"
        self._reused_browser = False

    def _resolve_selector(self, step: ActionStep, context: dict[str, object] | None = None) -> str | None:
        selector = step.metadata.get("selector") if isinstance(step.metadata, dict) else None
        if isinstance(selector, str) and selector.strip():
            return selector.strip()
        if isinstance(step.target, str) and step.target.startswith("cand_") and isinstance(context, dict):
            observation = context.get("runtime_observation")
            if isinstance(observation, dict):
                for candidate in observation.get("candidate_targets", []):
                    if isinstance(candidate, dict) and candidate.get("candidate_id") == step.target:
                        selector_hint = candidate.get("selector_hint")
                        if isinstance(selector_hint, str) and selector_hint.strip():
                            return selector_hint.strip()
        if isinstance(step.target, str) and step.target.strip():
            return step.target.strip()
        return None

    def _default_search_and_read_steps(self, command: CanonicalCommand) -> list[ActionStep]:
        search_request = self._extract_search_request(command.normalized_text)
        steps = [
            ActionStep(action="search_web", target=search_request["target"], text=search_request["query"]),
            ActionStep(action="verify_page_loaded", target=search_request["target"]),
            ActionStep(action="extract_top_result", target=search_request["target"]),
        ]
        if self._should_open_linked_page_for_search(command.normalized_text):
            steps.extend(
                [
                    ActionStep(action="click_search_result", target=search_request["target"]),
                    ActionStep(action="verify_page_loaded", target="linked_page"),
                    ActionStep(action="read_linked_page", target="linked_page"),
                ]
            )
            return steps
        steps.append(ActionStep(action="read_page_summary", target=search_request["target"]))
        return steps

    def _should_open_linked_page_for_search(self, normalized_text: str) -> bool:
        lowered = normalized_text.lower()
        explicit_linked_page_markers = [
            "open the article",
            "open the page",
            "open the result",
            "read the article",
            "read the full article",
            "read the full page",
            "read the full post",
            "read the original page",
            "read the original source",
            "visit the page",
            "visit the site",
            "상세",
            "자세히",
            "원문",
            "본문",
            "기사",
            "페이지 열",
            "링크 열",
            "사이트 들어",
            "공고문",
        ]
        return any(marker in lowered for marker in explicit_linked_page_markers)

    def _map_route_kind_filter_step(self, route_kind: str) -> ActionStep | None:
        if route_kind not in {"subway", "bus", "train"}:
            return None
        return ActionStep(
            action="click_element",
            target="route_kind_filter",
            metadata={"route_kind_filter": route_kind},
        )

    async def _click_map_route_kind_filter_async(self, page: Any, route_kind: str) -> str:
        label_map = {
            "subway": "지하철",
            "bus": "버스",
            "train": "기차",
        }
        label = label_map.get(route_kind)
        if not label:
            raise ValueError(f"unsupported_route_kind:{route_kind}")

        regex_locator = page.get_by_text(re.compile(rf"^{re.escape(label)}\s*\d+$")).first
        try:
            if await regex_locator.count() > 0:
                await regex_locator.click(timeout=self.settings.browser_timeout_ms)
                await page.wait_for_timeout(700)
                return f"route_kind:{route_kind}"
        except Exception:
            pass

        exact_locator = page.get_by_text(label, exact=True).first
        if await exact_locator.count() == 0:
            raise ValueError(f"route_kind_filter_not_found:{route_kind}")
        await exact_locator.click(timeout=self.settings.browser_timeout_ms)
        await page.wait_for_timeout(700)
        return f"route_kind:{route_kind}"

    async def _click_map_route_kind_filter_v2_async(self, page: Any, route_kind: str) -> str:
        label_map = {
            "subway": "\uC9C0\uD558\uCCA0",
            "bus": "\uBC84\uC2A4",
            "train": "\uAE30\uCC28",
        }
        label = label_map.get(route_kind)
        if not label:
            raise ValueError(f"unsupported_route_kind:{route_kind}")

        regex_locator = page.get_by_text(re.compile(rf"^{re.escape(label)}\s*\d+$")).first
        try:
            if await regex_locator.count() > 0:
                await regex_locator.click(timeout=self.settings.browser_timeout_ms)
                await page.wait_for_timeout(1200)
                return f"route_kind:{route_kind}"
        except Exception:
            pass

        exact_locator = page.get_by_text(label, exact=True).first
        try:
            if await exact_locator.count() > 0:
                await exact_locator.click(timeout=self.settings.browser_timeout_ms)
                await page.wait_for_timeout(1200)
                return f"route_kind:{route_kind}"
        except Exception:
            pass

        fuzzy_locator = page.get_by_text(re.compile(re.escape(label))).first
        if await fuzzy_locator.count() == 0:
            raise ValueError(f"route_kind_filter_not_found:{route_kind}")
        await fuzzy_locator.click(timeout=self.settings.browser_timeout_ms)
        await page.wait_for_timeout(1200)
        return f"route_kind:{route_kind}"

    def _resolve_next_step_decision(
        self,
        *,
        decision: NextActionResponse | None,
        fallback_steps: list[ActionStep],
        executed_count: int,
    ) -> tuple[ActionStep | None, str, str | None]:
        if isinstance(decision, NextActionResponse) and decision.step is not None:
            return decision.step, "llm_next_action", None
        if isinstance(decision, NextActionResponse) and decision.done:
            return None, "llm_done", "llm_marked_done"
        if isinstance(decision, NextActionResponse) and decision.needs_recovery:
            if executed_count < len(fallback_steps):
                return fallback_steps[executed_count], "fallback", "llm_requested_recovery"
            return None, "llm_recovery", "llm_requested_recovery"
        if isinstance(decision, NextActionResponse):
            if executed_count < len(fallback_steps):
                return fallback_steps[executed_count], "fallback", "llm_returned_no_step"
            return None, "llm_no_step", "llm_returned_no_step"
        if executed_count < len(fallback_steps):
            return fallback_steps[executed_count], "fallback", "llm_unavailable"
        return None, "none", "no_next_action_available"

    def _describe_runtime_progress(
        self,
        *,
        executed_steps: list[dict[str, object]],
        last_result: dict[str, object] | None,
    ) -> str:
        if not executed_steps:
            return "initial"
        last_action = executed_steps[-1].get("action")
        if last_action == "open_browser_url":
            return "page_opened"
        if last_action == "search_web":
            return "search_submitted"
        if last_action == "verify_page_loaded":
            verification_result = None if not isinstance(last_result, dict) else last_result.get("verification_result")
            if verification_result == "route_result_loaded":
                return "route_results_ready"
            if verification_result == "page_loaded":
                return "page_loaded"
        if last_action == "extract_top_result":
            return "top_result_extracted"
        if last_action == "click_search_result":
            return "result_clicked"
        if last_action in {"read_page_summary", "read_linked_page", "summarize_page", "read_section"}:
            return "goal_read_completed"
        if last_action == "fill_input":
            return "form_field_filled"
        if last_action == "submit_form":
            return "form_submitted"
        return f"after_{last_action}"

    def _resolve_scroll_amount(self, step: ActionStep) -> int:
        if isinstance(step.metadata, dict):
            amount = step.metadata.get("amount")
            if isinstance(amount, int):
                return amount
            if isinstance(amount, str) and amount.lstrip("-").isdigit():
                return int(amount)
        if isinstance(step.text, str) and step.text.lstrip("-").isdigit():
            return int(step.text)
        return 900

    async def _read_first_async(self, scope: Any, selectors: list[str]) -> str | None:
        for selector in selectors:
            locator = scope.locator(selector).first
            try:
                if await locator.count() > 0:
                    text = (await locator.inner_text(timeout=1000)).strip()
                    if text:
                        return text
            except Exception:
                continue
        return None

    async def _read_href_async(self, scope: Any, selectors: list[str]) -> str | None:
        for selector in selectors:
            locator = scope.locator(selector).first
            try:
                if await locator.count() > 0:
                    href = await locator.get_attribute("href", timeout=1000)
                    if href:
                        return href
            except Exception:
                continue
        return None

    def _launch_debug_browser_window(self) -> None:
        chrome_path = self._resolve_chrome_path()
        if chrome_path is None:
            raise RuntimeError("chrome_executable_not_found")

        profile_dir = self._resolve_debug_profile_dir()
        profile_dir.mkdir(parents=True, exist_ok=True)
        subprocess.Popen(
            [
                chrome_path,
                f"--remote-debugging-port={self.settings.browser_debug_port}",
                f"--user-data-dir={profile_dir}",
                "--new-window",
                "about:blank",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )

    def _restart_debug_browser_runtime(self) -> None:
        self._terminate_debug_browser_processes()
        endpoint = self._resolve_cdp_endpoint()
        self._wait_for_debug_browser_shutdown(endpoint, timeout_ms=5000)
        self._launch_debug_browser_window()
        self._wait_for_debug_browser(endpoint, self.settings.browser_debug_startup_timeout_ms)

    def _resolve_cdp_endpoint(self) -> str:
        configured = self.settings.browser_cdp_url.strip()
        expected_port = f":{self.settings.browser_debug_port}"
        if configured.endswith(expected_port) or expected_port in configured:
            return configured
        return f"http://127.0.0.1:{self.settings.browser_debug_port}"

    def _resolve_debug_profile_dir(self) -> Path:
        configured = self.settings.browser_debug_profile_dir
        if configured:
            return Path(configured)

        project_root = os.getenv("VOICE_NAVIGATOR_ROOT")
        if project_root:
            return Path(project_root) / "runtime" / "chrome_debug_profile"

        return Path.cwd() / "runtime" / "chrome_debug_profile"

    def _resolve_chrome_path(self) -> str | None:
        configured = self.settings.browser_chrome_executable
        if configured and Path(configured).exists():
            return configured

        candidates = [
            os.path.join(os.getenv("PROGRAMFILES", ""), "Google", "Chrome", "Application", "chrome.exe"),
            os.path.join(os.getenv("PROGRAMFILES(X86)", ""), "Google", "Chrome", "Application", "chrome.exe"),
            os.path.join(os.getenv("LOCALAPPDATA", ""), "Google", "Chrome", "Application", "chrome.exe"),
        ]
        for candidate in candidates:
            if candidate and Path(candidate).exists():
                return candidate
        return None

    def _is_debug_browser_ready(self, endpoint: str) -> bool:
        try:
            with urlopen(f"{endpoint}/json/version", timeout=1.2) as response:
                return response.status == 200
        except (URLError, TimeoutError, OSError):
            return False

    def _wait_for_debug_browser(self, endpoint: str, timeout_ms: int) -> None:
        deadline = time.time() + (timeout_ms / 1000)
        while time.time() < deadline:
            if self._is_debug_browser_ready(endpoint):
                return
            time.sleep(0.25)
        raise RuntimeError("chrome_debug_endpoint_not_ready")

    def _wait_for_debug_browser_shutdown(self, endpoint: str, timeout_ms: int) -> None:
        deadline = time.time() + (timeout_ms / 1000)
        while time.time() < deadline:
            if not self._is_debug_browser_ready(endpoint):
                return
            time.sleep(0.25)
        raise RuntimeError("chrome_debug_endpoint_not_stopped")

    def _has_reusable_browser_page(self, browser: Any) -> bool:
        try:
            contexts = browser.contexts
        except Exception:
            return False

        for context in contexts:
            try:
                pages = context.pages
            except Exception:
                continue
            for page in pages:
                try:
                    url = (page.url or "").strip().lower()
                    if not url.startswith("devtools://"):
                        return True
                except Exception:
                    continue
        return False

    def _terminate_debug_browser_processes(self) -> None:
        profile_dir = str(self._resolve_debug_profile_dir()).lower()
        debug_port = str(self.settings.browser_debug_port)
        command = rf"""
$processes = Get-CimInstance Win32_Process -Filter "Name = 'chrome.exe'";
foreach ($process in $processes) {{
  $commandLine = '';
  if ($null -ne $process.CommandLine) {{
    $commandLine = $process.CommandLine.ToLowerInvariant();
  }}
  if (
    $commandLine.Contains('--remote-debugging-port={debug_port}') -or
    $commandLine.Contains('{profile_dir}')
  ) {{
    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue;
  }}
}}
"""
        subprocess.run(
            ["powershell", "-NoProfile", "-Command", command],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            check=False,
        )

    def _is_recoverable_browser_error(self, exc: Exception) -> bool:
        detail = str(exc).lower()
        signals = [
            "target page, context or browser has been closed",
            "browser has been closed",
            "connection closed",
            "closed the page",
            "target closed",
        ]
        return any(signal in detail for signal in signals)
