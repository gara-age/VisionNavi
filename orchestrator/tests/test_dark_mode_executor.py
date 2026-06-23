from app.automation.desktop.executor import DesktopExecutor
from app.models.canonical_command import CanonicalCommand


def test_extract_dark_mode_request_from_korean_prompt() -> None:
    executor = DesktopExecutor()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="윈도우를 다크모드로 바꿔줘",
        normalized_text="윈도우를 다크모드로 바꿔줘",
        task_domain="desktop",
        intent="change_system_setting",
        risk_level="medium",
        requires_confirmation=False,
    )

    assert executor._extract_theme_request(command.normalized_text) == "dark"
