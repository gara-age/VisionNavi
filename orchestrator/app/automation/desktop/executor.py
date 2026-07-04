from __future__ import annotations

import shutil
import re
import subprocess
import tempfile
import time
from pathlib import Path

from app.models.action_step import ActionStep
from app.core.settings import Settings
from app.models.canonical_command import CanonicalCommand


class DesktopExecutor:
    def __init__(self, settings: Settings | None = None) -> None:
        self.settings = settings or Settings.from_env()

    def execute(self, command: CanonicalCommand) -> dict[str, object]:
        if command.intent == "open_notepad_and_type":
            return self._execute_notepad_flow(command)

        if command.intent == "inspect_workspace_files":
            return self.execute_action_plan(
                command,
                [
                    ActionStep(action="open_explorer", target="workspace"),
                    ActionStep(action="list_directory", target="workspace"),
                ],
            )

        if command.intent == "change_system_setting":
            return self._execute_system_setting_change(command)

        return {
            "status": "stubbed",
            "executor": "desktop",
            "strategy": "uia-first",
            "normalized_text": command.normalized_text,
        }

    def observe(self, command: CanonicalCommand) -> dict[str, object]:
        windows: list[dict[str, object]] = []
        try:
            from pywinauto import Desktop

            for window in Desktop(backend="win32").windows():
                try:
                    title = window.window_text()
                    class_name = window.class_name()
                    if not title and class_name != "Notepad":
                        continue
                    windows.append(
                        {
                            "title": title,
                            "class_name": class_name,
                            "process_id": window.process_id(),
                        }
                    )
                except Exception:
                    continue
        except Exception:
            windows = []

        return {
            "task_domain": command.task_domain,
            "intent": command.intent,
            "notepad_windows": [item for item in windows if item.get("class_name") == "Notepad"],
            "window_count": len(windows),
            "workspace_root": str(self._workspace_root()),
        }

    def execute_action_plan(
        self,
        command: CanonicalCommand,
        steps: list[ActionStep],
    ) -> dict[str, object]:
        context: dict[str, object] = {
            "command": command.normalized_text,
            "intent": command.intent,
            "target_app": command.target_app,
            "artifacts": {},
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
                    "executor": "desktop",
                    "strategy": "llm-action-plan",
                    "failed_step": step.model_dump(),
                    "step_result": step_result,
                    "executed_steps": context["executed_steps"],
                }

        return {
            "status": "success",
            "executor": "desktop",
            "strategy": "llm-action-plan",
            "intent": command.intent,
            "target_app": command.target_app,
            "text": context.get("text"),
            "file_path": context.get("file_path"),
            "observed_text": context.get("observed_text"),
            "folder_path": context.get("folder_path"),
            "directory_entries": context.get("directory_entries"),
            "moved_to_path": context.get("moved_to_path"),
            "executed_steps": context["executed_steps"],
        }

    def execute_action_step(self, step: ActionStep, context: dict[str, object]) -> dict[str, object]:
        if step.action == "observe_windows":
            observation = self.observe(
                CanonicalCommand(
                    input_mode="text",
                    raw_text=str(context.get("command", "")),
                    normalized_text=str(context.get("command", "")),
                    task_domain="desktop",
                    intent=str(context.get("intent", "general_assistance")),
                    risk_level="low",
                    requires_confirmation=False,
                    target_app=context.get("target_app") if isinstance(context.get("target_app"), str) else None,
                )
            )
            context["observation"] = observation
            return {"status": "success", "observation": observation}

        if step.action == "open_app":
            target = (step.target or "").lower()
            if target != "notepad":
                return {"status": "failed", "reason": "unsupported_open_app_target"}

            path_hint = step.path_hint or f"visionnavi-note-{int(time.time() * 1000)}.txt"
            note_path = self._build_note_path(path_hint)
            note_path.write_text("", encoding="utf-8")
            process = subprocess.Popen(["notepad.exe", str(note_path)])
            context["process_id"] = process.pid
            context["file_path"] = str(note_path)
            return {"status": "success", "process_id": process.pid, "file_path": str(note_path)}

        if step.action == "focus_window":
            target = (step.target or "").lower()
            if target != "notepad":
                return {"status": "failed", "reason": "unsupported_focus_target"}
            try:
                window = self._wait_for_any_notepad_window()
                window.set_focus()
                time.sleep(0.2)
                return {"status": "success", "window_title": window.window_text()}
            except Exception as exc:
                return {"status": "failed", "reason": f"desktop_error:{type(exc).__name__}", "detail": str(exc)}

        if step.action == "switch_window":
            target = step.target or "notepad"
            try:
                window = self._wait_for_window_by_target(target)
                window.set_focus()
                time.sleep(0.2)
                return {"status": "success", "window_title": window.window_text()}
            except Exception as exc:
                return {"status": "failed", "reason": f"desktop_error:{type(exc).__name__}", "detail": str(exc)}

        if step.action == "click_ui_element":
            target = (step.target or "").lower()
            if target not in {"notepad_editor", "notepad"}:
                return {"status": "failed", "reason": "unsupported_click_target"}
            try:
                window = self._wait_for_any_notepad_window()
                window.set_focus()
                return {"status": "success", "window_title": window.window_text()}
            except Exception as exc:
                return {"status": "failed", "reason": f"desktop_error:{type(exc).__name__}", "detail": str(exc)}

        if step.action == "open_explorer":
            try:
                folder_path = self._resolve_workspace_directory_hint(step.path_hint or step.target)
                folder_path.mkdir(parents=True, exist_ok=True)
                process_id = self._open_directory_in_explorer(folder_path)
                context["folder_path"] = str(folder_path)
                context["explorer_process_id"] = process_id
                return {"status": "success", "folder_path": str(folder_path), "process_id": process_id}
            except Exception as exc:
                return {"status": "failed", "reason": f"desktop_error:{type(exc).__name__}", "detail": str(exc)}

        if step.action == "list_directory":
            try:
                folder_path = self._resolve_directory_path(step, context)
                entries = sorted(
                    [
                        {
                            "name": child.name,
                            "kind": "directory" if child.is_dir() else "file",
                        }
                        for child in folder_path.iterdir()
                    ],
                    key=lambda item: (item["kind"], item["name"]),
                )
                context["folder_path"] = str(folder_path)
                context["directory_entries"] = entries
                return {"status": "success", "folder_path": str(folder_path), "entries": entries}
            except Exception as exc:
                return {"status": "failed", "reason": f"desktop_error:{type(exc).__name__}", "detail": str(exc)}

        if step.action == "select_file":
            try:
                folder_path = self._resolve_directory_path(step, context)
                query = (step.text or step.target or step.path_hint or "").lower().strip()
                selected_file = None
                for child in sorted(folder_path.iterdir()):
                    if not child.is_file():
                        continue
                    if not query or query in child.name.lower():
                        selected_file = child
                        break
                if selected_file is None:
                    return {"status": "failed", "reason": "file_not_found"}
                context["file_path"] = str(selected_file)
                return {"status": "success", "file_path": str(selected_file)}
            except Exception as exc:
                return {"status": "failed", "reason": f"desktop_error:{type(exc).__name__}", "detail": str(exc)}

        if step.action == "type_text":
            text = step.text or step.expected_text
            if not text:
                return {"status": "failed", "reason": "missing_type_text"}
            previous_clipboard_text = self._get_clipboard_text()
            try:
                from pywinauto.keyboard import send_keys

                window = self._wait_for_any_notepad_window()
                window.set_focus()
                self._set_clipboard_text(text)
                send_keys("^a{BACKSPACE}")
                time.sleep(0.1)
                send_keys("^v")
                context["text"] = text
                return {"status": "success", "text": text}
            except Exception as exc:
                return {"status": "failed", "reason": f"desktop_error:{type(exc).__name__}", "detail": str(exc)}
            finally:
                self._restore_clipboard_text(previous_clipboard_text)

        if step.action == "save_file":
            try:
                from pywinauto.keyboard import send_keys

                window = self._wait_for_any_notepad_window()
                window.set_focus()
                send_keys("^s")
                file_path = context.get("file_path")
                if isinstance(file_path, str):
                    observed_text = self._wait_for_file_text(
                        Path(file_path),
                        expected_text=str(context.get("text", "")),
                    )
                    context["observed_text"] = observed_text
                return {"status": "success", "file_path": context.get("file_path")}
            except Exception as exc:
                return {"status": "failed", "reason": f"desktop_error:{type(exc).__name__}", "detail": str(exc)}

        if step.action == "verify_file_contains_text":
            file_path = context.get("file_path")
            expected_text = step.expected_text or context.get("text")
            if not isinstance(file_path, str) or not expected_text:
                return {"status": "failed", "reason": "missing_verification_context"}
            observed_text = Path(file_path).read_text(encoding="utf-8", errors="ignore")
            context["observed_text"] = observed_text
            if str(expected_text) not in observed_text:
                return {
                    "status": "failed",
                    "reason": "notepad_text_verification_failed",
                    "observed_text": observed_text,
                    "expected_text": expected_text,
                }
            return {"status": "success", "observed_text": observed_text}

        if step.action == "create_folder":
            folder_hint = step.path_hint or step.target or "visionnavi-folder"
            try:
                folder_path = self._build_workspace_path(folder_hint, expect_directory=True)
                folder_path.mkdir(parents=True, exist_ok=True)
                context["folder_path"] = str(folder_path)
                return {"status": "success", "folder_path": str(folder_path)}
            except Exception as exc:
                return {"status": "failed", "reason": f"desktop_error:{type(exc).__name__}", "detail": str(exc)}

        if step.action == "move_file":
            try:
                source_path = self._resolve_source_path(step, context)
                destination_path = self._resolve_destination_path(step, context, source_path)
                destination_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(source_path), str(destination_path))
                context["file_path"] = str(destination_path)
                context["moved_to_path"] = str(destination_path)
                return {
                    "status": "success",
                    "source_path": str(source_path),
                    "destination_path": str(destination_path),
                }
            except Exception as exc:
                return {"status": "failed", "reason": f"desktop_error:{type(exc).__name__}", "detail": str(exc)}

        if step.action == "set_dark_mode":
            try:
                self._set_windows_dark_mode()
                return {"status": "success", "after": self._read_theme_state()}
            except Exception as exc:
                return {"status": "failed", "reason": f"desktop_error:{type(exc).__name__}", "detail": str(exc)}

        return {"status": "failed", "reason": "unsupported_action_step"}

    def _execute_notepad_flow(self, command: CanonicalCommand) -> dict[str, object]:
        note_text = self._extract_notepad_text(command.raw_text)
        if not note_text:
            return {
                "status": "failed",
                "executor": "desktop",
                "reason": "empty_notepad_text",
            }

        typed_result = self._type_text_in_notepad(note_text)
        if typed_result.get("status") == "success":
            return typed_result

        fallback_result = self._open_note_file_in_notepad(note_text)
        fallback_result.setdefault("fallback_from", typed_result.get("strategy", "uia-paste-save"))
        if typed_result.get("reason"):
            fallback_result.setdefault("primary_failure", typed_result["reason"])
        return fallback_result

    def _type_text_in_notepad(self, text: str) -> dict[str, object]:
        previous_clipboard_text = self._get_clipboard_text()
        note_path = self._create_note_file("")

        try:
            from pywinauto import Desktop
            from pywinauto.keyboard import send_keys

            process = subprocess.Popen(["notepad.exe", str(note_path)])
            window = self._wait_for_notepad_window(Desktop(backend="win32"), note_path)

            window.set_focus()
            time.sleep(0.35)

            self._set_clipboard_text(text)
            send_keys("^a{BACKSPACE}")
            time.sleep(0.1)
            send_keys("^v")
            time.sleep(0.2)
            send_keys("^s")

            observed_text = self._wait_for_file_text(note_path, expected_text=text)
            if observed_text != text:
                return {
                    "status": "failed",
                    "executor": "desktop",
                    "strategy": "uia-paste-save",
                    "reason": "notepad_text_verification_failed",
                    "text": text,
                    "observed_text": observed_text,
                    "file_path": str(note_path),
                }

            return {
                "status": "success",
                "executor": "desktop",
                "strategy": "uia-paste-save",
                "intent": "open_notepad_and_type",
                "target_app": "notepad",
                "text": text,
                "process_id": process.pid,
                "file_path": str(note_path),
                "observed_text": observed_text,
            }
        except Exception as exc:
            return {
                "status": "failed",
                "executor": "desktop",
                "strategy": "uia-paste-save",
                "reason": f"desktop_error:{type(exc).__name__}",
                "detail": str(exc),
                "text": text,
                "file_path": str(note_path),
            }
        finally:
            self._restore_clipboard_text(previous_clipboard_text)

    def _open_note_file_in_notepad(self, text: str) -> dict[str, object]:
        try:
            note_path = self._create_note_file(text)
            process = subprocess.Popen(["notepad.exe", str(note_path)])
            observed_text = note_path.read_text(encoding="utf-8")

            if text != observed_text:
                return {
                    "status": "failed",
                    "executor": "desktop",
                    "strategy": "file-open-first",
                    "reason": "notepad_text_verification_failed",
                    "text": text,
                    "observed_text": observed_text,
                    "file_path": str(note_path),
                }

            return {
                "status": "success",
                "executor": "desktop",
                "strategy": "file-open-first",
                "intent": "open_notepad_and_type",
                "target_app": "notepad",
                "text": text,
                "process_id": process.pid,
                "file_path": str(note_path),
                "observed_text": observed_text,
            }
        except Exception as exc:
            return {
                "status": "failed",
                "executor": "desktop",
                "strategy": "file-open-first",
                "reason": f"desktop_error:{type(exc).__name__}",
                "detail": str(exc),
                "text": text,
            }

    def _create_note_file(self, text: str) -> Path:
        target_dir = Path(tempfile.gettempdir()) / "visionnavi-notes"
        target_dir.mkdir(parents=True, exist_ok=True)
        note_path = target_dir / f"visionnavi-note-{int(time.time() * 1000)}.txt"
        note_path.write_text(text, encoding="utf-8")
        return note_path

    def _build_note_path(self, path_hint: str) -> Path:
        target_dir = Path(tempfile.gettempdir()) / "visionnavi-notes"
        target_dir.mkdir(parents=True, exist_ok=True)
        safe_name = re.sub(r"[^a-zA-Z0-9._-]+", "-", path_hint).strip("-") or "visionnavi-note"
        if not safe_name.lower().endswith(".txt"):
            safe_name = f"{safe_name}.txt"
        return target_dir / safe_name

    def _workspace_root(self) -> Path:
        root = Path(tempfile.gettempdir()) / "visionnavi-workspace"
        root.mkdir(parents=True, exist_ok=True)
        return root

    def _build_workspace_path(self, path_hint: str, expect_directory: bool = False) -> Path:
        safe_hint = path_hint.replace("\\", "/").strip().strip("/")
        safe_parts = [re.sub(r"[^a-zA-Z0-9._-]+", "-", part).strip("-") for part in safe_hint.split("/") if part]
        safe_parts = [part for part in safe_parts if part]
        if not safe_parts:
            safe_parts = ["visionnavi-item"]
        candidate = self._workspace_root().joinpath(*safe_parts)
        if expect_directory:
            return candidate
        if candidate.suffix:
            return candidate
        return candidate.with_suffix(".txt")

    def _resolve_directory_path(self, step: ActionStep, context: dict[str, object]) -> Path:
        folder_hint = step.path_hint or step.target
        if isinstance(folder_hint, str) and folder_hint:
            folder_path = self._resolve_workspace_directory_hint(folder_hint)
        elif isinstance(context.get("folder_path"), str):
            folder_path = Path(str(context["folder_path"]))
        else:
            folder_path = self._workspace_root()
        folder_path.mkdir(parents=True, exist_ok=True)
        return folder_path

    def _resolve_workspace_directory_hint(self, folder_hint: str | None) -> Path:
        normalized_hint = (folder_hint or "").strip().lower()
        if normalized_hint in {"", "workspace", "visionnavi workspace"}:
            return self._workspace_root()
        return self._build_workspace_path(folder_hint or "visionnavi-item", expect_directory=True)

    def _extract_notepad_text(self, raw_text: str) -> str:
        patterns = [
            r'open notepad and type exactly "(.+?)"(?:,?\s*then save(?: the file)?)?[.!]?$',
            r"open notepad and type exactly (.+?)(?:,?\s*then save(?: the file)?)?[.!]?$",
            r"open notepad and type (.+)",
            r"open notepad and write (.+)",
            r"open notepad then type (.+)",
            r"메모장을 열고 (.+?)(?:를|을)? 입력(?:해|해줘)?",
            r"메모장을 열고 (.+?)(?:를|을)? 작성(?:해|해줘)?",
            r"메모장에 (.+?)(?:를|을)? 입력(?:해|해줘)?",
        ]

        for pattern in patterns:
            match = re.search(pattern, raw_text, flags=re.IGNORECASE)
            if match:
                extracted = match.group(1).strip(" .")
                if extracted:
                    return extracted

        return raw_text.strip()

    def _extract_theme_request(self, text: str) -> str | None:
        lowered = text.lower()
        if any(keyword in lowered for keyword in ["dark mode", "dark theme", "다크 모드", "다크모드"]):
            return "dark"
        return None

    def _wait_for_notepad_window(self, desktop, note_path: Path):  # noqa: ANN001
        deadline = time.time() + self.settings.desktop_app_timeout_s
        targets = (note_path.name.lower(), note_path.stem.lower())

        while time.time() < deadline:
            for window in desktop.windows():
                try:
                    if window.class_name() != "Notepad":
                        continue
                    title = window.window_text().lower()
                    if any(target in title for target in targets):
                        return window
                except Exception:
                    continue
            time.sleep(0.25)

        for window in desktop.windows():
            try:
                if window.class_name() == "Notepad":
                    return window
            except Exception:
                continue

        raise TimeoutError("Timed out waiting for a Notepad window")

    def _wait_for_any_notepad_window(self):
        from pywinauto import Desktop

        deadline = time.time() + self.settings.desktop_app_timeout_s
        while time.time() < deadline:
            for window in Desktop(backend="win32").windows():
                try:
                    if window.class_name() == "Notepad":
                        return window
                except Exception:
                    continue
            time.sleep(0.2)

        raise TimeoutError("Timed out waiting for any Notepad window")

    def _wait_for_window_by_target(self, target: str):
        from pywinauto import Desktop

        lowered_target = target.lower()
        deadline = time.time() + self.settings.desktop_app_timeout_s
        while time.time() < deadline:
            for window in Desktop(backend="win32").windows():
                try:
                    title = window.window_text().lower()
                    class_name = window.class_name().lower()
                    if lowered_target in {class_name, title} or lowered_target in title:
                        return window
                    if lowered_target == "notepad" and class_name == "notepad":
                        return window
                except Exception:
                    continue
            time.sleep(0.2)

        raise TimeoutError(f"Timed out waiting for window target '{target}'")

    def _resolve_source_path(self, step: ActionStep, context: dict[str, object]) -> Path:
        source_hint = step.metadata.get("source_path") if isinstance(step.metadata, dict) else None
        candidate = source_hint or context.get("file_path")
        if not isinstance(candidate, str) or not candidate:
            raise ValueError("missing_source_path")
        source_path = Path(candidate)
        if not source_path.exists():
            raise FileNotFoundError(candidate)
        return source_path

    def _resolve_destination_path(
        self,
        step: ActionStep,
        context: dict[str, object],
        source_path: Path,
    ) -> Path:
        destination_hint = None
        if isinstance(step.metadata, dict):
            destination_hint = step.metadata.get("destination_path") or step.metadata.get("destination_folder")
        if isinstance(destination_hint, str) and destination_hint:
            destination = self._build_workspace_path(destination_hint)
        elif isinstance(context.get("folder_path"), str):
            destination = Path(str(context["folder_path"])) / source_path.name
        elif step.path_hint:
            destination = self._build_workspace_path(step.path_hint)
        else:
            destination = self._workspace_root() / source_path.name
        return destination

    def _wait_for_file_text(self, note_path: Path, expected_text: str) -> str:
        deadline = time.time() + self.settings.desktop_app_timeout_s
        observed_text = ""

        while time.time() < deadline:
            observed_text = note_path.read_text(encoding="utf-8", errors="ignore")
            if observed_text == expected_text:
                return observed_text
            time.sleep(0.2)

        return observed_text

    def _open_directory_in_explorer(self, folder_path: Path) -> int | None:
        existing_handles = self._explorer_window_handles()
        command = ["explorer.exe", "/n,", str(folder_path)]
        process = subprocess.Popen(command)
        opened_handle = self._wait_for_new_explorer_window(existing_handles)
        if opened_handle is None:
            raise RuntimeError("explorer_window_not_detected")
        return process.pid

    def _explorer_window_handles(self) -> set[int]:
        try:
            from pywinauto import Desktop

            handles: set[int] = set()
            for window in Desktop(backend="win32").windows():
                try:
                    class_name = window.class_name()
                except Exception:
                    continue
                if class_name in {"CabinetWClass", "ExploreWClass"}:
                    handles.add(int(window.handle))
            return handles
        except Exception:
            return set()

    def _wait_for_new_explorer_window(self, existing_handles: set[int], timeout_s: float = 4.0) -> int | None:
        deadline = time.time() + timeout_s
        while time.time() < deadline:
            current_handles = self._explorer_window_handles()
            new_handles = current_handles - existing_handles
            if new_handles:
                return next(iter(new_handles))
            time.sleep(0.2)
        return None

    def _get_clipboard_text(self) -> str | None:
        import win32clipboard

        for _ in range(5):
            try:
                win32clipboard.OpenClipboard()
                try:
                    if win32clipboard.IsClipboardFormatAvailable(win32clipboard.CF_UNICODETEXT):
                        return str(win32clipboard.GetClipboardData(win32clipboard.CF_UNICODETEXT))
                    return None
                finally:
                    win32clipboard.CloseClipboard()
            except Exception:
                time.sleep(0.05)
        return None

    def _set_clipboard_text(self, text: str) -> None:
        import win32clipboard

        for _ in range(5):
            try:
                win32clipboard.OpenClipboard()
                try:
                    win32clipboard.EmptyClipboard()
                    win32clipboard.SetClipboardText(text, win32clipboard.CF_UNICODETEXT)
                    return
                finally:
                    win32clipboard.CloseClipboard()
            except Exception:
                time.sleep(0.05)

        raise TimeoutError("Timed out setting clipboard text")

    def _restore_clipboard_text(self, previous_clipboard_text: str | None) -> None:
        if previous_clipboard_text is None:
            return
        try:
            self._set_clipboard_text(previous_clipboard_text)
        except Exception:
            return

    def _read_theme_state(self) -> dict[str, object]:
        import winreg

        key_path = r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, key_path) as key:
            apps_value = winreg.QueryValueEx(key, "AppsUseLightTheme")[0]
            system_value = winreg.QueryValueEx(key, "SystemUsesLightTheme")[0]

        return {
            "apps_use_light_theme": int(apps_value),
            "system_uses_light_theme": int(system_value),
            "is_dark_mode": int(apps_value) == 0 and int(system_value) == 0,
        }

    def _execute_system_setting_change(self, command: CanonicalCommand) -> dict[str, object]:
        requested_theme = self._extract_theme_request(command.normalized_text)
        if requested_theme != "dark":
            return {
                "status": "failed",
                "executor": "desktop",
                "reason": "unsupported_system_setting_request",
                "normalized_text": command.normalized_text,
            }

        try:
            previous_state = self._read_theme_state()
            self._set_windows_dark_mode()
            current_state = self._read_theme_state()

            if not current_state["is_dark_mode"]:
                return {
                    "status": "failed",
                    "executor": "desktop",
                    "reason": "dark_mode_verification_failed",
                    "before": previous_state,
                    "after": current_state,
                }

            return {
                "status": "success",
                "executor": "desktop",
                "strategy": "registry-first",
                "intent": command.intent,
                "target_app": "windows_settings",
                "setting": "dark_mode",
                "before": previous_state,
                "after": current_state,
            }
        except Exception as exc:
            return {
                "status": "failed",
                "executor": "desktop",
                "reason": f"desktop_error:{type(exc).__name__}",
                "detail": str(exc),
                "normalized_text": command.normalized_text,
            }

    def _set_windows_dark_mode(self) -> None:
        import ctypes
        import winreg

        key_path = r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, key_path) as key:
            winreg.SetValueEx(key, "AppsUseLightTheme", 0, winreg.REG_DWORD, 0)
            winreg.SetValueEx(key, "SystemUsesLightTheme", 0, winreg.REG_DWORD, 0)

        HWND_BROADCAST = 0xFFFF
        WM_SETTINGCHANGE = 0x001A
        SMTO_ABORTIFHUNG = 0x0002
        ctypes.windll.user32.SendMessageTimeoutW(
            HWND_BROADCAST,
            WM_SETTINGCHANGE,
            0,
            "ImmersiveColorSet",
            SMTO_ABORTIFHUNG,
            5000,
            0,
        )
