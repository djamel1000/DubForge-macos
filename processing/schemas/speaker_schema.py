"""
Pydantic model for the DubForge Speaker entity (spec §11).
"""

from pydantic import BaseModel, Field
from typing import Optional


class Speaker(BaseModel):
    """A speaker profile identified via diarization and user refinement."""
    speakerId: str
    displayName: str = ""
    characterName: str = ""
    genderStyle: str = "Male"  # Male | Female | Neutral
    ageStyle: str = "Adult"  # Child | Teen | Adult | Elder
    personalityStyle: str = "Neutral"
    color: str = "#C0C1FF"
    voiceProfileId: str = ""
    segmentCount: int = 0
    totalSpeakingTime: float = 0.0
    confidence: float = 0.0
    referenceClipPath: Optional[str] = None
