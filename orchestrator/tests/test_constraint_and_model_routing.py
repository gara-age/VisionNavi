from app.core.settings import Settings
from app.models.canonical_command import CanonicalCommand
from app.models.model_api import CanonicalCommandPredictionRequest
from app.services.command_constraint_service import CommandConstraintService
from app.services.model_client import RemoteModelClient


def test_find_map_route_slot_rewrite_is_reported_separately() -> None:
    service = CommandConstraintService()
    source_text = "Naver Map directions from Seoul Station to Songnae Station by subway"
    constraints = service.build_constraints(
        raw_text=source_text,
        normalized_text=source_text,
        task_domain="web",
        intent="find_map_route",
        target_app="naver_map",
    ).constraints

    changed_command = CanonicalCommand(
        input_mode="text",
        raw_text=source_text,
        normalized_text="Naver Map directions from Seoul Station to Incheon Station by subway",
        preferred_language="en",
        task_domain="web",
        intent="find_map_route",
        risk_level="low",
        requires_confirmation=False,
        target_app="naver_map",
        notes=[],
        constraints=constraints,
    )

    result = service.validate(changed_command)

    assert result.ok is False
    assert "slot_rewritten" in result.violations
    assert result.failure_reason == "slot_rewritten"


def test_canonicalization_debug_payload_uses_korean_default_model() -> None:
    client = RemoteModelClient(
        Settings(
            model_api_enabled=True,
            model_provider="ollama",
            ollama_model="qwen2.5:14b",
            ollama_model_ko="exaone3.5:7.8b",
            ollama_model_ja="dsasai/llama3-elyza-jp-8b",
        )
    )

    payload = client.build_canonicalization_debug_payload(
        CanonicalCommandPredictionRequest(
            input_mode="text",
            raw_text="네이버에서 청년 월세 지원 정보 찾아줘",
            normalized_text="네이버에서 청년 월세 지원 정보 찾아줘",
            preferred_language="ko",
        )
    )

    assert payload["model"] == "exaone3.5:7.8b"


def test_canonicalization_debug_payload_uses_japanese_default_model() -> None:
    client = RemoteModelClient(
        Settings(
            model_api_enabled=True,
            model_provider="ollama",
            ollama_model="qwen2.5:14b",
            ollama_model_ko="exaone3.5:7.8b",
            ollama_model_ja="dsasai/llama3-elyza-jp-8b",
        )
    )

    payload = client.build_canonicalization_debug_payload(
        CanonicalCommandPredictionRequest(
            input_mode="text",
            raw_text="YouTubeで演歌の動画を探して",
            normalized_text="YouTubeで演歌の動画を探して",
            preferred_language="ja",
        )
    )

    assert payload["model"] == "dsasai/llama3-elyza-jp-8b"


def test_explicit_provider_phrase_wins_over_query_keyword() -> None:
    service = CommandConstraintService()

    constraints = service.build_constraints(
        raw_text="구글에서 YouTube 검색 결과 요약해줘",
        normalized_text="구글에서 YouTube 검색 결과 요약해줘",
        preferred_language="ko",
        task_domain="web",
        intent="search_and_read",
        target_app="browser",
    ).constraints

    assert constraints.provider == "google"


def test_language_detection_prefers_hangul_when_brand_name_is_english() -> None:
    service = CommandConstraintService()

    detected = service._detect_language("VisionNavi 검색 결과를 짧게 요약해줘")  # noqa: SLF001

    assert detected == "ko"
