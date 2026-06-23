from typing import Any, Literal

from pydantic import BaseModel, Field


class ActionStep(BaseModel):
    action: Literal[
        "observe_windows",
        "open_app",
        "focus_window",
        "type_text",
        "save_file",
        "verify_file_contains_text",
        "set_dark_mode",
        "open_browser_url",
        "search_web",
        "extract_top_result",
        "click_search_result",
        "read_page_summary",
        "read_linked_page",
        "verify_page_loaded",
        "switch_window",
        "click_ui_element",
        "open_explorer",
        "list_directory",
        "select_file",
        "create_folder",
        "move_file",
    ]
    target: str | None = None
    text: str | None = None
    path_hint: str | None = None
    expected_text: str | None = None
    reasoning: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


class ActionPlan(BaseModel):
    steps: list[ActionStep] = Field(default_factory=list)
    notes: list[str] = Field(default_factory=list)
