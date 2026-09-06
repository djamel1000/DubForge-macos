"""
Pydantic model for Gemini adaptation output (spec §19).

This is the structured JSON that GeminiDirector returns for each segment.
"""

from pydantic import BaseModel
from typing import Optional


class GeminiOutput(BaseModel):
    """Structured response from the Gemini director for a single segment."""
    segment_id: int
    speaker_id: str
    dub_text: str
    literal_translation: str = ""
    emotion: str = "neutral"
    emotion_intensity: str = "medium"
    performance_instruction: str = ""
    qwen_instruction: str = ""
    estimated_spoken_duration: float = 0.0
    timing_strategy: str = "natural_pacing"
    meaning_preserved: bool = True
    needs_review: bool = False
