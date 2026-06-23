class IntentRouter:
    def route(self, normalized_text: str) -> tuple[str, str, str | None]:
        text = normalized_text.lower()

        if any(
            keyword in text
            for keyword in [
                "search",
                "find",
                "naver",
                "browser",
                "read",
                "검색",
                "찾아",
                "찾아줘",
                "네이버",
                "읽어",
            ]
        ):
            return ("web", "search_and_read", "browser")

        if any(
            keyword in text
            for keyword in [
                "explorer",
                "folder",
                "file",
                "workspace",
                "organize",
                "directory",
                "탐색기",
                "폴더",
                "파일",
                "작업공간",
                "디렉토리",
            ]
        ):
            return ("desktop", "inspect_workspace_files", "file_explorer")

        if "notepad" in text or "메모장" in text:
            return ("desktop", "open_notepad_and_type", "notepad")

        if any(
            keyword in text
            for keyword in [
                "dark mode",
                "dark theme",
                "windows",
                "settings",
                "theme",
                "다크모드",
                "다크 모드",
                "윈도우",
                "설정",
                "테마",
            ]
        ):
            return ("desktop", "change_system_setting", "windows_settings")

        return ("hybrid", "general_assistance", None)
