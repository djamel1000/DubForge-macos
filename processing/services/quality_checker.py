"""
QualityChecker — Automated quality-assurance checks for segments and projects.

Implements scoring per spec §34:
  - duration_fit_score: how well TTS output fits the original timing window
  - translation_confidence: estimated from Gemini adaptation metadata
  - speaker_confidence: derived from diarization overlap quality
  - emotion_confidence: based on emotion detection completeness
  - needs_human_review: aggregated boolean flag
"""


class QualityChecker:
    """Runs rule-based quality checks on individual segments and whole projects."""

    # ------------------------------------------------------------------
    # Per-segment check
    # ------------------------------------------------------------------

    @classmethod
    def check_segment(cls, segment: dict) -> dict:
        """
        Evaluates a single segment and returns a quality report dict.

        Args:
            segment: A fully-populated segment dict from the project.

        Returns:
            dict with keys:
                duration_fit_score      — float 0.0 – 1.0
                translation_confidence  — float 0.0 – 1.0
                speaker_confidence      — float 0.0 – 1.0
                emotion_confidence      — float 0.0 – 1.0
                needs_human_review      — bool
        """
        # --- Duration fit ---
        original_dur = segment.get("duration", 0.0)
        generated_dur = segment.get("generatedDuration") or 0.0
        if original_dur > 0 and generated_dur > 0:
            ratio = generated_dur / original_dur
            # Perfect fit at ratio == 1.0, linearly degrade for deviation
            duration_fit_score = max(0.0, 1.0 - abs(1.0 - ratio))
        else:
            duration_fit_score = 0.0

        # --- Translation confidence ---
        dub_text = segment.get("dubText", "")
        source_text = segment.get("sourceText", "")
        if dub_text and source_text:
            # Heuristic: penalise if dub text is drastically shorter or longer
            len_ratio = len(dub_text) / max(len(source_text), 1)
            translation_confidence = min(1.0, max(0.0, 1.0 - abs(1.0 - len_ratio) * 0.5))
        else:
            translation_confidence = 0.0

        # --- Speaker confidence ---
        fit_status = segment.get("fitStatus", "pending")
        warnings = segment.get("warnings", [])
        low_overlap = any("Low speaker overlap" in w for w in warnings)
        speaker_confidence = 0.5 if low_overlap else 0.92

        # --- Emotion confidence ---
        emotion = segment.get("emotion", "")
        emotion_confidence = 0.85 if emotion and emotion != "neutral" else 0.60

        # --- Aggregate review flag ---
        needs_human_review = (
            duration_fit_score < 0.70
            or translation_confidence < 0.50
            or speaker_confidence < 0.60
            or fit_status in ("needs_review", "too_long", "failed")
            or segment.get("retryCount", 0) >= 3
        )

        return {
            "duration_fit_score": round(duration_fit_score, 3),
            "translation_confidence": round(translation_confidence, 3),
            "speaker_confidence": round(speaker_confidence, 3),
            "emotion_confidence": round(emotion_confidence, 3),
            "needs_human_review": needs_human_review,
        }

    # ------------------------------------------------------------------
    # Project-level check
    # ------------------------------------------------------------------

    @classmethod
    def check_project(cls, project: dict) -> list[dict]:
        """
        Runs quality checks across every segment and returns a list of
        warning dicts matching spec §34.

        Each warning dict:
            segment_id  — int
            level       — "info" | "warning" | "error"
            code        — short machine-readable code
            message     — human-readable description
        """
        warnings: list[dict] = []
        segments = project.get("segments", [])

        if not segments:
            warnings.append({
                "segment_id": None,
                "level": "error",
                "code": "NO_SEGMENTS",
                "message": "Project has no segments. Run transcription first.",
            })
            return warnings

        total_needs_review = 0

        for seg in segments:
            seg_id = seg.get("id", 0)
            report = cls.check_segment(seg)

            if report["needs_human_review"]:
                total_needs_review += 1

            if report["duration_fit_score"] < 0.70:
                warnings.append({
                    "segment_id": seg_id,
                    "level": "warning",
                    "code": "POOR_DURATION_FIT",
                    "message": (
                        f"Segment {seg_id} duration fit is low "
                        f"({report['duration_fit_score']:.0%}). "
                        "Consider shortening the dubbed text or adjusting speed."
                    ),
                })

            if report["translation_confidence"] < 0.50:
                warnings.append({
                    "segment_id": seg_id,
                    "level": "warning",
                    "code": "LOW_TRANSLATION_CONFIDENCE",
                    "message": (
                        f"Segment {seg_id} translation confidence is low "
                        f"({report['translation_confidence']:.0%}). "
                        "Review the adapted text."
                    ),
                })

            if report["speaker_confidence"] < 0.60:
                warnings.append({
                    "segment_id": seg_id,
                    "level": "warning",
                    "code": "LOW_SPEAKER_CONFIDENCE",
                    "message": (
                        f"Segment {seg_id} has low speaker diarization confidence. "
                        "Verify speaker assignment."
                    ),
                })

            fit_status = seg.get("fitStatus", "pending")
            if fit_status == "failed":
                warnings.append({
                    "segment_id": seg_id,
                    "level": "error",
                    "code": "TTS_GENERATION_FAILED",
                    "message": f"Segment {seg_id} TTS generation failed.",
                })

            if not seg.get("generatedAudioPath"):
                warnings.append({
                    "segment_id": seg_id,
                    "level": "info",
                    "code": "NO_AUDIO_GENERATED",
                    "message": f"Segment {seg_id} has no generated audio yet.",
                })

        # Project-level summary warnings
        review_pct = (total_needs_review / len(segments)) * 100 if segments else 0
        if review_pct > 30:
            warnings.append({
                "segment_id": None,
                "level": "warning",
                "code": "HIGH_REVIEW_RATE",
                "message": (
                    f"{review_pct:.0f}% of segments need human review. "
                    "Consider re-running adaptation or adjusting speaker profiles."
                ),
            })

        return warnings
