"""
ExportService — Handles all export workflows for dubbed projects.

Supports:
  - Video export in MP4 H.264, MP4 H.265, and MOV ProRes
  - Audio-only WAV/AAC export
  - SRT subtitle generation from segments
  - Full project JSON export
  - Stems export (background, vocals, dubbed voices)
"""

import json
import os

from processing.config import EXPORTS_DIR, MIXES_DIR, SEPARATED_AUDIO_DIR
from processing.services.ffmpeg_service import FFmpegService


class ExportService:
    """Orchestrates all export deliverables for a dubbed project."""

    # ------------------------------------------------------------------
    # Video export
    # ------------------------------------------------------------------

    @classmethod
    def export_video(cls, project_data: dict) -> str:
        """
        Muxes the final audio mix with the original video into the chosen
        container/codec format.

        Supported project_data["export"]["videoFormat"] values:
          - "MP4 H.264"  (default)
          - "MP4 H.265"
          - "MOV ProRes"

        Returns the path to the exported video file.
        """
        ffmpeg_bin = FFmpegService.get_ffmpeg_binary()
        video_path = project_data["inputVideoPath"]
        mix_wav = os.path.join(str(MIXES_DIR), "final_mix.wav")
        video_format = project_data.get("export", {}).get("videoFormat", "MP4 H.264")

        if video_format == "MP4 H.265":
            ext = ".mp4"
            codec_flags = ["-c:v", "libx265", "-crf", "23"]
        elif video_format == "MOV ProRes":
            ext = ".mov"
            codec_flags = ["-c:v", "prores_ks", "-profile:v", "3"]
        else:  # MP4 H.264
            ext = ".mp4"
            codec_flags = ["-c:v", "libx264", "-crf", "18", "-preset", "medium"]

        output_path = os.path.join(str(EXPORTS_DIR), f"{project_data['name']}_dubbed{ext}")

        cmd = [
            ffmpeg_bin, "-y",
            "-i", video_path,
            "-i", mix_wav,
            "-map", "0:v:0",
            "-map", "1:a:0",
            *codec_flags,
            "-c:a", "aac", "-b:a", "320k",
            "-shortest",
            output_path,
        ]

        success = FFmpegService.run_cmd(cmd)
        if not success:
            raise RuntimeError(f"Video export failed for format {video_format}")
        return output_path

    # ------------------------------------------------------------------
    # Audio-only export
    # ------------------------------------------------------------------

    @classmethod
    def export_audio_only(cls, project_data: dict) -> str:
        """Exports just the final dubbed audio mix as a WAV file."""
        mix_wav = os.path.join(str(MIXES_DIR), "final_mix.wav")
        output_path = os.path.join(str(EXPORTS_DIR), f"{project_data['name']}_audio.wav")

        if os.path.exists(mix_wav):
            import shutil
            shutil.copy2(mix_wav, output_path)
        else:
            raise FileNotFoundError("Final mix WAV not found. Run mixing first.")
        return output_path

    # ------------------------------------------------------------------
    # Subtitle (SRT) export
    # ------------------------------------------------------------------

    @classmethod
    def export_subtitles(cls, project_data: dict) -> str:
        """Generates an SRT subtitle file from the project segments."""
        segments = project_data.get("segments", [])
        output_path = os.path.join(str(EXPORTS_DIR), f"{project_data['name']}_subtitles.srt")

        with open(output_path, "w", encoding="utf-8") as f:
            for idx, seg in enumerate(segments, start=1):
                start_tc = cls._seconds_to_srt_timecode(seg["start"])
                end_tc = cls._seconds_to_srt_timecode(seg["end"])
                text = seg.get("dubText") or seg.get("sourceText", "")
                f.write(f"{idx}\n{start_tc} --> {end_tc}\n{text}\n\n")

        return output_path

    # ------------------------------------------------------------------
    # Project JSON export
    # ------------------------------------------------------------------

    @classmethod
    def export_project_json(cls, project_data: dict) -> str:
        """Writes the full project data as a portable JSON file."""
        output_path = os.path.join(str(EXPORTS_DIR), f"{project_data['name']}_project.json")
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(project_data, f, indent=2, ensure_ascii=False)
        return output_path

    # ------------------------------------------------------------------
    # Stems export
    # ------------------------------------------------------------------

    @classmethod
    def export_stems(cls, project_data: dict) -> dict:
        """
        Copies separated stems (background, vocals, dubbed canvas) into
        the exports directory and returns a dict of paths.
        """
        import shutil

        stems = {}
        stem_files = {
            "background": os.path.join(str(SEPARATED_AUDIO_DIR), "background.wav"),
            "vocals": os.path.join(str(SEPARATED_AUDIO_DIR), "vocals.wav"),
            "dubbed_voices": os.path.join(str(MIXES_DIR), "dubbed_voices_canvas.wav"),
        }

        for stem_name, src_path in stem_files.items():
            if os.path.exists(src_path):
                dest = os.path.join(str(EXPORTS_DIR), f"{project_data['name']}_{stem_name}.wav")
                shutil.copy2(src_path, dest)
                stems[stem_name] = dest
            else:
                stems[stem_name] = None

        return stems

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _seconds_to_srt_timecode(seconds: float) -> str:
        """Converts a float seconds value to SRT timecode HH:MM:SS,mmm."""
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        secs = int(seconds % 60)
        millis = int(round((seconds - int(seconds)) * 1000))
        return f"{hours:02d}:{minutes:02d}:{secs:02d},{millis:03d}"
