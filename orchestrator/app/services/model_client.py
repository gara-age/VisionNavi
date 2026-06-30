from __future__ import annotations

from app.core.settings import Settings
from app.models.model_api import (
    ActionPlanRequest,
    ActionPlanResponse,
    CanonicalCommandPredictionRequest,
    CanonicalCommandPredictionResponse,
    NextActionRequest,
    NextActionResponse,
    PopupSummaryRequest,
    PopupSummaryResponse,
    VisionObservationRequest,
    VisionObservationResponse,
)


class RemoteModelClient:
    def __init__(self, settings: Settings | None = None) -> None:
        self.settings = settings or Settings.from_env()

    def is_enabled(self) -> bool:
        if not self.settings.model_api_enabled:
            return False
        if self.settings.model_provider == "ollama":
            return True
        return bool(self.settings.model_api_url)

    def predict_canonical_command(
        self, request: CanonicalCommandPredictionRequest
    ) -> CanonicalCommandPredictionResponse | None:
        if not self.is_enabled():
            return None

        if self.settings.model_provider == "ollama":
            return self._predict_with_ollama(request)

        return self._predict_with_remote_api(request)

    def plan_action_steps(self, request: ActionPlanRequest) -> ActionPlanResponse | None:
        if not self.is_enabled():
            return None

        if self.settings.model_provider == "ollama":
            return self._plan_with_ollama(request)

        return None

    def decide_next_action(self, request: NextActionRequest) -> NextActionResponse | None:
        if not self.is_enabled():
            return None

        if self.settings.model_provider == "ollama":
            return self._decide_next_action_with_ollama(request)

        return None

    def analyze_visual_observation(self, request: VisionObservationRequest, image_base64: str) -> VisionObservationResponse | None:
        if not self.is_enabled():
            return None
        if not self.settings.ollama_vision_enabled:
            return None
        if self.settings.model_provider == "ollama":
            return self._analyze_visual_observation_with_ollama(request, image_base64)
        return None

    def summarize_popup(self, request: PopupSummaryRequest) -> PopupSummaryResponse | None:
        if not self.is_enabled():
            return None
        if self.settings.model_provider == "ollama":
            return self._summarize_popup_with_ollama(request)
        return None

    def _predict_with_remote_api(
        self, request: CanonicalCommandPredictionRequest
    ) -> CanonicalCommandPredictionResponse:
        import httpx

        headers = {"Content-Type": "application/json"}
        if self.settings.model_api_key:
            headers["Authorization"] = f"Bearer {self.settings.model_api_key}"

        with httpx.Client(timeout=self.settings.model_api_timeout_s) as client:
            response = client.post(
                self.settings.model_api_url,
                headers=headers,
                json=request.model_dump(),
            )
            response.raise_for_status()
            payload = response.json()

        return CanonicalCommandPredictionResponse.model_validate(payload)

    def _plan_with_ollama(self, request: ActionPlanRequest) -> ActionPlanResponse:
        import httpx

        prompt = self._build_action_plan_prompt(request)

        with httpx.Client(timeout=self.settings.model_api_timeout_s) as client:
            response = client.post(
                f"{self.settings.ollama_base_url}/api/generate",
                headers={"Content-Type": "application/json"},
                json={
                    "model": self.settings.ollama_planner_model,
                    "prompt": prompt,
                    "stream": False,
                    "format": "json",
                    "options": {
                        "temperature": self.settings.ollama_planner_temperature,
                        "num_predict": self.settings.ollama_planner_num_predict,
                    },
                },
            )
            response.raise_for_status()
            payload = response.json()

        raw_response = payload.get("response", "")
        return ActionPlanResponse.model_validate(self._load_json_response(raw_response))

    def _decide_next_action_with_ollama(self, request: NextActionRequest) -> NextActionResponse:
        import httpx

        prompt = self._build_next_action_prompt(request)

        with httpx.Client(timeout=self.settings.model_api_timeout_s) as client:
            response = client.post(
                f"{self.settings.ollama_base_url}/api/generate",
                headers={"Content-Type": "application/json"},
                json={
                    "model": self.settings.ollama_planner_model,
                    "prompt": prompt,
                    "stream": False,
                    "format": "json",
                    "options": {
                        "temperature": self.settings.ollama_planner_temperature,
                        "num_predict": self.settings.ollama_planner_num_predict,
                    },
                },
            )
            response.raise_for_status()
            payload = response.json()

        raw_response = payload.get("response", "")
        return NextActionResponse.model_validate(self._load_json_response(raw_response))

    def _predict_with_ollama(
        self, request: CanonicalCommandPredictionRequest
    ) -> CanonicalCommandPredictionResponse:
        import httpx

        prompt = self._build_ollama_prompt(request)

        with httpx.Client(timeout=self.settings.model_api_timeout_s) as client:
            response = client.post(
                f"{self.settings.ollama_base_url}/api/generate",
                headers={"Content-Type": "application/json"},
                json={
                    "model": self.settings.ollama_model,
                    "prompt": prompt,
                    "stream": False,
                    "format": "json",
                    "options": {
                        "temperature": 0.1,
                    },
                },
            )
            response.raise_for_status()
            payload = response.json()

        raw_response = payload.get("response", "")
        return CanonicalCommandPredictionResponse.model_validate(self._load_json_response(raw_response))

    def _analyze_visual_observation_with_ollama(
        self,
        request: VisionObservationRequest,
        image_base64: str,
    ) -> VisionObservationResponse:
        import httpx

        prompt = self._build_vision_observation_prompt(request)

        with httpx.Client(timeout=self.settings.model_api_timeout_s) as client:
            response = client.post(
                f"{self.settings.ollama_base_url}/api/generate",
                headers={"Content-Type": "application/json"},
                json={
                    "model": self.settings.ollama_vision_model,
                    "prompt": prompt,
                    "images": [image_base64],
                    "stream": False,
                    "format": "json",
                    "options": {
                        "temperature": 0.0,
                        "num_predict": self.settings.ollama_vision_num_predict,
                    },
                },
            )
            response.raise_for_status()
            payload = response.json()

        raw_response = payload.get("response", "")
        return VisionObservationResponse.model_validate(self._load_json_response(raw_response))

    def _summarize_popup_with_ollama(self, request: PopupSummaryRequest) -> PopupSummaryResponse:
        import httpx

        prompt = self._build_popup_summary_prompt(request)

        with httpx.Client(timeout=self.settings.model_api_timeout_s) as client:
            response = client.post(
                f"{self.settings.ollama_base_url}/api/generate",
                headers={"Content-Type": "application/json"},
                json={
                    "model": self.settings.ollama_model,
                    "prompt": prompt,
                    "stream": False,
                    "format": "json",
                    "options": {
                        "temperature": 0.2,
                        "num_predict": 180,
                    },
                },
            )
            response.raise_for_status()
            payload = response.json()

        raw_response = payload.get("response", "")
        return PopupSummaryResponse.model_validate(self._load_json_response(raw_response))

    def _load_json_response(self, raw_response: str) -> dict[str, object]:
        import json

        last_error: Exception | None = None
        for candidate in self._json_parse_candidates(raw_response):
            try:
                parsed = json.loads(candidate)
            except json.JSONDecodeError as exc:
                last_error = exc
                continue
            if isinstance(parsed, dict):
                return parsed
        if last_error is not None:
            raise last_error
        raise ValueError("Model response did not contain a JSON object")

    def _json_parse_candidates(self, raw_response: str) -> list[str]:
        text = raw_response.strip()
        candidates: list[str] = []
        if text:
            candidates.append(text)

        if text.startswith("```"):
            lines = text.splitlines()
            if len(lines) >= 3:
                fenced = "\n".join(lines[1:-1]).strip()
                if fenced and fenced not in candidates:
                    candidates.append(fenced)

        extracted = self._extract_outer_json_object(text)
        if extracted and extracted not in candidates:
            candidates.append(extracted)

        repaired = self._repair_common_json_issues(extracted or text)
        if repaired and repaired not in candidates:
            candidates.append(repaired)

        return candidates

    def _extract_outer_json_object(self, text: str) -> str | None:
        start = text.find("{")
        end = text.rfind("}")
        if start == -1 or end == -1 or end <= start:
            return None
        return text[start : end + 1].strip()

    def _repair_common_json_issues(self, text: str) -> str | None:
        import re

        candidate = text.strip()
        if not candidate:
            return None

        candidate = candidate.replace("\ufeff", "")
        candidate = candidate.replace("“", '"').replace("”", '"')
        candidate = candidate.replace("‘", '"').replace("’", '"')
        candidate = re.sub(r",(\s*[}\]])", r"\1", candidate)
        candidate = re.sub(r"[\x00-\x08\x0B\x0C\x0E-\x1F]", "", candidate)
        return candidate

    def _build_ollama_prompt(self, request: CanonicalCommandPredictionRequest) -> str:
        return f"""
You are a command canonicalization engine for a desktop accessibility agent.

Return only valid JSON with this exact schema:
{{
  "normalized_text": "string",
  "task_domain": "web" | "desktop" | "hybrid",
  "intent": "string",
  "target_app": "string or null",
  "notes": ["string", "..."]
}}

Rules:
- Use "web" for browser search, reading, or navigation.
- Use "desktop" for Notepad, Windows settings, or local app/system actions.
- Use "hybrid" only when both browser and desktop are clearly needed.
- For dark mode changes, use intent "change_system_setting" and target_app "windows_settings".
- For Notepad writing, use intent "open_notepad_and_type" and target_app "notepad".
- For Naver or browser search, use intent "search_and_read" and target_app "browser".
- For Naver Map route requests, use intent "find_map_route" and target_app "naver_map".
- Keep normalized_text concise and task-oriented.
- notes should include "ollama_qwen2_5_14b".

input_mode: {request.input_mode}
raw_text: {request.raw_text}
normalized_text_candidate: {request.normalized_text}
""".strip()

    def build_canonicalization_debug_payload(
        self,
        request: CanonicalCommandPredictionRequest,
    ) -> dict[str, object]:
        payload: dict[str, object] = {
            "provider": self.settings.model_provider,
            "enabled": self.is_enabled(),
            "request": request.model_dump(),
        }
        if self.settings.model_provider == "ollama":
            payload["model"] = self.settings.ollama_model
            payload["prompt"] = self._build_ollama_prompt(request)
        elif self.settings.model_api_url:
            payload["model_api_url"] = self.settings.model_api_url
        return payload

    def _build_vision_observation_prompt(self, request: VisionObservationRequest) -> str:
        import json

        return f"""
You are a visual runtime observer for a Windows accessibility agent.

Return only valid JSON with this exact schema:
{{
  "summary": "string",
  "task_state": "string",
  "recommended_action": "string or null",
  "confidence": 0.0,
  "notes": ["string", "..."]
}}

Rules:
- Look at the screenshot together with the structured observation.
- Summarize only what is relevant to the current task.
- For map route tasks, identify whether the page is currently in route entry, suggestion selection, route results visible, blocked, or ambiguous state.
- If the screenshot already shows route results for the user's requested mode or route kind, say so in task_state.
- Do not invent hidden UI state that is not visible.
- Keep summary concise and concrete.
- notes should include "ollama_vision_observer".

command:
{request.command.model_dump_json(indent=2)}

observation:
{json.dumps(request.observation, ensure_ascii=False, indent=2)}
""".strip()

    def _build_action_plan_prompt(self, request: ActionPlanRequest) -> str:
        import json

        return f"""
You are an action planner for a Windows accessibility agent.

Return only valid JSON with this exact schema:
{{
  "steps": [
    {{
      "action": "observe_windows" | "open_app" | "focus_window" | "type_text" | "save_file" | "verify_file_contains_text" | "set_dark_mode" | "open_browser_url" | "search_web" | "extract_top_result" | "click_search_result" | "click_element" | "fill_input" | "submit_form" | "scroll_page" | "wait_for_element" | "switch_tab" | "close_tab" | "summarize_page" | "read_page_summary" | "read_linked_page" | "read_section" | "verify_page_loaded" | "switch_window" | "click_ui_element" | "open_explorer" | "list_directory" | "select_file" | "create_folder" | "move_file",
      "target": "string or null",
      "text": "string or null",
      "path_hint": "string or null",
      "expected_text": "string or null",
      "reasoning": "short string or null",
      "metadata": {{}}
    }}
  ],
  "notes": ["string", "..."]
}}

Rules:
- Prefer short deterministic plans.
- For Notepad writing, use steps that open Notepad, focus it, type text, save, and verify file contents.
- For browser search and reading, use steps that search the web, verify the page, extract the top result, optionally click the result, and read a concise summary from either the result card or the linked page.
- For Naver Map route tasks, prefer opening Naver Map directions, filling the origin and destination inputs, and submitting the route request instead of using a portal search result page.
- For search_web, set target to the most appropriate engine or site such as naver, google, or youtube based on the user's command and the observation context.
- For general browser tasks, use steps such as open_browser_url, click_element, fill_input, submit_form, scroll_page, wait_for_element, switch_tab, close_tab, summarize_page, and read_section when a selector or URL is explicit enough to execute safely.
- If the command names a site directly, prefer opening or searching that site instead of defaulting to Naver.
- For YouTube lookup tasks, prefer target "youtube" and avoid unnecessary intermediate search engines.
- If the result card already contains enough information, prefer read_page_summary or summarize_page over clicking through.
- If a result URL looks like a download or PDF link, prefer summarize_page or read_page_summary fallback behavior instead of assuming rich page navigation.
- Use switch_tab only when a new tab is likely or explicitly requested.
- Use wait_for_element before clicking or reading when the page may need extra time to stabilize.
- For desktop file organization tasks, use steps such as open_explorer, list_directory, select_file, create_folder, and move_file only when the target paths are explicit and safe.
- For dark mode changes, use "set_dark_mode".
- Do not invent unavailable apps or tools.
- If observation already shows a relevant Notepad window, you may skip "open_app" and start with "focus_window".
- notes should include "ollama_action_planner".

command:
{request.command.model_dump_json(indent=2)}

observation:
{json.dumps(request.observation, ensure_ascii=False, indent=2)}

prior_steps:
{json.dumps(request.prior_steps, ensure_ascii=False, indent=2)}

last_result:
{json.dumps(request.last_result, ensure_ascii=False, indent=2) if request.last_result is not None else "null"}
""".strip()

    def _build_popup_summary_prompt(self, request: PopupSummaryRequest) -> str:
        import json

        language_name = "Korean" if request.language == "ko" else "Japanese"
        return f"""
You create a short popup notification for a desktop accessibility assistant.

Return only valid JSON with this exact schema:
{{
  "title": "string",
  "message": "string",
  "notes": ["string", "..."]
}}

Rules:
- Write naturally in {language_name}.
- The title should be short, warm, and appropriate for a popup.
- The message should be 1 sentence, concise but helpful.
- Use the popup_context as the primary source of truth.
- If route duration, fare, or result title is available, you may mention it naturally.
- Do not invent facts that are not present in popup_context.
- Do not output Chinese unless the requested language is Chinese, which it is not.
- Prefer user-facing phrasing over technical phrasing.
- notes should include "ollama_popup_summary".

command:
{request.command.model_dump_json(indent=2)}

popup_context:
{json.dumps(request.popup_context, ensure_ascii=False, indent=2)}

result:
{json.dumps(request.result, ensure_ascii=False, indent=2)}
""".strip()

    def build_action_plan_debug_payload(self, request: ActionPlanRequest) -> dict[str, object]:
        payload: dict[str, object] = {
            "provider": self.settings.model_provider,
            "enabled": self.is_enabled(),
            "request": request.model_dump(),
        }
        if self.settings.model_provider == "ollama":
            payload["model"] = self.settings.ollama_planner_model
            payload["prompt"] = self._build_action_plan_prompt(request)
        return payload

    def build_vision_observation_debug_payload(self, request: VisionObservationRequest) -> dict[str, object]:
        payload: dict[str, object] = {
            "provider": self.settings.model_provider,
            "enabled": self.is_enabled() and self.settings.ollama_vision_enabled,
            "request": request.model_dump(),
        }
        if self.settings.model_provider == "ollama":
            payload["model"] = self.settings.ollama_vision_model
            payload["prompt"] = self._build_vision_observation_prompt(request)
        return payload

    def _build_next_action_prompt(self, request: NextActionRequest) -> str:
        import json

        return f"""
You are a runtime decision module for a Windows accessibility agent.

Return only valid JSON with this exact schema:
{{
  "step": {{
    "action": "observe_windows" | "open_app" | "focus_window" | "type_text" | "save_file" | "verify_file_contains_text" | "set_dark_mode" | "open_browser_url" | "search_web" | "extract_top_result" | "click_search_result" | "click_element" | "fill_input" | "submit_form" | "scroll_page" | "wait_for_element" | "switch_tab" | "close_tab" | "summarize_page" | "read_page_summary" | "read_linked_page" | "read_section" | "verify_page_loaded" | "switch_window" | "click_ui_element" | "open_explorer" | "list_directory" | "select_file" | "create_folder" | "move_file",
    "target": "string or null",
    "text": "string or null",
    "path_hint": "string or null",
    "expected_text": "string or null",
    "reasoning": "short string or null",
    "metadata": {{}}
  }} | null,
  "done": true | false,
  "needs_recovery": true | false,
  "choice_reason": "string or null",
  "completion_reason": "string or null",
  "notes": ["string", "..."]
}}

Rules:
- Choose only the single best next action, not a full plan.
- Use the latest observation and candidate targets as the primary basis for your decision.
- Prefer referencing candidate IDs or selector hints already present in the candidate list rather than inventing new selectors.
- Use observation.progress_state and observation.suggested_next_step as strong hints when they are present, unless the page state clearly indicates a better action.
- Field rules:
- For "open_browser_url", put the URL in "target". Do not put the URL in "text".
- For "search_web", put the engine or site in "target" and the search query in "text".
- For "fill_input", put the selector hint or candidate ID in "target" and the input value in "text".
- For "click_element" and "wait_for_element", put the selector hint or candidate ID in "target".
- For "read_page_summary", "summarize_page", and "read_linked_page", prefer leaving "text" null unless new text input is truly needed.
- Set "done" to true only when the user goal appears completed.
- Set "needs_recovery" to true when the current path looks blocked or repeated retries are likely.
- If the page already contains enough information, prefer reading or summarizing over extra navigation.
- For generic "search and read" requests, prefer staying on the search results page and using "read_page_summary" first.
- Only click through to a linked page when the user explicitly asks for details, the full article, the original page, the announcement page, or when the result card is clearly insufficient.
- For browser search tasks, prefer actions that move the task toward the user's goal with minimal unnecessary steps.
- For map route tasks, prefer actions that move from route entry toward visible route results.
- If the command explicitly names Naver Map or Kakao Map, stay on that provider unless the observation clearly proves the provider is unavailable.
- For map route tasks, treat origin, destination, route mode, and route kind as separate fields. Do not put words like "버스 경로", "지하철 경로", or "가는 경로" into the destination input.
- For map route tasks, if one route input is already filled correctly, prefer filling only the missing field instead of restarting from the beginning.
- For map route tasks, when visible route results already match the requested route kind, prefer marking the task done instead of reopening or resubmitting the route form.
- Progress heuristics:
- If progress_state is "initial", prefer "open_browser_url" or "search_web".
- If progress_state is "page_opened" or "page_loaded" on a search result page, prefer "extract_top_result", "read_page_summary", or "fill_input" depending on the visible page state.
- If progress_state is "top_result_extracted", prefer "read_page_summary" first for generic read requests, and use "click_search_result" only when the command explicitly calls for deeper navigation.
- If progress_state is "result_clicked", prefer "verify_page_loaded" and then "read_linked_page" or "read_section".
- If progress_state is "form_field_filled", prefer another "fill_input" or "submit_form".
- If progress_state is "route_results_ready", prefer "read_section" or "summarize_page" instead of restarting the search.
- notes should include "ollama_next_action".

command:
{request.command.model_dump_json(indent=2)}

observation:
{json.dumps(request.observation, ensure_ascii=False, indent=2)}

candidate_targets:
{json.dumps([candidate.model_dump() for candidate in request.candidate_targets], ensure_ascii=False, indent=2)}

history:
{json.dumps(request.history, ensure_ascii=False, indent=2)}

last_result:
{json.dumps(request.last_result, ensure_ascii=False, indent=2) if request.last_result is not None else "null"}
""".strip()

    def build_next_action_debug_payload(self, request: NextActionRequest) -> dict[str, object]:
        payload: dict[str, object] = {
            "provider": self.settings.model_provider,
            "enabled": self.is_enabled(),
            "request": request.model_dump(),
        }
        if self.settings.model_provider == "ollama":
            payload["model"] = self.settings.ollama_planner_model
            payload["prompt"] = self._build_next_action_prompt(request)
        return payload
