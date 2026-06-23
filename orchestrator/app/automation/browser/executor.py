from __future__ import annotations

import re
from typing import Any
from urllib.parse import quote_plus

from app.core.settings import Settings
from app.models.action_step import ActionStep
from app.models.canonical_command import CanonicalCommand


class BrowserExecutor:
    def __init__(self, settings: Settings | None = None) -> None:
        self.settings = settings or Settings.from_env()

    def execute(self, command: CanonicalCommand) -> dict[str, object]:
        if command.intent == "search_and_read":
            return self._execute_search_and_read(command)

        return {
            "status": "stubbed",
            "executor": "browser",
            "strategy": "playwright-first",
            "normalized_text": command.normalized_text,
        }

    def observe(self, command: CanonicalCommand) -> dict[str, object]:
        query = self._extract_search_query(command.normalized_text)
        return {
            "task_domain": command.task_domain,
            "intent": command.intent,
            "query": query,
            "default_engine": "naver",
        }

    def execute_action_plan(
        self,
        command: CanonicalCommand,
        steps: list[ActionStep],
    ) -> dict[str, object]:
        try:
            from playwright.sync_api import Error as PlaywrightError
            from playwright.sync_api import sync_playwright
        except Exception:
            return {
                "status": "failed",
                "executor": "browser",
                "strategy": "llm-action-plan",
                "reason": "playwright_not_installed",
            }

        try:
            with sync_playwright() as playwright:
                browser = playwright.chromium.launch(headless=self.settings.browser_headless)
                page = browser.new_page()
                page.set_default_timeout(self.settings.browser_timeout_ms)

                context: dict[str, object] = {
                    "page": page,
                    "command": command.normalized_text,
                    "intent": command.intent,
                    "query": self._extract_search_query(command.normalized_text),
                    "executed_steps": [],
                }

                for index, step in enumerate(steps, start=1):
                    step_result = self.execute_action_step(step, context=context)
                    context["executed_steps"].append(
                        {
                            "index": index,
                            "action": step.action,
                            "target": step.target,
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
                        }

                result_card = context.get("top_result") if isinstance(context.get("top_result"), dict) else {}
                return {
                    "status": "success",
                    "executor": "browser",
                    "strategy": "llm-action-plan",
                    "intent": command.intent,
                    "query": context.get("query"),
                    "url": context.get("page_url"),
                    "page_title": context.get("page_title"),
                    "top_result_title": result_card.get("title") if isinstance(result_card, dict) else None,
                    "top_result_snippet": result_card.get("snippet") if isinstance(result_card, dict) else None,
                    "top_result_url": result_card.get("url") if isinstance(result_card, dict) else None,
                    "page_summary": context.get("page_summary"),
                    "linked_page_url": context.get("linked_page_url"),
                    "executed_steps": context["executed_steps"],
                }
        except PlaywrightError as exc:
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

    def execute_action_step(self, step: ActionStep, context: dict[str, object]) -> dict[str, object]:
        page = context.get("page")
        if page is None:
            return {"status": "failed", "reason": "missing_page_context"}

        if step.action == "open_browser_url":
            target_url = step.target or context.get("target_url")
            if not isinstance(target_url, str) or not target_url:
                return {"status": "failed", "reason": "missing_target_url"}
            page.goto(target_url, wait_until="domcontentloaded")
            page.wait_for_timeout(1200)
            context["page_url"] = page.url
            context["page_title"] = page.title()
            return {"status": "success", "url": page.url}

        if step.action == "search_web":
            query = step.text or context.get("query")
            if not isinstance(query, str) or not query:
                return {"status": "failed", "reason": "missing_search_query"}
            target_url = self._build_naver_search_url(query)
            page.goto(target_url, wait_until="domcontentloaded")
            page.wait_for_timeout(1500)
            context["query"] = query
            context["target_url"] = target_url
            context["page_url"] = page.url
            context["page_title"] = page.title()
            return {"status": "success", "query": query, "url": page.url}

        if step.action == "extract_top_result":
            result_card = self._extract_first_result(page)
            if not any(result_card.values()):
                return {"status": "failed", "reason": "top_result_not_found"}
            context["top_result"] = result_card
            return {"status": "success", "top_result": result_card}

        if step.action == "click_search_result":
            result_card = context.get("top_result")
            if not isinstance(result_card, dict):
                result_card = self._extract_first_result(page)
                context["top_result"] = result_card
            result_url = result_card.get("url") if isinstance(result_card, dict) else None
            if not isinstance(result_url, str) or not result_url:
                return {"status": "failed", "reason": "missing_result_url"}
            if self._looks_like_download_url(result_url):
                context["linked_page_url"] = result_url
                context["download_only"] = True
                return {"status": "success", "url": result_url, "mode": "download_only"}
            page.goto(result_url, wait_until="domcontentloaded")
            page.wait_for_timeout(1500)
            context["linked_page_url"] = page.url
            context["page_url"] = page.url
            context["page_title"] = page.title()
            return {"status": "success", "url": page.url}

        if step.action == "read_page_summary":
            result_card = context.get("top_result")
            if not isinstance(result_card, dict):
                result_card = self._extract_first_result(page)
                context["top_result"] = result_card
            summary = None
            if isinstance(result_card, dict):
                summary = result_card.get("snippet") or result_card.get("title")
            if not isinstance(summary, str) or not summary.strip():
                return {"status": "failed", "reason": "page_summary_not_found"}
            context["page_summary"] = summary.strip()
            return {"status": "success", "page_summary": context["page_summary"]}

        if step.action == "read_linked_page":
            if context.get("download_only") is True:
                result_card = context.get("top_result")
                if isinstance(result_card, dict):
                    summary = result_card.get("snippet") or result_card.get("title")
                    if isinstance(summary, str) and summary.strip():
                        context["page_summary"] = summary.strip()
                        return {"status": "success", "page_summary": context["page_summary"]}
            summary = self._extract_page_body_summary(page)
            if not summary:
                return {"status": "failed", "reason": "linked_page_summary_not_found"}
            context["page_summary"] = summary
            context["page_title"] = page.title()
            context["page_url"] = page.url
            return {"status": "success", "page_summary": summary}

        if step.action == "verify_page_loaded":
            page_title = page.title().strip()
            page_url = page.url
            context["page_title"] = page_title
            context["page_url"] = page_url
            if not page_title or not page_url:
                return {"status": "failed", "reason": "page_verification_failed"}
            return {"status": "success", "page_title": page_title, "url": page_url}

        return {"status": "failed", "reason": "unsupported_action_step"}

    def _execute_search_and_read(self, command: CanonicalCommand) -> dict[str, object]:
        query = self._extract_search_query(command.normalized_text)
        steps = [
            ActionStep(action="search_web", target="naver", text=query),
            ActionStep(action="verify_page_loaded", target="naver"),
            ActionStep(action="extract_top_result", target="naver"),
            ActionStep(action="click_search_result", target="naver"),
            ActionStep(action="verify_page_loaded", target="linked_page"),
            ActionStep(action="read_linked_page", target="linked_page"),
        ]
        return self.execute_action_plan(command, steps)

    def _build_naver_search_url(self, query: str) -> str:
        return f"https://search.naver.com/search.naver?query={quote_plus(query)}"

    def _extract_search_query(self, text: str) -> str:
        patterns = [
            r"naver for (.+?) and read",
            r"search naver for (.+?) and read",
            r"search naver for (.+)",
            r"search for (.+?) and read",
            r"search for (.+)",
            r"search (.+?) and read",
            r"search (.+)",
        ]
        lowered = text.lower()

        for pattern in patterns:
            match = re.search(pattern, lowered, flags=re.IGNORECASE)
            if match:
                extracted = match.group(1).strip(" .")
                extracted = re.sub(r"\b(the conditions|conditions|details|read)\b", "", extracted, flags=re.IGNORECASE)
                if extracted.strip():
                    return extracted.strip()

        cleaned = re.sub(r"\b(search|read|find|open|browser|naver|for|and)\b", "", lowered)
        return cleaned.strip(" .") or text

    def _extract_first_result(self, page: Any) -> dict[str, str | None]:
        result_selectors = [
            ".total_group .bx",
            ".api_subject_bx",
            ".search_result .bx",
            "main .bx",
        ]

        for selector in result_selectors:
            cards = page.locator(selector)
            try:
                count = cards.count()
            except Exception:
                continue

            for index in range(min(count, 5)):
                card = cards.nth(index)
                data = self._extract_result_from_card(card)
                if data.get("title") or data.get("snippet"):
                    return data

        return {
            "title": self._read_first(page, ["a.title_link", "a.link_tit", ".total_tit", "h3"]),
            "snippet": self._read_first(page, [".desc", ".total_dsc", ".api_txt_lines", ".news_dsc"]),
            "url": self._read_href(page, ["a.title_link", "a.link_tit", ".total_tit a"]),
        }

    def _extract_result_from_card(self, card: Any) -> dict[str, str | None]:
        title = self._read_first(card, ["a.title_link", "a.link_tit", ".total_tit", "h3", "a"])
        snippet = self._read_first(
            card,
            [
                ".desc",
                ".total_dsc",
                ".api_txt_lines",
                ".news_dsc",
                ".dsc_txt_wrap",
                "p",
            ],
        )
        url = self._read_href(card, ["a.title_link", "a.link_tit", ".total_tit a", "a"])
        return {"title": title, "snippet": snippet, "url": url}

    def _extract_page_body_summary(self, page: Any) -> str | None:
        for selector in ["main", "article", "#content", ".content", "body"]:
            locator = page.locator(selector).first
            try:
                if locator.count() > 0:
                    text = locator.inner_text(timeout=1500).strip()
                    normalized = re.sub(r"\s+", " ", text)
                    if normalized:
                        return normalized[:400]
            except Exception:
                continue
        return None

    def _looks_like_download_url(self, url: str) -> bool:
        lowered = url.lower()
        return lowered.endswith(".pdf") or "filedown" in lowered or "download" in lowered

    def _read_first(self, scope: Any, selectors: list[str]) -> str | None:
        for selector in selectors:
            locator = scope.locator(selector).first
            try:
                if locator.count() > 0:
                    text = locator.inner_text(timeout=1000).strip()
                    if text:
                        return text
            except Exception:
                continue
        return None

    def _read_href(self, scope: Any, selectors: list[str]) -> str | None:
        for selector in selectors:
            locator = scope.locator(selector).first
            try:
                if locator.count() > 0:
                    href = locator.get_attribute("href", timeout=1000)
                    if href:
                        return href
            except Exception:
                continue
        return None
