from pathlib import Path

from app.automation.desktop.executor import DesktopExecutor
from app.models.action_step import ActionStep
from app.models.canonical_command import CanonicalCommand


def _build_notepad_command(raw_text: str = "Open Notepad and type my presentation notes for today.") -> CanonicalCommand:
    return CanonicalCommand(
        input_mode="text",
        raw_text=raw_text,
        normalized_text=raw_text,
        task_domain="desktop",
        intent="open_notepad_and_type",
        risk_level="low",
        requires_confirmation=False,
    )


def test_extract_notepad_text_from_english_prompt() -> None:
    executor = DesktopExecutor()

    result = executor._extract_notepad_text(_build_notepad_command().raw_text)

    assert result == "my presentation notes for today"


def test_extract_notepad_text_from_exact_then_save_prompt() -> None:
    executor = DesktopExecutor()

    result = executor._extract_notepad_text(
        "Open Notepad and type exactly VisionNavi external desktop verification, then save the file."
    )

    assert result == "VisionNavi external desktop verification"


def test_execute_notepad_flow_prefers_uia_automation(monkeypatch) -> None:
    executor = DesktopExecutor()
    command = _build_notepad_command()

    def fake_type_text_in_notepad(text: str) -> dict[str, object]:
        return {
            "status": "success",
            "executor": "desktop",
            "strategy": "uia-paste-save",
            "text": text,
            "file_path": r"C:\temp\visionnavi-note.txt",
        }

    monkeypatch.setattr(executor, "_type_text_in_notepad", fake_type_text_in_notepad)
    monkeypatch.setattr(
        executor,
        "_open_note_file_in_notepad",
        lambda text: {"status": "success", "strategy": "file-open-first", "text": text},
    )

    result = executor.execute(command)

    assert result["status"] == "success"
    assert result["strategy"] == "uia-paste-save"


def test_execute_notepad_flow_falls_back_when_uia_automation_fails(monkeypatch) -> None:
    executor = DesktopExecutor()
    command = _build_notepad_command()

    monkeypatch.setattr(
        executor,
        "_type_text_in_notepad",
        lambda text: {
            "status": "failed",
            "strategy": "uia-paste-save",
            "reason": "desktop_error:TimeoutError",
            "text": text,
        },
    )
    monkeypatch.setattr(
        executor,
        "_open_note_file_in_notepad",
        lambda text: {
            "status": "success",
            "executor": "desktop",
            "strategy": "file-open-first",
            "text": text,
        },
    )

    result = executor.execute(command)

    assert result["status"] == "success"
    assert result["strategy"] == "file-open-first"
    assert result["fallback_from"] == "uia-paste-save"
    assert result["primary_failure"] == "desktop_error:TimeoutError"


def test_execute_action_plan_reports_success(monkeypatch) -> None:
    executor = DesktopExecutor()
    command = _build_notepad_command()
    steps = [
        ActionStep(action="open_app", target="notepad", path_hint="agent-note.txt"),
        ActionStep(action="focus_window", target="notepad"),
        ActionStep(action="type_text", target="notepad", text="hello agent"),
        ActionStep(action="save_file", target="notepad"),
        ActionStep(action="verify_file_contains_text", expected_text="hello agent"),
    ]

    def fake_execute_action_step(step: ActionStep, context: dict[str, object]) -> dict[str, object]:
        if step.action == "open_app":
            context["file_path"] = r"C:\temp\agent-note.txt"
            return {"status": "success"}
        if step.action == "type_text":
            context["text"] = step.text
            return {"status": "success"}
        if step.action == "save_file":
            context["observed_text"] = "hello agent"
            return {"status": "success"}
        if step.action == "verify_file_contains_text":
            return {"status": "success"}
        return {"status": "success"}

    monkeypatch.setattr(executor, "execute_action_step", fake_execute_action_step)

    result = executor.execute_action_plan(command, steps)

    assert result["status"] == "success"
    assert result["strategy"] == "llm-action-plan"
    assert result["file_path"] == r"C:\temp\agent-note.txt"
    assert len(result["executed_steps"]) == 5


def test_create_folder_and_move_file_stay_in_workspace(tmp_path: Path, monkeypatch) -> None:
    executor = DesktopExecutor()
    source_file = tmp_path / "draft.txt"
    source_file.write_text("hello", encoding="utf-8")
    workspace_root = tmp_path / "workspace"
    workspace_root.mkdir()

    monkeypatch.setattr(executor, "_workspace_root", lambda: workspace_root)

    context = {"file_path": str(source_file)}
    create_result = executor.execute_action_step(
        ActionStep(action="create_folder", path_hint="notes/archive"),
        context,
    )
    move_result = executor.execute_action_step(
        ActionStep(action="move_file", metadata={"destination_folder": "notes/archive"}),
        context,
    )

    assert create_result["status"] == "success"
    assert move_result["status"] == "success"
    assert Path(context["moved_to_path"]).exists()
    assert workspace_root in Path(context["moved_to_path"]).parents


def test_execute_workspace_inspection_returns_directory_entries(tmp_path: Path, monkeypatch) -> None:
    executor = DesktopExecutor()
    workspace_root = tmp_path / "workspace"
    workspace_root.mkdir()
    (workspace_root / "draft.txt").write_text("hello", encoding="utf-8")
    (workspace_root / "notes").mkdir()

    monkeypatch.setattr(executor, "_workspace_root", lambda: workspace_root)
    monkeypatch.setattr(
        executor,
        "execute_action_step",
        lambda step, context: (
            context.update({"folder_path": str(workspace_root)})
            or context.update(
                {
                    "directory_entries": [
                        {"name": "notes", "kind": "directory"},
                        {"name": "draft.txt", "kind": "file"},
                    ]
                }
            )
            or {"status": "success"}
        ),
    )

    command = CanonicalCommand(
        input_mode="text",
        raw_text="Open file explorer for the VisionNavi workspace and list files.",
        normalized_text="Open file explorer for the VisionNavi workspace and list files.",
        task_domain="desktop",
        intent="inspect_workspace_files",
        risk_level="low",
        requires_confirmation=False,
        target_app="file_explorer",
    )

    result = executor.execute(command)

    assert result["status"] == "success"
    assert result["folder_path"] == str(workspace_root)
    assert len(result["directory_entries"]) == 2
