from fastapi import APIRouter

from app.core.build_info import get_build_info

router = APIRouter(tags=["health"])


@router.get("/health")
def health_check() -> dict[str, str]:
    return {"status": "ok", **get_build_info()}
