from __future__ import annotations

from app.core.settings import Settings
from app.models.model_api import (
    ActionPlanRequest,
    ActionPlanResponse,
    CanonicalCommandPredictionRequest,
    CanonicalCommandPredictionResponse,
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
        import json

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
        return ActionPlanResponse.model_validate(json.loads(raw_response))

    def _predict_with_ollama(
        self, request: CanonicalCommandPredictionRequest
    ) -> CanonicalCommandPredictionResponse:
        import httpx
        import json

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
        return CanonicalCommandPredictionResponse.model_validate(json.loads(raw_response))

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
- Keep normalized_text concise and task-oriented.
- notes should include "ollama_qwen2_5_14b".

input_mode: {request.input_mode}
raw_text: {request.raw_text}
normalized_text_candidate: {request.normalized_text}
""".strip()

    def _build_action_plan_prompt(self, request: ActionPlanRequest) -> str:
        import json

        return f"""
You are an action planner for a Windows accessibility agent.

Return only valid JSON with this exact schema:
{{
  "steps": [
    {{
      "action": "observe_windows" | "open_app" | "focus_window" | "type_text" | "save_file" | "verify_file_contains_text" | "set_dark_mode" | "open_browser_url" | "search_web" | "extract_top_result" | "click_search_result" | "read_page_summary" | "read_linked_page" | "verify_page_loaded" | "switch_window" | "click_ui_element" | "open_explorer" | "list_directory" | "select_file" | "create_folder" | "move_file",
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
