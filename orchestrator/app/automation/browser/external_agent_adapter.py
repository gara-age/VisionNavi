from __future__ import annotations

import asyncio
import json
import re
import time
from collections.abc import Mapping, Sequence
from urllib.parse import urlparse

from app.core.settings import Settings
from app.automation.browser.executor import BrowserExecutor
from app.models.agent_adapter import AgentAdapterRequest, AgentAdapterResponse
from app.models.execution_backend import ExecutionBackend
from app.services.model_client import RemoteModelClient


class ExternalBrowserAgentAdapter:
    def __init__(
        self,
        browser_executor: BrowserExecutor,
        model_client: RemoteModelClient,
        settings: Settings | None = None,
    ) -> None:
        self.browser_executor = browser_executor
        self.model_client = model_client
        self.settings = settings or Settings.from_env()
        self.execution_backend: ExecutionBackend = "external_browser_agent"

    def supports(self, request: AgentAdapterRequest) -> bool:
        return request.command.task_domain == "web" and request.command.intent == "search_and_read"

    def execute(self, request: AgentAdapterRequest) -> AgentAdapterResponse:
        try:
            return asyncio.run(self._execute_async(request))
        except Exception as exc:
            return AgentAdapterResponse(
                status="failed",
                execution_backend=self.execution_backend,
                blocked_reason=f"external_browser_agent_runtime_failed:{type(exc).__name__}",
                raw_agent_trace={
                    "adapter": self.execution_backend,
                    "error": f"{type(exc).__name__}: {exc}",
                },
                normalized_agent_trace=[
                    {"phase": "observe", "detail": "Prepared browser-use task input"},
                    {"phase": "decide", "detail": "browser-use runtime failed before completion"},
                ],
            )

    async def _execute_async(self, request: AgentAdapterRequest) -> AgentAdapterResponse:
        try:
            from browser_use import Agent
            from browser_use.browser.profile import BrowserProfile
            from browser_use.browser.session import BrowserSession
            from browser_use.llm import ChatOllama
            from playwright.async_api import async_playwright
        except Exception as exc:
            return AgentAdapterResponse(
                status="failed",
                execution_backend=self.execution_backend,
                blocked_reason=f"browser_use_import_failed:{type(exc).__name__}",
                raw_agent_trace={
                    "adapter": self.execution_backend,
                    "error": f"{type(exc).__name__}: {exc}",
                },
                normalized_agent_trace=[
                    {"phase": "observe", "detail": "Prepared browser-use task input"},
                    {"phase": "decide", "detail": "browser-use package import failed"},
                ],
            )

        search_request = self.browser_executor._extract_search_request(request.command.normalized_text)  # noqa: SLF001
        task = self._build_task(request, search_request)
        profile_dir = self.browser_executor._resolve_debug_profile_dir()  # noqa: SLF001
        chrome_path = self.browser_executor._resolve_chrome_path()  # noqa: SLF001
        cdp_endpoint = self.browser_executor._resolve_cdp_endpoint()  # noqa: SLF001
        cdp_ready = self.browser_executor._is_debug_browser_ready(cdp_endpoint)  # noqa: SLF001
        if not cdp_ready:
            self.browser_executor._launch_debug_browser_window()  # noqa: SLF001
            self.browser_executor._wait_for_debug_browser(  # noqa: SLF001
                cdp_endpoint,
                self.settings.browser_debug_startup_timeout_ms,
            )
            cdp_ready = True

        cleanup_result = await self._prepare_clean_browser_session(async_playwright, cdp_endpoint)

        raw_trace: dict[str, object] = {
            "adapter": self.execution_backend,
            "runtime": "browser-use",
            "request": {
                "command": request.command.model_dump(),
                "observation": request.observation,
                "policy_flags": request.policy_flags,
            },
            "task": task,
            "browser_config": {
                "profile_dir": str(profile_dir),
                "chrome_path": chrome_path,
                "cdp_endpoint": cdp_endpoint,
                "cdp_ready": cdp_ready,
                "use_vision": self.settings.external_browser_agent_use_vision,
                "model": self.settings.external_browser_agent_model,
            },
            "session_cleanup": cleanup_result,
        }

        browser_profile = BrowserProfile(
            headless=self.settings.browser_headless,
            keep_alive=True,
            minimum_wait_page_load_time=0.25,
            wait_for_network_idle_page_load_time=0.5,
            wait_between_actions=0.2,
            highlight_elements=False,
        )
        browser_session = BrowserSession(
            cdp_url=cdp_endpoint,
            is_local=True,
            browser_profile=browser_profile,
        )
        raw_trace["launch_mode"] = "cdp_attach"

        llm = ChatOllama(
            model=self.settings.external_browser_agent_model,
            host=self.settings.ollama_base_url,
            ollama_options={
                "temperature": 0.0,
            },
        )

        callback_steps: list[dict[str, object]] = []
        normalized_trace: list[dict[str, object]] = [
            {"phase": "observe", "detail": "Prepared browser-use task and browser session"},
        ]

        def register_new_step_callback(state, output, step_number: int) -> None:  # noqa: ANN001
            serialized_state = self._safe_dump(state)
            serialized_output = self._safe_dump(output)
            callback_steps.append(
                {
                    "step_number": step_number,
                    "url": getattr(state, "url", None),
                    "title": getattr(state, "title", None),
                    "state": serialized_state,
                    "output": serialized_output,
                }
            )
            normalized_trace.append(
                {
                    "phase": "decide",
                    "detail": f"browser-use selected step {step_number}",
                    "payload": {
                        "url": getattr(state, "url", None),
                        "title": getattr(state, "title", None),
                    },
                }
            )

        agent = Agent(
            task=task,
            llm=llm,
            browser_session=browser_session,
            register_new_step_callback=register_new_step_callback,
            use_vision=self.settings.external_browser_agent_use_vision,
            directly_open_url=True,
            use_judge=False,
            final_response_after_failure=True,
            max_actions_per_step=3,
            max_failures=3,
            step_timeout=self.settings.external_browser_agent_step_timeout_s,
            enable_planning=True,
        )

        started_at = time.perf_counter()
        total_timeout_s = max(
            self.settings.external_browser_agent_step_timeout_s,
            (self.settings.external_browser_agent_step_timeout_s * self.settings.external_browser_agent_max_steps) + 30,
        )
        try:
            history = await asyncio.wait_for(
                agent.run(max_steps=self.settings.external_browser_agent_max_steps),
                timeout=total_timeout_s,
            )
        except asyncio.TimeoutError:
            duration_ms = round((time.perf_counter() - started_at) * 1000, 1)
            raw_trace["duration_ms"] = duration_ms
            raw_trace["timeout_s"] = total_timeout_s
            raw_trace["step_trace"] = self._safe_dump(callback_steps)
            raw_trace["history"] = None
            raw_trace["final_result"] = None
            raw_trace["history_urls"] = []
            raw_trace["validation"] = {
                "ok": False,
                "reason": "external_browser_agent_timeout",
                "query_tokens": self._query_tokens(str(search_request.get("query", ""))),
                "matched_tokens": [],
                "expected_domains": self._expected_domains_for_target(str(search_request.get("target", ""))),
                "visited_domains": [],
                "final_domain": "",
            }
            normalized_trace.append(
                {
                    "phase": "verify",
                    "detail": "browser-use exceeded the total execution timeout",
                    "payload": {
                        "duration_ms": duration_ms,
                        "timeout_s": total_timeout_s,
                        "steps": len(callback_steps),
                    },
                }
            )
            return AgentAdapterResponse(
                status="failed",
                execution_backend=self.execution_backend,
                result={
                    "status": "failed",
                    "executor": "browser",
                    "strategy": "browser-use",
                    "summary": None,
                    "history_urls": [],
                    "total_duration_seconds": None,
                    "step_count": len(callback_steps),
                    "task": task,
                    "duration_ms": duration_ms,
                    "failure_reason": "external_browser_agent_timeout",
                    "validation": self._safe_dump(raw_trace["validation"]),
                },
                raw_agent_trace=self._safe_dump(raw_trace),
                normalized_agent_trace=self._safe_dump(normalized_trace),
                blocked_reason="external_browser_agent_timeout",
            )
        duration_ms = round((time.perf_counter() - started_at) * 1000, 1)

        final_result = history.final_result()
        history_dump = self._safe_dump(history)
        success = bool(getattr(history, "is_successful", lambda: False)())
        history_urls = getattr(history, "urls", lambda: [])()
        raw_trace["history"] = history_dump
        raw_trace["step_trace"] = self._safe_dump(callback_steps)
        raw_trace["duration_ms"] = duration_ms
        raw_trace["final_result"] = self._safe_dump(final_result)
        raw_trace["history_urls"] = self._safe_dump(history_urls)

        validation = self._validate_run_output(
            search_request=search_request,
            summary=final_result,
            history_urls=history_urls,
            callback_steps=callback_steps,
        )
        raw_trace["validation"] = self._safe_dump(validation)
        if success and not validation["ok"]:
            success = False

        normalized_trace.append(
            {
                "phase": "verify",
                "detail": f"browser-use finished with status {'success' if success else 'failed'}",
                "payload": {
                    "duration_ms": duration_ms,
                    "steps": len(callback_steps),
                    "validation_ok": validation["ok"],
                    "validation_reason": validation["reason"],
                },
            }
        )

        failure_reason = None if success else str(validation["reason"] or "external_browser_agent_execution_failed")
        return AgentAdapterResponse(
            status="success" if success else "failed",
            execution_backend=self.execution_backend,
            result={
                "status": "success" if success else "failed",
                "executor": "browser",
                "strategy": "browser-use",
                "summary": final_result,
                "history_urls": history_urls,
                "total_duration_seconds": getattr(history, "total_duration_seconds", lambda: None)(),
                "step_count": len(callback_steps),
                "task": task,
                "duration_ms": duration_ms,
                "failure_reason": failure_reason,
                "validation": self._safe_dump(validation),
            },
            raw_agent_trace=self._safe_dump(raw_trace),
            normalized_agent_trace=self._safe_dump(normalized_trace),
            blocked_reason=None if success else failure_reason,
        )

    def _build_task(self, request: AgentAdapterRequest, search_request: dict[str, str]) -> str:
        target = search_request["target"]
        query = search_request["query"]
        search_url = self.browser_executor._build_search_url(target, query)  # noqa: SLF001
        return (
            f"You are operating a real browser to complete a search-and-read task.\n"
            f"Preferred site or engine: {target}\n"
            f"Exact search query: {query}\n"
            f"Required starting URL: {search_url}\n"
            "Rules:\n"
            "- Start from a clean tab and treat this task as independent from any previously open page.\n"
            "- Open the required starting URL first.\n"
            "- Stay on the requested site or engine unless it is clearly unavailable.\n"
            "- Do not switch to another search engine.\n"
            "- Do not translate, paraphrase, or rewrite the search query.\n"
            "- Use the exact search query string as provided.\n"
            "- Prefer reading the search result card or summary on the results page first.\n"
            "- Do not open unrelated news articles or secondary pages unless the results page is insufficient.\n"
            "- Do not answer with information unrelated to the search query.\n"
            "- If you cannot find query-grounded information, say the task could not be completed instead of guessing.\n"
            "- Keep the browser open after the task finishes.\n"
            "- Return a concise summary of what you found.\n"
            f"User command: {request.command.normalized_text}"
        )

    async def _prepare_clean_browser_session(self, async_playwright, cdp_endpoint: str) -> dict[str, object]:  # noqa: ANN001
        closed_pages = 0
        reset_pages = 0
        created_page = False
        async with async_playwright() as playwright:
            browser = await playwright.chromium.connect_over_cdp(cdp_endpoint)
            try:
                pages: list[object] = []
                for context in browser.contexts:
                    pages.extend(context.pages)

                usable_pages = []
                for page in pages:
                    try:
                        url = str((page.url or "")).strip().lower()
                    except Exception:
                        url = ""
                    if url.startswith("devtools://"):
                        continue
                    usable_pages.append(page)

                active_page = usable_pages[0] if usable_pages else None
                for extra_page in usable_pages[1:]:
                    try:
                        await extra_page.close()
                        closed_pages += 1
                    except Exception:
                        continue

                if active_page is None:
                    context = browser.contexts[0] if browser.contexts else await browser.new_context()
                    active_page = await context.new_page()
                    created_page = True

                try:
                    await active_page.goto("about:blank", wait_until="domcontentloaded")
                    reset_pages += 1
                except Exception:
                    pass
            finally:
                await browser.close()

        return {
            "closed_pages": closed_pages,
            "reset_pages": reset_pages,
            "created_page": created_page,
        }

    def _validate_run_output(
        self,
        *,
        search_request: dict[str, str],
        summary: object,
        history_urls: object,
        callback_steps: list[dict[str, object]],
    ) -> dict[str, object]:
        summary_text = str(summary or "").strip()
        history_url_list = [str(item).strip() for item in history_urls if str(item).strip()] if isinstance(history_urls, list) else []
        titles = [
            str(step.get("title", "")).strip()
            for step in callback_steps
            if isinstance(step, dict) and str(step.get("title", "")).strip()
        ]
        grounding_text = " ".join([summary_text, *titles]).lower()
        target = str(search_request.get("target", "")).strip().lower()
        query = str(search_request.get("query", "")).strip().lower()
        query_tokens = self._query_tokens(query)
        matched_tokens = [token for token in query_tokens if token in grounding_text]

        required_matches = 1 if len(query_tokens) <= 2 else 2
        expected_domains = self._expected_domains_for_target(target)
        visited_domains = [
            domain
            for domain in (self._extract_domain(url) for url in history_url_list)
            if domain
        ]
        final_domain = visited_domains[-1] if visited_domains else ""
        has_expected_domain = not expected_domains or any(
            any(expected in visited for expected in expected_domains)
            for visited in visited_domains
        )
        final_domain_matches = not expected_domains or any(
            expected in final_domain for expected in expected_domains
        )

        if not summary_text:
            return {
                "ok": False,
                "reason": "external_browser_agent_empty_summary",
                "matched_tokens": matched_tokens,
                "query_tokens": query_tokens,
                "visited_domains": visited_domains,
            }
        if expected_domains and (not has_expected_domain or not final_domain_matches):
            return {
                "ok": False,
                "reason": "external_browser_agent_off_target_navigation",
                "matched_tokens": matched_tokens,
                "query_tokens": query_tokens,
                "visited_domains": visited_domains,
                "final_domain": final_domain,
                "expected_domains": expected_domains,
            }
        if query_tokens and len(matched_tokens) < required_matches:
            return {
                "ok": False,
                "reason": "external_browser_agent_off_target_summary",
                "matched_tokens": matched_tokens,
                "query_tokens": query_tokens,
                "required_matches": required_matches,
                "visited_domains": visited_domains,
                "final_domain": final_domain,
            }
        return {
            "ok": True,
            "reason": None,
            "matched_tokens": matched_tokens,
            "query_tokens": query_tokens,
            "visited_domains": visited_domains,
            "final_domain": final_domain,
        }

    def _query_tokens(self, query: str) -> list[str]:
        stopwords = {
            "search",
            "find",
            "read",
            "summary",
            "summarize",
            "page",
            "result",
            "results",
            "the",
            "and",
            "for",
            "with",
            "from",
            "about",
            "please",
        }
        tokens = re.findall(r"[0-9a-zA-Z가-힣]{2,}", query.lower())
        if len(tokens) <= 1:
            return tokens
        unique_tokens: list[str] = []
        for token in tokens:
            if token in stopwords:
                continue
            if token not in unique_tokens:
                unique_tokens.append(token)
        return unique_tokens

    def _expected_domains_for_target(self, target: str) -> list[str]:
        mapping = {
            "naver": ["naver.com"],
            "google": ["google.com"],
            "youtube": ["youtube.com"],
        }
        return mapping.get(target, [])

    def _extract_domain(self, url: str) -> str:
        try:
            return urlparse(url).netloc.lower()
        except Exception:
            return ""

    def _safe_dump(self, value: object) -> object:
        if value is None or isinstance(value, (str, int, float, bool)):
            return value
        if isinstance(value, Mapping):
            return {
                str(key): self._safe_dump(item)
                for key, item in value.items()
            }
        if isinstance(value, Sequence) and not isinstance(value, (str, bytes, bytearray)):
            return [self._safe_dump(item) for item in value]
        if hasattr(value, "model_dump"):
            try:
                return self._safe_dump(value.model_dump())  # type: ignore[no-any-return]
            except Exception:
                pass
        if hasattr(value, "__dict__"):
            try:
                return self._safe_dump(dict(value.__dict__))  # type: ignore[arg-type]
            except Exception:
                pass
        try:
            json.dumps(value)
            return value
        except TypeError:
            pass
        return str(value)
