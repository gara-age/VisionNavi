from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.core.settings import Settings
from app.services.wakeword_service import WakeWordService


def test_resolve_profile_by_phrase(tmp_path: Path) -> None:
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(
        json.dumps(
            {
                "profiles": [
                    {
                        "id": "ko_nabiya",
                        "language": "ko",
                        "phrase": "나비야",
                        "model_path": str(tmp_path / "ko_nabiya_dev.onnx"),
                    }
                ]
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    service = WakeWordService(
        Settings(
            wakeword_manifest_path=str(manifest_path),
        )
    )

    profile = service._resolve_profile(language="ko", phrase="나비야", profile_id=None)

    assert profile.profile_id == "ko_nabiya"
    assert profile.language == "ko"


def test_resolve_profile_by_language_default(tmp_path: Path) -> None:
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(
        json.dumps(
            {
                "profiles": [
                    {
                        "id": "ja_nee_navi",
                        "language": "ja",
                        "phrase": "ねえ、ナビ",
                        "model_path": str(tmp_path / "ja_nee_navi_dev.onnx"),
                    }
                ]
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    service = WakeWordService(
        Settings(
            wakeword_manifest_path=str(manifest_path),
        )
    )

    profile = service._resolve_profile(language="ja", phrase=None, profile_id=None)

    assert profile.profile_id == "ja_nee_navi"
    assert profile.phrase == "ねえ、ナビ"


def test_resolve_profile_by_profile_id(tmp_path: Path) -> None:
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(
        json.dumps(
            {
                "profiles": [
                    {
                        "id": "ko_nabiya",
                        "language": "ko",
                        "phrase": "나비야",
                        "model_path": str(tmp_path / "ko_nabiya_dev.onnx"),
                    },
                    {
                        "id": "ko_hey_nabi",
                        "language": "ko",
                        "phrase": "헤이 나비",
                        "model_path": str(tmp_path / "ko_hey_nabi_dev.onnx"),
                    },
                ]
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    service = WakeWordService(
        Settings(
            wakeword_manifest_path=str(manifest_path),
        )
    )

    profile = service._resolve_profile(
        language="ko",
        phrase=None,
        profile_id="ko_hey_nabi",
    )

    assert profile.profile_id == "ko_hey_nabi"
    assert profile.phrase == "헤이 나비"


def test_missing_manifest_raises(tmp_path: Path) -> None:
    service = WakeWordService(
        Settings(
            wakeword_manifest_path=str(tmp_path / "missing.json"),
        )
    )

    with pytest.raises(FileNotFoundError):
        service._load_profiles()
