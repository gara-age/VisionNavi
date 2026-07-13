class CommandNormalizer:
    def normalize(self, text: str) -> str:
        normalized = " ".join(text.strip().split())
        return normalized

    def normalize_transcript(
        self,
        text: str,
        *,
        language_hint: str | None = None,
    ) -> str:
        normalized = " ".join(text.strip().split())
        normalized = normalized.replace(" ,", ",").replace(" .", ".")
        normalized = normalized.replace(" !", "!").replace(" ?", "?")
        if language_hint in {"ko", "ja"}:
            normalized = normalized.replace("  ", " ")
        return normalized.strip()
