import wave
import os
import json
import subprocess

class DurationChecker:
    @staticmethod
    def get_audio_duration(filepath: str) -> float:
        """Reads audio duration for WAV/MP3/M4A/etc."""
        if not filepath or not os.path.exists(filepath):
            return 0.0
        if filepath.lower().endswith(".wav"):
            duration = DurationChecker.get_wav_duration(filepath)
            if duration:
                return duration

        try:
            from processing.services.ffmpeg_service import FFmpegService
            ffprobe_bin = FFmpegService.get_ffmpeg_binary().replace("ffmpeg", "ffprobe")
            cmd = [
                ffprobe_bin, "-v", "error",
                "-show_entries", "format=duration",
                "-of", "json",
                filepath
            ]
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10)
            if result.returncode == 0:
                payload = json.loads(result.stdout or "{}")
                duration = float(payload.get("format", {}).get("duration", 0.0))
                return round(duration, 3)
        except Exception as e:
            print(f"Error checking media duration with ffprobe: {e}")
        return 0.0

    @staticmethod
    def get_wav_duration(filepath: str) -> float:
        """Reads WAV file duration using standard library Wave module."""
        if not filepath or not os.path.exists(filepath):
            return 0.0
        try:
            with wave.open(filepath, 'rb') as f:
                frames = f.getnframes()
                rate = f.getframerate()
                return round(frames / float(rate), 3)
        except Exception as e:
            print(f"Error checking WAV duration: {e}")
            return 0.0

    @classmethod
    def check_fit(cls, original_duration: float, generated_audio_path: str) -> tuple:
        """
        Determines timing fit status:
        - generatedDuration <= originalDuration: fits
        - generatedDuration <= originalDuration: fits
        - generatedDuration > originalDuration: too_long
        - generatedDuration < originalDuration * 0.70: too_short
        """
        gen_duration = cls.get_audio_duration(generated_audio_path)
        
        if gen_duration == 0.0:
            return "failed", 0.0, ["Failed to read generated audio duration."]
            
        warnings = []
        if gen_duration < original_duration * 0.70:
            status = "too_short"
            warnings.append("Segment is significantly shorter than original (over 30% gap).")
        elif gen_duration <= original_duration:
            status = "fits"
        else:
            status = "too_long"
            warnings.append("Segment is too long to fit in mouth movement window.")
            
        return status, gen_duration, warnings

    @classmethod
    def apply_speed_or_padding(cls, audio_path: str, output_path: str, speed_factor: float, pad_silence_sec: float = 0.0) -> bool:
        """
        Uses FFmpeg filters to adjust TTS speed (atempo filter) and pad with silence
        to fit original speech windows.
        """
        from processing.services.ffmpeg_service import FFmpegService
        ffmpeg_bin = FFmpegService.get_ffmpeg_binary()
        
        # Audio speed filter. FFmpeg atempo accepts 0.5..2.0 per filter, so
        # chain filters for aggressive timing compression.
        filters = []
        if speed_factor != 1.0:
            remaining = max(0.25, min(8.0, speed_factor))
            while remaining > 2.0:
                filters.append("atempo=2.0")
                remaining /= 2.0
            while remaining < 0.5:
                filters.append("atempo=0.5")
                remaining /= 0.5
            filters.append(f"atempo={remaining:.6f}")
            
        filter_str = f"-af {','.join(filters)}" if filters else ""
        
        # If we need padding, pad with silence at the end using apad filter or simple ffmpeg pad
        if pad_silence_sec > 0:
            # We can pad using apad filter: apad=pad_dur=X
            if filter_str:
                filter_str += f",apad=pad_dur={pad_silence_sec}"
            else:
                filter_str = f"-af apad=pad_dur={pad_silence_sec}"
                
        cmd = [
            ffmpeg_bin, "-y",
            "-i", audio_path
        ]
        if filter_str:
            cmd.extend(filter_str.split())
        cmd.append(output_path)
        
        return FFmpegService.run_cmd(cmd)
