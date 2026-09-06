import json
import os
import subprocess
from pathlib import Path

from processing.config import API_SETTINGS, BASE_DIR, TRANSCRIPTS_DIR
from processing.services.ffmpeg_service import FFmpegService


class DiarizationService:
    @staticmethod
    def _worker_environment() -> dict:
        environment = os.environ.copy()
        ffmpeg_binary = Path(FFmpegService.get_ffmpeg_binary()).expanduser()
        library_dirs = []
        try:
            resolved_library_dir = ffmpeg_binary.resolve().parent.parent / "lib"
            if resolved_library_dir.is_dir():
                library_dirs.append(str(resolved_library_dir))
        except OSError:
            pass

        for candidate in (
            Path("/opt/homebrew/opt/ffmpeg/lib"),
            Path("/usr/local/opt/ffmpeg/lib"),
        ):
            if candidate.is_dir() and str(candidate) not in library_dirs:
                library_dirs.append(str(candidate))

        existing = environment.get("DYLD_LIBRARY_PATH", "").strip()
        if existing:
            library_dirs.append(existing)
        if library_dirs:
            environment["DYLD_LIBRARY_PATH"] = os.pathsep.join(library_dirs)
        return environment

    @staticmethod
    def _friendly_worker_error(message: str, model: str) -> str:
        normalized = message.lower()
        if (
            "cannot access gated repo" in normalized
            or "not in the authorized list" in normalized
            or "403 client error" in normalized
        ):
            return (
                f"Access to {model} has not been approved for this Hugging Face account. "
                "Open the model access page, accept its conditions, then retry."
            )
        if "401 client error" in normalized or "invalid token" in normalized:
            return (
                "The Hugging Face token is invalid or expired. Create a Read token, "
                "apply it in DubForge Settings, then retry."
            )
        return message[-1200:]

    @staticmethod
    def diarize(audio_path: str, num_speakers: int = None, project_id: str = "unassigned") -> list:
        """
        Runs Pyannote in the isolated Python 3.12 ML environment.
        """
        if not os.path.exists(audio_path):
            raise FileNotFoundError(f"Diarization audio does not exist: {audio_path}")

        python_path = os.path.expanduser(API_SETTINGS.get("mlPythonPath", ""))
        if not python_path:
            python_path = str(BASE_DIR / "ml_venv" / "bin" / "python")
        if not os.path.exists(python_path):
            raise RuntimeError(f"DubForge ML Python was not found at {python_path}.")

        output_dir = Path(TRANSCRIPTS_DIR) / project_id
        output_dir.mkdir(parents=True, exist_ok=True)
        output_path = output_dir / "speaker_diarization.json"
        worker_path = BASE_DIR / "ml_worker.py"
        model = API_SETTINGS.get(
            "diarizationModel", "pyannote/speaker-diarization-community-1"
        )
        device = API_SETTINGS.get("diarizationDevice", "cpu")
        command = [
            python_path,
            str(worker_path),
            "diarize",
            "--audio", audio_path,
            "--output", str(output_path),
            "--model", model,
            "--device", device,
        ]
        if num_speakers:
            command.extend(["--num-speakers", str(num_speakers)])

        environment = DiarizationService._worker_environment()
        hf_token = (API_SETTINGS.get("huggingFaceToken") or "").strip()
        if hf_token:
            environment["HF_TOKEN"] = hf_token
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=environment,
            timeout=int(API_SETTINGS.get("diarizationTimeoutSec", 3600)),
        )
        if result.returncode != 0:
            message = (result.stderr or result.stdout or "Unknown Pyannote error").strip()
            message = DiarizationService._friendly_worker_error(message, model)
            raise RuntimeError(f"Pyannote diarization failed: {message}")

        with open(output_path, "r", encoding="utf-8") as result_file:
            regions = json.load(result_file).get("regions", [])
        if not regions:
            raise RuntimeError("Pyannote diarization produced no speaker regions.")
        return regions

    @staticmethod
    def merge_segments_with_speakers(segments: list, speaker_regions: list) -> list:
        """
        Merges transcript segments with speaker timestamps based on overlap logic.
        Delegates to TranscriptMerger for the actual merge algorithm.
        """
        from processing.services.transcript_merger import TranscriptMerger
        return TranscriptMerger.merge(segments, speaker_regions)
