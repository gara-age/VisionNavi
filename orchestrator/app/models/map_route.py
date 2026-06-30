from typing import Literal

from pydantic import BaseModel, Field


class MapRouteRequest(BaseModel):
    provider: Literal["naver_map", "kakao_map", "unknown_map"] = "unknown_map"
    origin: str = Field(default="")
    destination: str = Field(default="")
    mode: Literal["transit", "car", "walk", "bike"] = "transit"
    route_kind: Literal["general", "subway", "bus", "train"] = "general"
