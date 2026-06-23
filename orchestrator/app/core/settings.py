import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    browser_headless: bool = True
    browser_timeout_ms: int = 12000
    desktop_app_timeout_s: float = 8.0
    model_api_enabled: bool = False
    model_provider: str = "remote"
    model_api_url: str | None = None
    model_api_key: str | None = None
    model_api_timeout_s: float = 15.0
    ollama_base_url: str = "http://127.0.0.1:11434"
    ollama_model: str = "qwen2.5:14b"
    ollama_planner_model: str = "qwen2.5:7b"
    ollama_planner_temperature: float = 0.0
    ollama_planner_num_predict: int = 512

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            browser_headless=os.getenv("PLAYWRIGHT_HEADLESS", "true").lower() != "false",
            browser_timeout_ms=int(os.getenv("PLAYWRIGHT_TIMEOUT_MS", "12000")),
            desktop_app_timeout_s=float(os.getenv("DESKTOP_APP_TIMEOUT_S", "8")),
            model_api_enabled=os.getenv("MODEL_API_ENABLED", "false").lower() == "true",
            model_provider=os.getenv("MODEL_PROVIDER", "remote").lower(),
            model_api_url=os.getenv("MODEL_API_URL"),
            model_api_key=os.getenv("MODEL_API_KEY"),
            model_api_timeout_s=float(os.getenv("MODEL_API_TIMEOUT_S", "15")),
            ollama_base_url=os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434"),
            ollama_model=os.getenv("OLLAMA_MODEL", "qwen2.5:14b"),
            ollama_planner_model=os.getenv("OLLAMA_PLANNER_MODEL", "qwen2.5:7b"),
            ollama_planner_temperature=float(os.getenv("OLLAMA_PLANNER_TEMPERATURE", "0.0")),
            ollama_planner_num_predict=int(os.getenv("OLLAMA_PLANNER_NUM_PREDICT", "512")),
        )
