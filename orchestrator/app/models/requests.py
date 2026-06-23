from typing import Literal

from pydantic import BaseModel, Field

from app.models.canonical_command import CanonicalCommand


class CommandRequest(BaseModel):
    input_mode: Literal["voice", "text"] = "text"
    text: str = Field(min_length=1)


class RunCommandRequest(BaseModel):
    input_mode: Literal["voice", "text"] | None = "text"
    text: str | None = None
    canonical_command: CanonicalCommand | None = None
    confirmed: bool = False
