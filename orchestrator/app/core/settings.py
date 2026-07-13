import os
from dataclasses import dataclass

from app.models.execution_backend import ExecutionBackend


@dataclass(frozen=True)
class Settings:
    browser_headless: bool = False
    browser_timeout_ms: int = 12000
    browser_use_cdp: bool = True
    browser_cdp_url: str = "http://127.0.0.1:9222"
    browser_debug_port: int = 9222
    browser_debug_startup_timeout_ms: int = 12000
    browser_debug_profile_dir: str | None = None
    browser_chrome_executable: str | None = None
    desktop_app_timeout_s: float = 8.0
    model_api_enabled: bool = False
    model_provider: str = "remote"
    model_api_url: str | None = None
    model_api_key: str | None = None
    model_api_timeout_s: float = 15.0
    ollama_base_url: str = "http://127.0.0.1:11434"
    ollama_model: str = "qwen2.5:14b"
    ollama_model_ko: str = "exaone3.5:7.8b"
    ollama_model_ja: str = "dsasai/llama3-elyza-jp-8b"
    ollama_planner_model: str = "qwen2.5:7b"
    ollama_planner_model_ko: str = "exaone3.5:7.8b"
    ollama_planner_model_ja: str = "dsasai/llama3-elyza-jp-8b"
    ollama_vision_model: str = "qwen2.5vl:3b"
    ollama_vision_enabled: bool = False
    ollama_vision_num_predict: int = 256
    ollama_planner_temperature: float = 0.0
    ollama_planner_num_predict: int = 512
    iterative_browser_loop_enabled: bool = False
    iterative_browser_max_steps: int = 12
    default_browser_execution_backend: ExecutionBackend = "external_browser_agent"
    default_desktop_execution_backend: ExecutionBackend = "external_desktop_agent"
    external_agent_fallback_to_internal: bool = True
    command_constraint_validation_enabled: bool = True
    command_constraint_repair_enabled: bool = True
    command_constraint_max_repairs: int = 1
    external_browser_cross_provider_fallback_allowed: bool = False
    constraint_enforced_intents: tuple[str, ...] = ("search_and_read", "find_map_route")
    external_browser_agent_model: str = "qwen2.5:7b"
    external_browser_agent_use_vision: bool = False
    external_browser_agent_max_steps: int = 4
    external_browser_agent_step_timeout_s: int = 15
    external_desktop_agent_base_url: str = "http://127.0.0.1:11434/v1"
    external_desktop_agent_api_key: str = "ollama"
    external_desktop_agent_model: str = "qwen2.5vl:3b"
    external_desktop_agent_max_loops: int = 10
    external_desktop_agent_timeout_s: int = 180
    external_desktop_agent_loop_interval_ms: int = 250
    external_desktop_agent_bridge_dir: str = "runtime/external_agents/ui_tars_bridge"
    external_desktop_agent_bridge_script: str = "run_ui_tars.js"
    external_desktop_agent_preopen_notepad: bool = True
    audio_transcription_model: str = "medium"
    audio_transcription_device: str = "auto"
    audio_transcription_compute_type: str = "int8"
    audio_transcription_beam_size: int = 8
    audio_transcription_vad_filter: bool = True
    wakeword_backend: str = "livekit-wakeword"
    wakeword_manifest_path: str = "runtime/wakewords/manifest.json"
    wakeword_threshold: float = 0.5
    wakeword_debounce_seconds: float = 2.0
    wakeword_required_consecutive_hits: int = 2
    tts_provider: str = "edge"
    tts_enabled: bool = True
    tts_output_dir: str = "runtime/tts_output"
    tts_edge_voice_ko: str = "ko-KR-SunHiNeural"
    tts_edge_voice_ja: str = "ja-JP-NanamiNeural"

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            browser_headless=os.getenv("PLAYWRIGHT_HEADLESS", "false").lower() == "true",
            browser_timeout_ms=int(os.getenv("PLAYWRIGHT_TIMEOUT_MS", "12000")),
            browser_use_cdp=os.getenv("PLAYWRIGHT_USE_CDP", "true").lower() == "true",
            browser_cdp_url=os.getenv("PLAYWRIGHT_CDP_URL", "http://127.0.0.1:9222"),
            browser_debug_port=int(os.getenv("PLAYWRIGHT_DEBUG_PORT", "9222")),
            browser_debug_startup_timeout_ms=int(os.getenv("PLAYWRIGHT_DEBUG_STARTUP_TIMEOUT_MS", "12000")),
            browser_debug_profile_dir=os.getenv("PLAYWRIGHT_DEBUG_PROFILE_DIR"),
            browser_chrome_executable=os.getenv("PLAYWRIGHT_CHROME_EXECUTABLE"),
            desktop_app_timeout_s=float(os.getenv("DESKTOP_APP_TIMEOUT_S", "8")),
            model_api_enabled=os.getenv("MODEL_API_ENABLED", "false").lower() == "true",
            model_provider=os.getenv("MODEL_PROVIDER", "remote").lower(),
            model_api_url=os.getenv("MODEL_API_URL"),
            model_api_key=os.getenv("MODEL_API_KEY"),
            model_api_timeout_s=float(os.getenv("MODEL_API_TIMEOUT_S", "15")),
            ollama_base_url=os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434"),
            ollama_model=os.getenv("OLLAMA_MODEL", "qwen2.5:14b"),
            ollama_model_ko=os.getenv("OLLAMA_MODEL_KO", "exaone3.5:7.8b"),
            ollama_model_ja=os.getenv("OLLAMA_MODEL_JA", "dsasai/llama3-elyza-jp-8b"),
            ollama_planner_model=os.getenv("OLLAMA_PLANNER_MODEL", "qwen2.5:7b"),
            ollama_planner_model_ko=os.getenv("OLLAMA_PLANNER_MODEL_KO", "exaone3.5:7.8b"),
            ollama_planner_model_ja=os.getenv("OLLAMA_PLANNER_MODEL_JA", "dsasai/llama3-elyza-jp-8b"),
            ollama_vision_model=os.getenv("OLLAMA_VISION_MODEL", "qwen2.5vl:3b"),
            ollama_vision_enabled=os.getenv("OLLAMA_VISION_ENABLED", "false").lower() == "true",
            ollama_vision_num_predict=int(os.getenv("OLLAMA_VISION_NUM_PREDICT", "256")),
            ollama_planner_temperature=float(os.getenv("OLLAMA_PLANNER_TEMPERATURE", "0.0")),
            ollama_planner_num_predict=int(os.getenv("OLLAMA_PLANNER_NUM_PREDICT", "512")),
            iterative_browser_loop_enabled=os.getenv("ITERATIVE_BROWSER_LOOP_ENABLED", "false").lower() == "true",
            iterative_browser_max_steps=int(os.getenv("ITERATIVE_BROWSER_MAX_STEPS", "12")),
            default_browser_execution_backend=os.getenv("DEFAULT_BROWSER_EXECUTION_BACKEND", "external_browser_agent"),  # type: ignore[arg-type]
            default_desktop_execution_backend=os.getenv("DEFAULT_DESKTOP_EXECUTION_BACKEND", "external_desktop_agent"),  # type: ignore[arg-type]
            external_agent_fallback_to_internal=os.getenv("EXTERNAL_AGENT_FALLBACK_TO_INTERNAL", "true").lower() == "true",
            command_constraint_validation_enabled=os.getenv("COMMAND_CONSTRAINT_VALIDATION_ENABLED", "true").lower() == "true",
            command_constraint_repair_enabled=os.getenv("COMMAND_CONSTRAINT_REPAIR_ENABLED", "true").lower() == "true",
            command_constraint_max_repairs=int(os.getenv("COMMAND_CONSTRAINT_MAX_REPAIRS", "1")),
            external_browser_cross_provider_fallback_allowed=os.getenv("EXTERNAL_BROWSER_CROSS_PROVIDER_FALLBACK_ALLOWED", "false").lower() == "true",
            constraint_enforced_intents=tuple(
                item.strip()
                for item in os.getenv("CONSTRAINT_ENFORCED_INTENTS", "search_and_read,find_map_route").split(",")
                if item.strip()
            ),
            external_browser_agent_model=os.getenv("EXTERNAL_BROWSER_AGENT_MODEL", "qwen2.5:7b"),
            external_browser_agent_use_vision=os.getenv("EXTERNAL_BROWSER_AGENT_USE_VISION", "false").lower() == "true",
            external_browser_agent_max_steps=int(os.getenv("EXTERNAL_BROWSER_AGENT_MAX_STEPS", "4")),
            external_browser_agent_step_timeout_s=int(os.getenv("EXTERNAL_BROWSER_AGENT_STEP_TIMEOUT_S", "15")),
            external_desktop_agent_base_url=os.getenv("EXTERNAL_DESKTOP_AGENT_BASE_URL", "http://127.0.0.1:11434/v1"),
            external_desktop_agent_api_key=os.getenv("EXTERNAL_DESKTOP_AGENT_API_KEY", "ollama"),
            external_desktop_agent_model=os.getenv("EXTERNAL_DESKTOP_AGENT_MODEL", "qwen2.5vl:3b"),
            external_desktop_agent_max_loops=int(os.getenv("EXTERNAL_DESKTOP_AGENT_MAX_LOOPS", "10")),
            external_desktop_agent_timeout_s=int(os.getenv("EXTERNAL_DESKTOP_AGENT_TIMEOUT_S", "180")),
            external_desktop_agent_loop_interval_ms=int(os.getenv("EXTERNAL_DESKTOP_AGENT_LOOP_INTERVAL_MS", "250")),
            external_desktop_agent_bridge_dir=os.getenv("EXTERNAL_DESKTOP_AGENT_BRIDGE_DIR", "runtime/external_agents/ui_tars_bridge"),
            external_desktop_agent_bridge_script=os.getenv("EXTERNAL_DESKTOP_AGENT_BRIDGE_SCRIPT", "run_ui_tars.js"),
            external_desktop_agent_preopen_notepad=os.getenv("EXTERNAL_DESKTOP_AGENT_PREOPEN_NOTEPAD", "true").lower() == "true",
            audio_transcription_model=os.getenv("AUDIO_TRANSCRIPTION_MODEL", "medium"),
            audio_transcription_device=os.getenv("AUDIO_TRANSCRIPTION_DEVICE", "auto"),
            audio_transcription_compute_type=os.getenv("AUDIO_TRANSCRIPTION_COMPUTE_TYPE", "int8"),
            audio_transcription_beam_size=int(os.getenv("AUDIO_TRANSCRIPTION_BEAM_SIZE", "8")),
            audio_transcription_vad_filter=os.getenv("AUDIO_TRANSCRIPTION_VAD_FILTER", "true").lower() == "true",
            wakeword_backend=os.getenv("WAKEWORD_BACKEND", "livekit-wakeword"),
            wakeword_manifest_path=os.getenv("WAKEWORD_MANIFEST_PATH", "runtime/wakewords/manifest.json"),
            wakeword_threshold=float(os.getenv("WAKEWORD_THRESHOLD", "0.5")),
            wakeword_debounce_seconds=float(os.getenv("WAKEWORD_DEBOUNCE_SECONDS", "2.0")),
            wakeword_required_consecutive_hits=max(
                1,
                int(os.getenv("WAKEWORD_REQUIRED_CONSECUTIVE_HITS", "2")),
            ),
            tts_provider=os.getenv("TTS_PROVIDER", "edge").lower(),
            tts_enabled=os.getenv("TTS_ENABLED", "true").lower() == "true",
            tts_output_dir=os.getenv("TTS_OUTPUT_DIR", "runtime/tts_output"),
            tts_edge_voice_ko=os.getenv("TTS_EDGE_VOICE_KO", "ko-KR-SunHiNeural"),
            tts_edge_voice_ja=os.getenv("TTS_EDGE_VOICE_JA", "ja-JP-NanamiNeural"),
        )
