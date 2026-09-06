"""
Pydantic models for the DubForge Project entity (spec §9).
"""

from pydantic import BaseModel, Field
from typing import Optional, List


class MixSettings(BaseModel):
    """Audio mixing configuration embedded in a Project."""
    voiceRemovalStrength: str = "Medium"
    vocalStemGainDb: float = -24.0
    backgroundGainDb: float = 0.0
    dubbedVoiceGainDb: float = 0.0
    duckingEnabled: bool = True
    duckingAmountDb: float = 4.0
    duckingAttackMs: float = 80.0
    duckingReleaseMs: float = 250.0
    limiterEnabled: bool = True
    targetLoudness: str = "-16 LUFS Web Video"
    backgroundDamageRisk: Optional[str] = None


class ExportSettings(BaseModel):
    """Export configuration embedded in a Project."""
    videoFormat: str = "MP4 H.264"
    audioFormat: str = "AAC 320 kbps"
    includeProjectJson: bool = True
    includeStems: bool = False
    includeSubtitles: bool = True
    burnInSubtitles: bool = False


class Project(BaseModel):
    """Top-level project model matching spec §9."""
    projectId: str
    name: str
    sourceLanguage: str
    targetLanguage: str
    inputVideoPath: str
    subtitlePath: Optional[str] = None
    pipelineStage: str = "Import"
    speakers: List[dict] = Field(default_factory=list)
    segments: List[dict] = Field(default_factory=list)
    speakerRegions: List[dict] = Field(default_factory=list)
    mix: MixSettings = Field(default_factory=MixSettings)
    export: ExportSettings = Field(default_factory=ExportSettings)
