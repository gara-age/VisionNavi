from __future__ import annotations

import re

from app.models.map_route import MapRouteRequest


def detect_map_provider(normalized_text: str) -> str | None:
    text = normalized_text.lower().strip()
    if not text:
        return None
    if "kakao map" in text or "kakaomap" in text or "카카오맵" in normalized_text or "카카오 지도" in normalized_text:
        return "kakao_map"
    if (
        "naver map" in text
        or "네이버지도" in normalized_text
        or "네이버 지도" in normalized_text
        or normalized_text.strip().startswith("네이버")
    ):
        return "naver_map"
    return None


def parse_map_route_request(text: str) -> MapRouteRequest:
    stripped = text.strip()
    lowered = stripped.lower()
    provider = detect_map_provider(stripped) or "unknown_map"

    mode = "transit"
    route_kind = "general"
    if any(token in lowered for token in ["car", "drive", "자동차"]):
        mode = "car"
    elif any(token in lowered for token in ["walk", "walking", "도보"]):
        mode = "walk"
    elif any(token in lowered for token in ["bike", "bicycle", "자전거"]):
        mode = "bike"
    elif any(token in lowered for token in ["지하철", "subway", "metro"]):
        mode = "transit"
        route_kind = "subway"
    elif any(token in lowered for token in ["버스", "bus"]):
        mode = "transit"
        route_kind = "bus"
    elif any(token in lowered for token in ["기차", "train", "rail"]):
        mode = "transit"
        route_kind = "train"

    cleaned = _strip_provider_prefixes(stripped)

    patterns = [
        r"(?P<origin>.+?)\s*(?:에서|from)\s+(?P<destination>.+?)\s*(?:까지|가는|로\s*가는|으로\s*가는)?\s*(?:경로|길찾기|directions|route).*$",
        r"(?:find|show|get)\s+(?:the\s+)?(?:route|directions)\s+from\s+(?P<origin>.+?)\s+to\s+(?P<destination>.+)$",
        r"(?P<origin>.+?)\s*->\s*(?P<destination>.+)$",
    ]
    for pattern in patterns:
        match = re.search(pattern, cleaned, flags=re.IGNORECASE)
        if not match:
            continue
        origin = sanitize_route_endpoint(match.group("origin"), is_destination=False)
        destination = sanitize_route_endpoint(match.group("destination"), is_destination=True)
        if origin and destination:
            return MapRouteRequest(
                provider=provider,
                origin=origin,
                destination=destination,
                mode=mode,
                route_kind=route_kind,
            )

    return MapRouteRequest(
        provider=provider,
        origin="",
        destination=sanitize_route_endpoint(cleaned, is_destination=True),
        mode=mode,
        route_kind=route_kind,
    )


def _strip_provider_prefixes(text: str) -> str:
    cleaned = text.strip()
    patterns = [
        r"^(?:on\s+)?naver\s*map(?:s)?\s+",
        r"^(?:on\s+)?kakao\s*map(?:s)?\s+",
        r"^(?:네이버\s*지도(?:에서|에)?|지도(?:에서|에)?)\s*",
        r"^(?:카카오\s*맵(?:에서|에)?|카카오\s*지도(?:에서|에)?)\s*",
        r"^(?:네이버|카카오맵|카카오|구글)(?:에서|에)?\s*",
    ]
    for pattern in patterns:
        cleaned = re.sub(pattern, "", cleaned, flags=re.IGNORECASE).strip()
    return cleaned


def sanitize_route_endpoint(value: str, *, is_destination: bool) -> str:
    normalized = re.sub(r"\s+", " ", value).strip(" .")
    normalized = re.sub(
        r"(?:찾아줘|찾아주세요|알려줘|알려주세요|보여줘|보여주세요)$",
        "",
        normalized,
        flags=re.IGNORECASE,
    ).strip(" .")
    if is_destination:
        cleanup_patterns = [
            r"(?P<place>.+?)\s*(?:까지)?\s*(?:로\s*)?가는\s*(?:지하철|subway|metro|대중교통|transit|버스|bus|기차|train|자동차|car|도보|walk|자전거|bike)?\s*(?:경로|길찾기)?$",
            r"(?P<place>.+?)\s*(?:지하철|subway|metro|대중교통|transit|버스|bus|기차|train|자동차|car|도보|walk|자전거|bike)\s*(?:경로|길찾기)?$",
            r"(?P<place>.+?)\s*(?:경로|길찾기)$",
        ]
        for pattern in cleanup_patterns:
            match = re.match(pattern, normalized, flags=re.IGNORECASE)
            if match:
                place = match.groupdict().get("place")
                if isinstance(place, str) and place.strip():
                    normalized = place.strip(" .")
                    break
    normalized = re.sub(r"(?:경로|길찾기)\s*$", "", normalized, flags=re.IGNORECASE).strip(" .")
    return normalized
