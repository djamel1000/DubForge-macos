"""
VoiceRegistry — Manages voice profile assignments persisted in voice_registry.json.

Schema follows spec §23: each entry maps a speaker_id to a voice profile with
cloning reference, style tags, and quality metrics.
"""

import json
import os
from processing.config import PROJECTS_DIR


class VoiceRegistry:
    """Persistent voice profile registry backed by a JSON file in the projects
    storage directory."""

    REGISTRY_FILENAME = "voice_registry.json"

    def __init__(self, registry_dir: str = None):
        self._dir = registry_dir or str(PROJECTS_DIR)
        self._path = os.path.join(self._dir, self.REGISTRY_FILENAME)
        self._data: dict = self._load()

    # ------------------------------------------------------------------
    # Persistence helpers
    # ------------------------------------------------------------------

    def _load(self) -> dict:
        if os.path.exists(self._path):
            try:
                with open(self._path, "r") as f:
                    return json.load(f)
            except (json.JSONDecodeError, OSError):
                return {"voices": {}}
        return {"voices": {}}

    def _save(self) -> None:
        os.makedirs(os.path.dirname(self._path), exist_ok=True)
        with open(self._path, "w") as f:
            json.dump(self._data, f, indent=2)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def get_voice(self, speaker_id: str) -> dict | None:
        """Returns the voice profile dict for a given speaker, or None."""
        return self._data["voices"].get(speaker_id)

    def register_voice(self, voice_profile: dict) -> dict:
        """
        Registers (or updates) a voice profile.

        Expected voice_profile keys (spec §23):
            voiceProfileId  — unique identifier, e.g. "qwen_voice_speaker_01"
            speakerId       — the speaker this profile is assigned to
            displayName     — human-readable label
            referenceClipPath — path to the reference WAV used for cloning
            genderStyle     — Male | Female | Neutral
            ageStyle        — Child | Teen | Adult | Elder
            tags            — list of style tags, e.g. ["warm", "authoritative"]
            qualityScore    — float 0-1 indicating cloning quality
        """
        profile_id = voice_profile.get("voiceProfileId")
        if not profile_id:
            raise ValueError("voice_profile must contain a 'voiceProfileId' key.")
        self._data["voices"][profile_id] = voice_profile
        self._save()
        return voice_profile

    def list_voices(self) -> list[dict]:
        """Returns all registered voice profiles as a list."""
        return list(self._data["voices"].values())

    def assign_voice_to_speaker(self, speaker_id: str, voice_profile_id: str) -> dict | None:
        """
        Assigns an existing voice profile to a speaker_id by setting the
        profile's speakerId field.  Returns the updated profile, or None if
        the profile_id is unknown.
        """
        profile = self._data["voices"].get(voice_profile_id)
        if profile is None:
            return None
        profile["speakerId"] = speaker_id
        self._save()
        return profile

    def delete_voice(self, voice_profile_id: str) -> bool:
        """Removes a voice profile by id. Returns True if it existed."""
        removed = self._data["voices"].pop(voice_profile_id, None)
        if removed is not None:
            self._save()
            return True
        return False
