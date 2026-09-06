"""
Pydantic model for the DubForge Segment entity (spec §10).
"""

from pydantic import BaseModel, Field
from typing import Optional, List


class Segment(BaseModel):
    """A single time-aligned dialogue segment in a dubbing project."""
    id: int
    start: float
    end: float
    duration: float
    speakerId: str = "SPEAKER_01"
    sourceText: str = ""
    dubText: str = ""
    literalTranslation: str = ""
    emotion: str = "neutral"
    emotionIntensity: float = 50.0
    performanceInstruction: str = ""
    qwenInstruction: str = ""
    voiceProfileId: str = ""
    generatedAudioPath: Optional[str] = None
    generatedDuration: Optional[float] = None
    retryCount: int = 0
    fitStatus: str = "pending"  # pending | fits | too_long | too_short | needs_review | failed
    approved: bool = False
    locked: bool = False
    warnings: List[str] = Field(default_factory=list)
