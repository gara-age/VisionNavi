class CommandNormalizer:
    def normalize(self, text: str) -> str:
        normalized = " ".join(text.strip().split())
        return normalized
