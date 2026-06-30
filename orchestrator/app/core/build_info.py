from __future__ import annotations

from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path


@lru_cache(maxsize=1)
def get_build_info() -> dict[str, str]:
    started_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    project_root = Path(__file__).resolve().parents[3]
    signature = _safe_mtime_signature(project_root / "orchestrator" / "app")
    return {
        "server_build_id": f"{started_at}|{signature}",
        "server_started_at_utc": started_at,
        "server_code_signature": signature,
    }


def _safe_mtime_signature(root: Path) -> str:
    try:
        latest_mtime = 0.0
        for path in root.rglob("*.py"):
            try:
                latest_mtime = max(latest_mtime, path.stat().st_mtime)
            except OSError:
                continue
        if latest_mtime <= 0:
            return "unknown"
        return datetime.fromtimestamp(latest_mtime, tz=timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    except OSError:
        return "unknown"
