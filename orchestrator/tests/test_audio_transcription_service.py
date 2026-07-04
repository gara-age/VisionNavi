from pathlib import Path

from app.services.audio_transcription_service import AudioTranscriptionService


def test_resolve_input_path_keeps_windows_path() -> None:
    resolved = AudioTranscriptionService._resolve_input_path(  # noqa: SLF001
        r"C:\Users\USER\Desktop\sample.mp3"
    )

    assert resolved == Path(r"C:\Users\USER\Desktop\sample.mp3")


def test_resolve_input_path_supports_file_uri() -> None:
    resolved = AudioTranscriptionService._resolve_input_path(  # noqa: SLF001
        "file:///C:/Users/USER/Desktop/sample.mp3"
    )

    assert resolved == Path(r"C:\Users\USER\Desktop\sample.mp3")


def test_should_fallback_to_cpu_for_missing_cublas() -> None:
    should_fallback = AudioTranscriptionService._should_fallback_to_cpu(  # noqa: SLF001
        RuntimeError("Library cublas64_12.dll is not found or cannot be loaded"),
        "auto",
    )

    assert should_fallback is True


def test_should_not_fallback_when_cpu_was_requested() -> None:
    should_fallback = AudioTranscriptionService._should_fallback_to_cpu(  # noqa: SLF001
        RuntimeError("Library cublas64_12.dll is not found or cannot be loaded"),
        "cpu",
    )

    assert should_fallback is False


def test_normalize_language_hint_accepts_language_codes_and_labels() -> None:
    assert AudioTranscriptionService._normalize_language_hint("ko") == "ko"  # noqa: SLF001
    assert AudioTranscriptionService._normalize_language_hint("한국어") == "ko"  # noqa: SLF001
    assert AudioTranscriptionService._normalize_language_hint("Japanese") == "ja"  # noqa: SLF001
    assert AudioTranscriptionService._normalize_language_hint("日本語") == "ja"  # noqa: SLF001
