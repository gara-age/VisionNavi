from __future__ import annotations

import json
import subprocess
from typing import Any


class AudioDiagnosticsService:
    def collect(self) -> dict[str, Any]:
        endpoints = self._query_audio_endpoints()
        return {
            "platform": "windows",
            "input_endpoints": endpoints,
            "summary": self._summarize(endpoints),
        }

    def _query_audio_endpoints(self) -> list[dict[str, str]]:
        command = [
            "powershell.exe",
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            (
                "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; "
                "Get-PnpDevice -Class AudioEndpoint | "
                "Select-Object Status,Class,FriendlyName,InstanceId | "
                "ConvertTo-Json -Depth 4"
            ),
        ]
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=10,
            check=False,
        )
        if completed.returncode != 0:
            stderr = completed.stderr.strip() or completed.stdout.strip()
            raise RuntimeError(f"Audio endpoint query failed: {stderr}")

        payload = completed.stdout.strip()
        if not payload:
            return []

        decoded = json.loads(payload)
        if isinstance(decoded, dict):
            decoded = [decoded]
        if not isinstance(decoded, list):
            return []

        endpoints: list[dict[str, str]] = []
        for item in decoded:
            if not isinstance(item, dict):
                continue
            endpoints.append(
                {
                    "status": str(item.get("Status", "")),
                    "class": str(item.get("Class", "")),
                    "friendly_name": str(item.get("FriendlyName", "")),
                    "instance_id": str(item.get("InstanceId", "")),
                }
            )
        return endpoints

    def _summarize(self, endpoints: list[dict[str, str]]) -> dict[str, Any]:
        ok_items = [
            item for item in endpoints if item.get("status", "").strip().lower() == "ok"
        ]
        input_candidates = [
            item
            for item in endpoints
            if any(
                marker in item.get("friendly_name", "").lower()
                for marker in ("마이크", "microphone", "hands-free", "수화기", "headset")
            )
        ]
        remote_items = [
            item
            for item in endpoints
            if "원격 오디오" in item.get("friendly_name", "")
            or "remote audio" in item.get("friendly_name", "").lower()
        ]
        unknown_items = [
            item
            for item in endpoints
            if item.get("status", "").strip().lower() == "unknown"
        ]
        return {
            "ok_count": len(ok_items),
            "unknown_count": len(unknown_items),
            "remote_audio_count": len(remote_items),
            "input_candidate_count": len(input_candidates),
            "has_any_ok_endpoint": bool(ok_items),
            "has_ok_input_candidate": any(
                item.get("status", "").strip().lower() == "ok"
                for item in input_candidates
            ),
        }
