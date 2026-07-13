from app.agent.loop import AgentLoop
from app.models.canonical_command import CanonicalCommand
from app.services.command_constraint_service import CommandConstraintService


def test_constraint_service_repairs_provider_back_to_naver() -> None:
    service = CommandConstraintService()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="네이버에서 청년 월세 지원 검색해줘",
        normalized_text="구글에서 청년 월세 지원 검색해줘",
        task_domain="web",
        intent="search_and_read",
        risk_level="low",
        requires_confirmation=False,
        target_app="browser",
        notes=[],
        constraints=service.build_constraints(
            raw_text="네이버에서 청년 월세 지원 검색해줘",
            normalized_text="네이버에서 청년 월세 지원 검색해줘",
            task_domain="web",
            intent="search_and_read",
            target_app="browser",
        ).constraints,
    )

    repaired_command, result = service.validate_and_repair(command, allow_repair=True, max_repairs=1)

    assert result.attempted_repair is True
    assert repaired_command.normalized_text.startswith("네이버에서")
    assert result.ok is True


def test_agent_loop_blocks_on_unrepaired_language_mismatch() -> None:
    loop = AgentLoop()
    service = CommandConstraintService()
    command = CanonicalCommand(
        input_mode="text",
        raw_text="네이버에서 청년 월세 지원 검색해줘",
        normalized_text="Search Naver for youth monthly rent support",
        task_domain="web",
        intent="search_and_read",
        risk_level="low",
        requires_confirmation=False,
        target_app="browser",
        notes=[],
        constraints=service.build_constraints(
            raw_text="네이버에서 청년 월세 지원 검색해줘",
            normalized_text="네이버에서 청년 월세 지원 검색해줘",
            task_domain="web",
            intent="search_and_read",
            target_app="browser",
        ).constraints,
    )
    loop.settings = loop.settings.__class__(
        **{
            **loop.settings.__dict__,
            "command_constraint_validation_enabled": True,
            "command_constraint_repair_enabled": False,
        }
    )

    result = loop._execute_command(command, requested_backend="external_browser_agent")  # noqa: SLF001

    assert result["status"] == "failed"
    assert result["failure_reason"] == "query_changed"
