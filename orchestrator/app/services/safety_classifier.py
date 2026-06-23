class SafetyClassifier:
    HIGH_RISK_KEYWORDS = (
        "delete",
        "payment",
        "login",
        "send",
        "post",
        "personal",
        "account",
        "transfer",
    )
    MEDIUM_RISK_KEYWORDS = (
        "settings",
        "change",
        "move",
        "launch",
        "theme",
        "system",
        "window",
    )

    def classify(self, intent: str, normalized_text: str) -> str:
        lowered = normalized_text.lower()

        if any(keyword in lowered for keyword in self.HIGH_RISK_KEYWORDS):
            return "high"

        if intent == "change_system_setting":
            return "medium"

        if any(keyword in lowered for keyword in self.MEDIUM_RISK_KEYWORDS):
            return "medium"

        return "low"

    def requires_confirmation(self, intent: str, risk_level: str, normalized_text: str) -> bool:
        lowered = normalized_text.lower()

        if risk_level == "high":
            return True

        # Dark mode is reversible and approved for one-click execution in the MVP.
        if intent == "change_system_setting" and any(
            keyword in lowered for keyword in ["dark mode", "dark theme", "다크모드", "다크 모드"]
        ):
            return False

        if risk_level == "medium":
            return True

        return False
