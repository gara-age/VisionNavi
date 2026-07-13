from __future__ import annotations

import re
from dataclasses import dataclass

from app.models.canonical_command import CanonicalCommand
from app.models.command_constraint import CommandConstraint
from app.models.command_constraint import CommandValidationResult
from app.models.command_constraint import RouteConstraintContext
from app.services.map_route_parser import detect_map_provider
from app.services.map_route_parser import parse_map_route_request


@dataclass(frozen=True)
class CommandConstraintBuildResult:
    constraints: CommandConstraint
    trace: dict[str, object]


class CommandConstraintService:
    def build_constraints(
        self,
        *,
        raw_text: str,
        normalized_text: str,
        preferred_language: str | None = None,
        task_domain: str,
        intent: str,
        target_app: str | None,
        source: str = "harmonized",
    ) -> CommandConstraintBuildResult:
        provider = self._extract_provider(normalized_text, task_domain, intent, target_app)
        query_text = self._extract_query_text(normalized_text, intent)
        expected_language = self._detect_language(
            preferred_language or raw_text or normalized_text
        )
        route_context = self._extract_route_context(normalized_text, intent)
        confidence = 0.95 if provider != "unknown" or query_text or route_context is not None else 0.4
        constraints = CommandConstraint(
            provider=provider,
            query_text=query_text,
            expected_language=expected_language,
            allow_provider_switch=False,
            allow_query_rewrite=False,
            allow_language_shift=False,
            allow_cross_provider_fallback=False,
            source="harmonized" if source not in {"rule_extracted", "llm_extracted", "harmonized"} else source,
            confidence=confidence,
            route_context=route_context,
        )
        trace = {
            "provider": provider,
            "query_text": query_text,
            "expected_language": expected_language,
            "route_context": route_context.model_dump() if route_context else None,
            "source": constraints.source,
            "confidence": confidence,
        }
        return CommandConstraintBuildResult(constraints=constraints, trace=trace)

    def validate_and_repair(
        self,
        command: CanonicalCommand,
        *,
        allow_repair: bool = True,
        max_repairs: int = 1,
    ) -> tuple[CanonicalCommand, CommandValidationResult]:
        current = command
        attempts = 0
        validation = self.validate(current)
        while allow_repair and not validation.ok and attempts < max_repairs:
            repaired = self.repair_command(current, validation)
            attempts += 1
            if repaired.model_dump() == current.model_dump():
                validation.attempted_repair = True
                validation.failure_reason = "constraint_repair_failed"
                if "constraint_repair_failed" not in validation.violations:
                    validation.violations.append("constraint_repair_failed")
                break
            current = repaired
            validation = self.validate(current)
            validation.attempted_repair = True
            validation.repaired_command = current.model_dump()
            if validation.ok:
                validation.notes.append("constraint_repair_succeeded")
                break

        if not validation.ok and validation.failure_reason is None:
            validation.failure_reason = validation.violations[0] if validation.violations else "constraint_repair_failed"
        return current, validation

    def validate(self, command: CanonicalCommand) -> CommandValidationResult:
        constraints = command.constraints or self.build_constraints(
            raw_text=command.raw_text,
            normalized_text=command.normalized_text,
            preferred_language=command.preferred_language,
            task_domain=command.task_domain,
            intent=command.intent,
            target_app=command.target_app,
        ).constraints
        detected_provider = self._extract_provider(
            command.normalized_text,
            command.task_domain,
            command.intent,
            command.target_app,
        )
        detected_query = self._extract_query_text(command.normalized_text, command.intent)
        detected_language = self._detect_language(command.raw_text or command.normalized_text)
        violations: list[str] = []

        if constraints.provider != "unknown" and not constraints.allow_provider_switch:
            if detected_provider != constraints.provider:
                violations.append("provider_mismatch")
        if (
            constraints.query_text
            and not constraints.allow_query_rewrite
            and not (command.intent == "find_map_route" and constraints.route_context is not None)
        ):
            if self._normalize_compare_text(detected_query) != self._normalize_compare_text(constraints.query_text):
                violations.append("query_changed")
        if constraints.expected_language != "unknown" and not constraints.allow_language_shift:
            if detected_language != constraints.expected_language:
                violations.append("unexpected_language")
        if command.intent == "find_map_route" and constraints.route_context is not None:
            route_request = parse_map_route_request(command.normalized_text)
            route_origin = self._normalize_compare_text(route_request.origin)
            route_destination = self._normalize_compare_text(route_request.destination)
            route_mode = self._normalize_compare_text(route_request.mode)
            route_kind = self._normalize_compare_text(route_request.route_kind)
            expected_origin = self._normalize_compare_text(constraints.route_context.origin or "")
            expected_destination = self._normalize_compare_text(constraints.route_context.destination or "")
            expected_mode = self._normalize_compare_text(constraints.route_context.transport_mode or "")
            expected_kind = self._normalize_compare_text(constraints.route_context.route_kind or "")
            if expected_origin and route_origin != expected_origin and "slot_rewritten" not in violations:
                violations.append("slot_rewritten")
            if expected_destination and route_destination != expected_destination and "slot_rewritten" not in violations:
                violations.append("slot_rewritten")
            if expected_mode and route_mode != expected_mode and "slot_rewritten" not in violations:
                violations.append("slot_rewritten")
            if expected_kind and route_kind != expected_kind and "slot_rewritten" not in violations:
                violations.append("slot_rewritten")

        failure_reason = None
        if "slot_rewritten" in violations:
            failure_reason = "slot_rewritten"
        elif violations:
            failure_reason = violations[0]

        result = CommandValidationResult(
            ok=not violations,
            detected_provider=detected_provider,
            detected_query=detected_query,
            detected_language=detected_language,
            violations=violations,  # type: ignore[arg-type]
            failure_reason=failure_reason,
        )
        return result

    def repair_command(self, command: CanonicalCommand, validation: CommandValidationResult) -> CanonicalCommand:
        constraints = command.constraints
        if constraints is None:
            return command

        normalized_text = command.normalized_text
        target_app = command.target_app
        repaired_notes = list(command.notes)

        if "provider_mismatch" in validation.violations:
            normalized_text = self._repair_provider_text(normalized_text, constraints.provider, command.intent)
            target_app = self._repair_target_app(constraints.provider, target_app, command.intent)
        if "query_changed" in validation.violations or "slot_rewritten" in validation.violations:
            normalized_text = self._repair_query_text(normalized_text, constraints, command.intent)
        if "unexpected_language" in validation.violations:
            normalized_text = command.raw_text.strip() or normalized_text

        if "constraint_repaired" not in repaired_notes:
            repaired_notes.append("constraint_repaired")

        return command.model_copy(
            update={
                "normalized_text": normalized_text,
                "target_app": target_app,
                "notes": repaired_notes,
            }
        )

    def _extract_provider(self, text: str, task_domain: str, intent: str, target_app: str | None) -> str:
        lowered = text.lower()
        if intent == "find_map_route":
            provider = detect_map_provider(text)
            if provider:
                return provider
            if target_app in {"naver_map", "kakao_map"}:
                return str(target_app)
            return "unknown"
        if task_domain == "desktop":
            return "desktop"
        explicit_provider_patterns = (
            (r"^\s*(?:search\s+google\s+for|search\s+on\s+google|find\s+on\s+google|google\s+for)\b", "google"),
            (r"^\s*(?:search\s+naver\s+for|search\s+on\s+naver|find\s+on\s+naver|naver\s+for)\b", "naver"),
            (r"^\s*(?:search\s+youtube\s+for|search\s+on\s+youtube|find\s+on\s+youtube|youtube\s+for)\b", "youtube"),
            (r"^\s*구글(?:에서)?", "google"),
            (r"^\s*네이버(?:에서)?", "naver"),
            (r"^\s*유튜브(?:에서)?", "youtube"),
        )
        for pattern, provider in explicit_provider_patterns:
            if re.search(pattern, text, flags=re.IGNORECASE):
                return provider
        if "youtube" in lowered or "유튜브" in text:
            return "youtube"
        if "google" in lowered or "구글" in text:
            return "google"
        if "naver" in lowered or "네이버" in text:
            return "naver"
        if target_app == "browser":
            return "browser"
        return "unknown"

    def _extract_query_text(self, text: str, intent: str) -> str:
        stripped = text.strip()
        if intent == "find_map_route":
            route = parse_map_route_request(stripped)
            transport = route.route_kind if route.route_kind and route.route_kind != "general" else route.mode
            return " | ".join(
                [
                    part
                    for part in [route.origin.strip(), route.destination.strip(), (transport or "").strip()]
                    if part
                ]
            )

        lowered = stripped.lower()
        patterns = [
            r"(?:search|find)\s+(?:on\s+)?(?:naver|google|youtube)\s+for\s+(.+?)(?:\s+and\s+read|\s+and\s+summarize)?$",
            r"(?:search|find)\s+for\s+(.+?)(?:\s+on\s+(?:naver|google|youtube))?(?:\s+and\s+read|\s+and\s+summarize)?$",
            r"(?:naver|google|youtube)\s+for\s+(.+?)(?:\s+and\s+read|\s+and\s+summarize)?$",
            r"(.+?)\s+(?:검색해줘|검색해 줘|찾아줘|찾아 줘|읽어줘|읽어 줘|요약해줘|요약해 줘)$",
        ]
        extracted = ""
        for pattern in patterns:
            match = re.search(pattern, stripped, flags=re.IGNORECASE)
            if match:
                extracted = match.group(1).strip(" .")
                break

        if not extracted:
            extracted = stripped

        for token in [
            "네이버에서",
            "구글에서",
            "유튜브에서",
            "Search Naver for",
            "Search Google for",
            "Search YouTube for",
        ]:
            extracted = extracted.replace(token, "").strip()
        return extracted

    def _detect_language(self, text: str) -> str:
        normalized = text.strip().lower()
        if normalized in {"ko", "ko-kr", "korean"}:
            return "ko"
        if normalized in {"ja", "ja-jp", "jp", "japanese"}:
            return "ja"
        if normalized in {"en", "en-us", "english"}:
            return "en"
        hangul_count = len(re.findall(r"[\uac00-\ud7a3]", text))
        kana_count = len(re.findall(r"[\u3040-\u30ff]", text))
        cjk_count = len(re.findall(r"[\u4e00-\u9fff]", text))
        latin_count = len(re.findall(r"[A-Za-z]", text))

        if kana_count > 0:
            return "ja"
        if hangul_count > 0 and (hangul_count + cjk_count) >= latin_count:
            return "ko"
        if cjk_count > 0 and latin_count == 0:
            return "ja"
        if latin_count > 0:
            return "en"
        return "unknown"

    def _extract_route_context(self, text: str, intent: str) -> RouteConstraintContext | None:
        if intent != "find_map_route":
            return None
        route = parse_map_route_request(text)
        return RouteConstraintContext(
            origin=route.origin or None,
            destination=route.destination or None,
            transport_mode=route.mode or None,
            route_kind=route.route_kind or None,
        )

    def _normalize_compare_text(self, text: str) -> str:
        return re.sub(r"\s+", " ", str(text or "").strip()).lower()

    def _repair_provider_text(self, text: str, provider: str, intent: str) -> str:
        provider_labels = {
            "naver": "네이버에서",
            "google": "구글에서",
            "youtube": "유튜브에서",
            "naver_map": "네이버 지도에서",
            "kakao_map": "카카오맵에서",
        }
        prefix = provider_labels.get(provider)
        if not prefix:
            return text
        cleaned = re.sub(
            r"^(?:네이버(?: 지도)?에서|구글에서|유튜브에서|카카오맵에서|Search Naver for|Search Google for|Search YouTube for)\s*",
            "",
            text,
            flags=re.IGNORECASE,
        ).strip()
        if intent == "search_and_read" and provider in {"naver", "google", "youtube"}:
            query = self._extract_query_text(cleaned, intent)
            if provider == "youtube":
                return f"{prefix} {query} 영상 찾아줘".strip()
            return f"{prefix} {query} 검색해줘".strip()
        return f"{prefix} {cleaned}".strip()

    def _repair_target_app(self, provider: str, target_app: str | None, intent: str) -> str | None:
        if intent == "find_map_route" and provider in {"naver_map", "kakao_map"}:
            return provider
        if intent == "search_and_read":
            return "browser"
        return target_app

    def _repair_query_text(self, text: str, constraints: CommandConstraint, intent: str) -> str:
        if intent == "find_map_route" and constraints.route_context is not None:
            origin = constraints.route_context.origin or ""
            destination = constraints.route_context.destination or ""
            route_kind = constraints.route_context.route_kind or constraints.route_context.transport_mode or ""
            provider_prefix = self._repair_provider_text("", constraints.provider, intent).strip()
            route_phrase = "길 찾아줘"
            if route_kind and route_kind not in {"general", "transit"}:
                route_phrase = f"{route_kind} 경로 찾아줘"
            rebuilt = f"{provider_prefix} {origin}에서 {destination} {route_phrase}".strip()
            return re.sub(r"\s+", " ", rebuilt)

        query = constraints.query_text.strip()
        if not query:
            return text
        provider_prefix = self._repair_provider_text("", constraints.provider, intent).strip()
        if constraints.provider == "youtube":
            rebuilt = f"{provider_prefix} {query} 영상 찾아줘"
        elif constraints.provider in {"naver", "google"}:
            rebuilt = f"{provider_prefix} {query} 검색해줘"
        else:
            rebuilt = query
        return re.sub(r"\s+", " ", rebuilt.strip())
