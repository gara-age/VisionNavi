from app.services.map_route_parser import detect_map_provider


class IntentRouter:
    def route(self, normalized_text: str) -> tuple[str, str, str | None]:
        text = normalized_text.lower()

        map_keywords = [
            "naver map",
            "map",
            "directions",
            "route",
            "\ub124\uc774\ubc84 \uc9c0\ub3c4",
            "\uc9c0\ub3c4",
            "\uae38\ucc3e\uae30",
            "\uacbd\ub85c",
        ]
        route_keywords = [
            "from",
            "to",
            "\uc5d0\uc11c",
            "\uae4c\uc9c0",
            "\uac00\ub294",
            "\ucc3e\uc544\uc918",
            "\uc54c\ub824\uc918",
        ]

        web_keywords = [
            "search",
            "find",
            "google",
            "naver",
            "youtube",
            "browser",
            "read",
            "\uac80\uc0c9",
            "\ucc3e\uc544",
            "\uc77d\uc5b4",
            "\uad6c\uae00",
            "\ub124\uc774\ubc84",
            "\uc720\ud29c\ube0c",
            "\ube0c\ub77c\uc6b0\uc800",
        ]
        file_keywords = [
            "explorer",
            "folder",
            "file",
            "workspace",
            "organize",
            "directory",
            "drive",
            "\ud0d0\uc0c9\uae30",
            "\ud3f4\ub354",
            "\ud30c\uc77c",
            "\uc791\uc5c5\uacf5\uac04",
            "\ub514\ub809\ud130\ub9ac",
            "\ub4dc\ub77c\uc774\ube0c",
        ]
        notepad_keywords = ["notepad", "\uba54\ubaa8\uc7a5"]
        setting_keywords = [
            "dark mode",
            "dark theme",
            "windows",
            "settings",
            "theme",
            "\ub2e4\ud06c\ubaa8\ub4dc",
            "\ub2e4\ud06c \ubaa8\ub4dc",
            "\uc124\uc815",
            "\ud14c\ub9c8",
        ]

        if any(keyword in text for keyword in map_keywords) and any(
            keyword in text for keyword in route_keywords
        ):
            return ("web", "find_map_route", detect_map_provider(normalized_text) or "naver_map")

        if any(keyword in text for keyword in web_keywords):
            return ("web", "search_and_read", "browser")

        if any(keyword in text for keyword in file_keywords):
            return ("desktop", "inspect_workspace_files", "file_explorer")

        if any(keyword in text for keyword in notepad_keywords):
            return ("desktop", "open_notepad_and_type", "notepad")

        if any(keyword in text for keyword in setting_keywords):
            return ("desktop", "change_system_setting", "windows_settings")

        return ("hybrid", "general_assistance", None)
