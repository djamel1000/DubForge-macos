import atexit
import json
import math
import os
import select
import struct
import subprocess
import threading
import time
import wave
from pathlib import Path

from processing.config import API_SETTINGS, TTS_SEGMENTS_DIR


class QwenTTSService:
    """Runs Qwen3-TTS locally through MLX.

    Inference happens in this project's own isolated ML environment via
    ``ml_worker.py`` -- the same subprocess bridge Whisper and Pyannote use --
    so dubbing does not depend on any separately installed inference server
    being launched and listening first.
    """

    # Canonical Qwen3-TTS preset names. Serena, Vivian and Dylan are Chinese
    # voices (Dylan is Beijing dialect); Ryan and Aiden are English.
    VOICE_MAP = {
        "qwen_voice_speaker_01": "Serena",
        "qwen_voice_speaker_02": "Vivian",
        "qwen_voice_speaker_03": "Ryan",
        "qwen_voice_speaker_04": "Aiden",
        "qwen_voice_speaker_05": "Dylan",
    }

    # Base checkpoints are the only ones that accept a cloning reference, so this
    # is the right default for a dubbing tool.
    DEFAULT_MODEL = "Qwen3-TTS-12Hz-1.7B-Base-8bit"
    HUB_NAMESPACE = "mlx-community"

    _instruction_notice_shown = False
    _worker_process = None
    _worker_model_reference = ""
    _worker_output_buffer = b""
    _worker_lock = threading.Lock()
    _ready_prefix = "DUBFORGE_TTS_READY\t"
    _result_prefix = "DUBFORGE_TTS_RESULT\t"

    @classmethod
    def model_reference(cls) -> str:
        """Resolves the configured model to a local directory or a Hub repo id."""
        local_path = str(API_SETTINGS.get("qwenLocalPath", "") or "").strip()
        if local_path:
            return os.path.expanduser(local_path)
        name = str(API_SETTINGS.get("qwenModel", "") or "").strip() or cls.DEFAULT_MODEL
        if "/" in name:
            return name
        return f"{cls.HUB_NAMESPACE}/{name}"

    @staticmethod
    def _is_local_reference(reference: str) -> bool:
        return os.path.isabs(reference) or reference.startswith((".", "~"))

    @staticmethod
    def _hub_cache_dir() -> Path:
        for variable, suffix in (("HF_HUB_CACHE", ""), ("HF_HOME", "hub")):
            value = os.environ.get(variable, "").strip()
            if value:
                base = Path(os.path.expanduser(value))
                return base / suffix if suffix else base
        return Path.home() / ".cache" / "huggingface" / "hub"

    @classmethod
    def _ml_python(cls) -> str:
        return os.path.expanduser(API_SETTINGS.get("mlPythonPath", "") or "")

    @staticmethod
    def _worker_path() -> Path:
        return Path(__file__).resolve().parents[1] / "ml_worker.py"

    @classmethod
    def weights_available(cls) -> bool:
        reference = cls.model_reference()
        if cls._is_local_reference(reference):
            return os.path.isdir(reference)
        cached = cls._hub_cache_dir() / f"models--{reference.replace('/', '--')}"
        return cached.is_dir()

    @classmethod
    def quick_ready(cls) -> bool:
        """Filesystem-only readiness, cheap enough to call from list endpoints.

        Skips the package import probe -- that costs a subprocess -- so a True
        here means "nothing obviously missing" rather than a full guarantee.
        """
        ml_python = cls._ml_python()
        return (
            bool(ml_python and os.path.exists(ml_python))
            and cls._worker_path().exists()
            and cls.weights_available()
        )

    @classmethod
    def readiness(cls) -> dict:
        """Reports whether local Qwen3-TTS can run, without synthesizing anything.

        The pipeline reaches TTS only after transcription, diarization and
        translation have already run, so an unusable engine needs to be
        detectable up front rather than discovered after that work is spent.
        """
        ml_python = cls._ml_python()
        worker = cls._worker_path()
        runtime_ready = bool(ml_python and os.path.exists(ml_python)) and worker.exists()
        packages = {"mlx": False, "mlx_audio": False}

        if runtime_ready:
            try:
                probe = subprocess.run(
                    [
                        ml_python,
                        "-c",
                        "import importlib.util,json;print(json.dumps({"
                        "'mlx':importlib.util.find_spec('mlx') is not None,"
                        "'mlx_audio':importlib.util.find_spec('mlx_audio') is not None}))",
                    ],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
                if probe.returncode == 0 and probe.stdout.strip():
                    packages = json.loads(probe.stdout.strip().splitlines()[-1])
            except Exception:
                pass

        reference = cls.model_reference()
        weights = cls.weights_available()
        ready = runtime_ready and packages.get("mlx_audio", False) and weights

        detail = ""
        if not runtime_ready:
            detail = "The isolated ML Python runtime is not configured."
        elif not packages.get("mlx_audio", False):
            detail = (
                "mlx-audio is not installed in the ML runtime. Install it with: "
                f"{ml_python} -m pip install mlx-audio"
            )
        elif not weights:
            detail = (
                f"The weights for '{reference}' are not downloaded yet. They are fetched "
                "automatically on first synthesis, which needs network access and several GB of disk."
            )

        return {
            "ready": ready,
            "model": reference,
            "modelIsLocalPath": cls._is_local_reference(reference),
            "mlRuntimeReady": runtime_ready,
            "mlxInstalled": packages.get("mlx", False),
            "mlxAudioInstalled": packages.get("mlx_audio", False),
            "weightsAvailable": weights,
            "detail": detail,
        }

    @classmethod
    def _voice_name(cls, voice_profile_id: str) -> str:
        return API_SETTINGS.get("qwenVoiceName", "") or cls.VOICE_MAP.get(voice_profile_id, "Serena")

    @staticmethod
    def generate_mock_wav(output_path: str, duration: float, sample_rate: int = 24000) -> str:
        """Generates a high-quality sinusoidal synthetic audio WAV file to mimic TTS output."""
        num_samples = int(duration * sample_rate)
        # Create a basic pleasant audio tone
        frequency = 300.0  # Nice male-ish low hum

        with wave.open(output_path, 'wb') as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(sample_rate)

            for i in range(num_samples):
                # Fade in/out slightly to avoid pops
                envelope = 1.0
                if i < 480:  # 20ms fade in
                    envelope = i / 480.0
                elif i > num_samples - 1200:  # 50ms fade out
                    envelope = (num_samples - i) / 1200.0

                val = math.sin(2.0 * math.pi * frequency * (i / sample_rate))
                val_int = int(val * 16384 * envelope)
                w.writeframesraw(struct.pack('<h', val_int))

        return output_path

    @classmethod
    def _validate_clone_reference(
        cls,
        reference_audio_path: str,
        reference_text: str,
        voice_profile_id: str,
        model_reference: str,
    ) -> None:
        if not reference_audio_path or not os.path.exists(reference_audio_path):
            raise RuntimeError(
                f"Qwen clone reference audio is missing for voice profile '{voice_profile_id}'."
            )
        if not reference_text.strip():
            raise RuntimeError(
                f"Qwen clone reference transcript is missing for voice profile '{voice_profile_id}'."
            )
        lowered = model_reference.lower()
        if "customvoice" in lowered or "voicedesign" in lowered:
            raise RuntimeError(
                "The selected Qwen model only provides preset or designed voices. "
                "Select a Qwen3-TTS Base voice-cloning model in Settings."
            )

    @classmethod
    def _apply_speed(cls, audio_path: str, speed: float) -> None:
        """Retimes a rendered segment in place with FFmpeg's pitch-preserving atempo.

        Qwen3-TTS exposes no speaking-rate argument, so the duration-fitting retry
        loop is served here instead. Retiming after synthesis is also the more
        predictable half of the job: the same requested speed always produces the
        same length, which is what the fit checker measures.
        """
        from processing.services.duration_checker import DurationChecker

        retimed_path = f"{os.path.splitext(audio_path)[0]}_retimed.wav"
        if not DurationChecker.apply_speed_or_padding(audio_path, retimed_path, speed):
            raise RuntimeError(f"Failed to retime Qwen3-TTS audio to {speed:.3f}x.")
        os.replace(retimed_path, audio_path)

    @classmethod
    def _stop_worker(cls) -> None:
        process = cls._worker_process
        cls._worker_process = None
        cls._worker_model_reference = ""
        cls._worker_output_buffer = b""
        if process is None or process.poll() is not None:
            return
        try:
            if process.stdin:
                process.stdin.close()
            process.wait(timeout=5)
        except Exception:
            process.terminate()
            try:
                process.wait(timeout=5)
            except Exception:
                process.kill()

    @classmethod
    def _read_worker_message(cls, process, prefix: str, timeout: int) -> dict:
        if process.stdout is None:
            raise RuntimeError("Qwen worker output pipe is unavailable.")
        deadline = time.monotonic() + max(1, timeout)
        recent_output = []
        prefix_bytes = prefix.encode("utf-8")
        while time.monotonic() < deadline:
            while b"\n" in cls._worker_output_buffer:
                raw_line, cls._worker_output_buffer = cls._worker_output_buffer.split(b"\n", 1)
                line = raw_line.decode("utf-8", errors="replace").strip()
                if line:
                    recent_output.append(line)
                    recent_output = recent_output[-8:]
                if prefix_bytes in raw_line:
                    payload = raw_line.split(prefix_bytes, 1)[1]
                    return json.loads(payload.decode("utf-8"))
            if process.poll() is not None:
                detail = recent_output[-1] if recent_output else f"exit code {process.returncode}"
                raise RuntimeError(f"Qwen worker stopped unexpectedly: {detail}")
            remaining = max(0.1, deadline - time.monotonic())
            readable, _, _ = select.select([process.stdout], [], [], remaining)
            if not readable:
                continue
            chunk = os.read(process.stdout.fileno(), 65536)
            if not chunk:
                continue
            cls._worker_output_buffer += chunk
        raise TimeoutError(f"Qwen worker did not respond within {timeout} seconds.")

    @classmethod
    def _ensure_worker(cls, model_reference: str, env: dict, timeout: int):
        process = cls._worker_process
        if (
            process is not None
            and process.poll() is None
            and cls._worker_model_reference == model_reference
        ):
            return process

        cls._stop_worker()
        process = subprocess.Popen(
            [cls._ml_python(), str(cls._worker_path()), "tts-server", "--model", model_reference],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=False,
            bufsize=0,
            env=env,
        )
        cls._worker_process = process
        cls._worker_model_reference = model_reference
        try:
            cls._read_worker_message(process, cls._ready_prefix, timeout)
        except Exception:
            cls._stop_worker()
            raise
        return process

    @classmethod
    def _max_generation_tokens(cls, target_duration: float) -> int:
        """Bounds decoder work while leaving enough margin for natural cadence."""
        token_rate = float(API_SETTINGS.get("qwenCodecTokensPerSecond", 12.5))
        margin = float(API_SETTINGS.get("qwenDurationTokenMargin", 1.35))
        minimum = int(API_SETTINGS.get("qwenMinGenerationTokens", 24))
        maximum = int(API_SETTINGS.get("qwenMaxGenerationTokens", 300))
        estimate = math.ceil(max(0.1, target_duration) * token_rate * margin) + 8
        return max(minimum, min(maximum, estimate))

    @classmethod
    def _synthesize(
        cls,
        text: str,
        output_path: str,
        model_reference: str,
        voice: str,
        instruction: str,
        reference_audio_path: str,
        reference_text: str,
        segment_id: int,
        target_duration: float,
    ) -> None:
        ml_python = cls._ml_python()
        worker = cls._worker_path()
        if not ml_python or not os.path.exists(ml_python):
            raise RuntimeError(
                "The isolated ML Python runtime for local Qwen3-TTS is not configured. "
                "Set the ML Python path in Settings."
            )
        if not worker.exists():
            raise RuntimeError(f"The ML worker script is missing at {worker}.")

        language = str(API_SETTINGS.get("qwenLanguage", "") or "").strip().lower()
        if not reference_audio_path and instruction and not cls._instruction_notice_shown:
            cls._instruction_notice_shown = True
            print(
                "Note: per-segment delivery instructions apply to Qwen3-TTS CustomVoice "
                "and VoiceDesign checkpoints. Base checkpoints ignore them."
            )

        print(f"Synthesizing segment {segment_id} with local Qwen3-TTS ({model_reference})...")
        env = os.environ.copy()
        env["MTL_DEBUG_LAYER"] = "0"
        env["METAL_DEVICE_WRAPPER_TYPE"] = "0"
        env["TOKENIZERS_PARALLELISM"] = "false"
        env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        env["HF_HUB_ENABLE_HF_TRANSFER"] = "0"
        if cls.weights_available():
            env["HF_HUB_OFFLINE"] = "1"

        timeout = int(API_SETTINGS.get("qwenTtsTimeoutSec", 900))
        payload = {
            "text": text,
            "output": output_path,
            "language": language,
            "voice": "" if reference_audio_path else voice,
            "instruct": "" if reference_audio_path else instruction,
            "ref_audio": reference_audio_path,
            "ref_text": reference_text.strip(),
            "sample_rate": 24000,
            "max_tokens": cls._max_generation_tokens(target_duration),
        }
        try:
            with cls._worker_lock:
                process = cls._ensure_worker(model_reference, env, timeout)
                if process.stdin is None:
                    raise RuntimeError("Qwen worker input pipe is unavailable.")
                request_data = (json.dumps(payload, ensure_ascii=False) + "\n").encode("utf-8")
                process.stdin.write(request_data)
                process.stdin.flush()
                response = cls._read_worker_message(process, cls._result_prefix, timeout)
        except TimeoutError as exc:
            cls._stop_worker()
            raise RuntimeError(f"Local Qwen3-TTS timed out on segment {segment_id}.") from exc
        except (BrokenPipeError, OSError) as exc:
            cls._stop_worker()
            raise RuntimeError(f"Local Qwen3-TTS worker failed on segment {segment_id}: {exc}") from exc

        if not response.get("ok"):
            detail = str(response.get("error") or "unknown worker error")
            raise RuntimeError(cls._friendly_worker_error(detail))
        if not os.path.exists(output_path) or os.path.getsize(output_path) < 1000:
            raise RuntimeError(f"Local Qwen3-TTS produced no usable audio for segment {segment_id}.")

    @classmethod
    def _friendly_worker_error(cls, detail: str) -> str:
        lowered = detail.lower()
        if "no module named 'mlx_audio'" in lowered or "no module named mlx_audio" in lowered:
            return (
                "mlx-audio is not installed in the ML runtime. Install it with: "
                f"{cls._ml_python()} -m pip install mlx-audio"
            )
        if "no module named 'mlx'" in lowered:
            return (
                "MLX is not installed in the ML runtime. Install it with: "
                f"{cls._ml_python()} -m pip install mlx mlx-audio"
            )
        if "couldn't connect" in lowered or "connectionerror" in lowered or "offline" in lowered:
            return (
                f"Could not download the Qwen3-TTS weights for '{cls.model_reference()}'. "
                "Connect to the network for the first run, or point the Qwen local model path at "
                "an already-downloaded checkpoint."
            )
        if "not a local folder" in lowered or "repositorynotfound" in lowered or "404" in lowered:
            return (
                f"The Qwen3-TTS model '{cls.model_reference()}' was not found locally or on the Hub. "
                "Check the model name in Settings."
            )
        return f"Local Qwen3-TTS failed: {detail}"

    @classmethod
    def generate(
        cls,
        text: str,
        instruction: str,
        voice_profile_id: str,
        speed: float = 1.0,
        target_duration: float = 3.0,
        segment_id: int = 1,
        project_id: str = "unassigned",
        reference_audio_path: str = "",
        reference_text: str = "",
    ) -> str:
        """Renders one segment with local Qwen3-TTS and returns the WAV path."""
        output_dir = os.path.join(str(TTS_SEGMENTS_DIR), project_id, "qwen")
        os.makedirs(output_dir, exist_ok=True)
        output_filename = f"segment_{segment_id:04d}_tts.wav"
        output_path = os.path.join(output_dir, output_filename)

        model_reference = cls.model_reference()
        if reference_audio_path or reference_text:
            cls._validate_clone_reference(
                reference_audio_path, reference_text, voice_profile_id, model_reference
            )
        else:
            reference_audio_path = ""

        try:
            cls._synthesize(
                text=text,
                output_path=output_path,
                model_reference=model_reference,
                voice=cls._voice_name(voice_profile_id),
                instruction=(instruction or "").strip(),
                reference_audio_path=reference_audio_path,
                reference_text=reference_text,
                segment_id=segment_id,
                target_duration=target_duration,
            )
            requested_speed = max(0.25, min(4.0, float(speed or 1.0)))
            if abs(requested_speed - 1.0) > 1e-3:
                cls._apply_speed(output_path, requested_speed)
            return output_path
        except Exception as e:
            if API_SETTINGS.get("allowMockTTS", False):
                print(f"Qwen TTS unavailable ({e}). Rendering synthetic WAV because allowMockTTS is enabled...")
                return cls.generate_mock_wav(output_path, duration=target_duration)
            raise


atexit.register(QwenTTSService._stop_worker)
