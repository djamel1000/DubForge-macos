import os
from pathlib import Path

from processing.config import TTS_SEGMENTS_DIR
from processing.services.ffmpeg_service import FFmpegService


class SpeakerReferenceService:
    """Builds one transcript-aligned Qwen cloning reference per speaker."""

    MIN_REFERENCE_SECONDS = 1.5
    MAX_REFERENCE_SECONDS = 12.0

    @classmethod
    def _candidate_score(cls, segment: dict) -> float:
        duration = float(segment.get("duration", 0.0))
        text = (segment.get("sourceText") or "").strip()
        warnings = segment.get("warnings") or []
        if any("Overlapping speakers" in warning for warning in warnings):
            return -1.0
        if not text or duration < cls.MIN_REFERENCE_SECONDS:
            return -1.0

        # Qwen cloning works best with a complete, moderately long utterance.
        duration_score = min(duration, 8.0)
        word_score = min(len(text.split()), 14) * 0.2
        review_penalty = 2.0 if segment.get("fitStatus") == "needs_review" else 0.0
        return duration_score + word_score - review_penalty

    @classmethod
    def build_references(
        cls,
        project_id: str,
        source_audio_path: str,
        speakers: list[dict],
        segments: list[dict],
    ) -> tuple[list[dict], list[dict]]:
        reference_dir = Path(TTS_SEGMENTS_DIR) / project_id / "references"
        reference_dir.mkdir(parents=True, exist_ok=True)

        updated_speakers = []
        profile_by_speaker = {}

        for speaker in speakers:
            speaker_id = speaker.get("speakerId", "SPEAKER_01")
            candidates = [
                segment for segment in segments
                if segment.get("speakerId") == speaker_id
                and cls._candidate_score(segment) >= 0
            ]
            candidates.sort(key=cls._candidate_score, reverse=True)

            updated = dict(speaker)
            if candidates:
                selected = candidates[0]
                duration = min(float(selected["duration"]), cls.MAX_REFERENCE_SECONDS)
                safe_speaker_id = "".join(
                    char.lower() if char.isalnum() else "_" for char in speaker_id
                ).strip("_") or "speaker"
                output_path = reference_dir / f"{safe_speaker_id}_reference.wav"
                extracted = FFmpegService.extract_audio_clip(
                    source_audio_path,
                    str(output_path),
                    start=float(selected["start"]),
                    duration=duration,
                    channels=1,
                    sample_rate=24000,
                    clean_speech=True,
                )
                if extracted and output_path.exists() and output_path.stat().st_size > 1024:
                    profile_id = f"qwen_clone_{project_id[:8]}_{safe_speaker_id}"
                    updated.update({
                        "voiceProfileId": profile_id,
                        "voiceType": "cloned_voice",
                        "referenceAudioPath": str(output_path),
                        "referenceText": (selected.get("sourceText") or "").strip(),
                        "referenceSegmentId": selected.get("id"),
                        "cloneReady": True,
                    })
                    profile_by_speaker[speaker_id] = profile_id
                else:
                    updated["cloneReady"] = False
                    updated["cloneError"] = "Could not extract a usable speaker reference."
            else:
                updated["cloneReady"] = False
                updated["cloneError"] = "No transcript-aligned reference longer than 1.5 seconds."

            updated_speakers.append(updated)

        updated_segments = []
        for segment in segments:
            updated = dict(segment)
            profile_id = profile_by_speaker.get(segment.get("speakerId"))
            if profile_id:
                updated["voiceProfileId"] = profile_id
            updated_segments.append(updated)

        return updated_speakers, updated_segments
