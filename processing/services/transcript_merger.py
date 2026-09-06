"""
TranscriptMerger — Merges transcript segments with speaker diarization regions.

Extracted from diarization_service.py to provide a dedicated, reusable merge layer.
"""


class TranscriptMerger:
    """Merges time-aligned transcript segments with speaker diarization regions
    using maximum-overlap assignment."""

    @staticmethod
    def merge(segments: list, speaker_regions: list) -> list:
        """
        Merges transcript segments with speaker timestamps based on overlap logic.
        Assigns the dominant speaker to each segment.

        Args:
            segments: List of dicts with keys id, start, end, duration, source_text.
            speaker_regions: List of dicts with keys start, end, speaker_id.

        Returns:
            List of fully-formed segment dicts ready for project storage.
        """
        updated_segments = []
        for seg in segments:
            seg_start = seg["start"]
            seg_end = seg["end"]
            seg_duration = seg["duration"]

            best_speaker = "SPEAKER_01"  # Default fallback
            max_overlap = 0.0
            overlapping_speech = False

            for region in speaker_regions:
                # Calculate overlap interval
                overlap_start = max(seg_start, region["start"])
                overlap_end = min(seg_end, region["end"])

                if overlap_start < overlap_end:
                    overlap_dur = overlap_end - overlap_start
                    if region.get("overlap") and overlap_dur >= 0.08:
                        overlapping_speech = True
                    if overlap_dur > max_overlap:
                        max_overlap = overlap_dur
                        best_speaker = region["speaker_id"]

            # Map values matching Segment schema
            warnings = []
            fit_status = "pending"
            needs_review = False

            # If overlap confidence is low or split lines, flag for review
            if max_overlap < (seg_duration * 0.4):
                warnings.append("Low speaker overlap confidence.")
                fit_status = "needs_review"
                needs_review = True
            if overlapping_speech:
                warnings.append("Overlapping speakers detected; verify speaker assignment and cloning reference.")
                fit_status = "needs_review"
                needs_review = True

            updated_segments.append({
                "id": seg["id"],
                "start": seg_start,
                "end": seg_end,
                "duration": seg_duration,
                "speakerId": best_speaker,
                "sourceText": seg["source_text"],
                "dubText": "",
                "literalTranslation": "",
                "emotion": "neutral",
                "emotionIntensity": 50.0,
                "performanceInstruction": "",
                "qwenInstruction": "",
                "voiceProfileId": f"qwen_voice_{best_speaker.lower()}",
                "generatedAudioPath": None,
                "generatedDuration": None,
                "retryCount": 0,
                "fitStatus": fit_status,
                "approved": False,
                "locked": False,
                "warnings": warnings
            })

        return updated_segments
