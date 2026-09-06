import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

from processing.config import API_SETTINGS

class WhisperService:
    LANGUAGE_CODES = {
        "afrikaans": "af", "albanian": "sq", "arabic": "ar", "armenian": "hy",
        "azerbaijani": "az", "basque": "eu", "bengali": "bn", "bosnian": "bs",
        "bulgarian": "bg", "catalan": "ca", "chinese (simplified)": "zh",
        "chinese (traditional)": "zh", "croatian": "hr", "czech": "cs", "danish": "da",
        "dutch": "nl", "english": "en", "estonian": "et", "filipino": "tl",
        "finnish": "fi", "french": "fr", "galician": "gl", "georgian": "ka",
        "german": "de", "greek": "el", "gujarati": "gu", "hebrew": "he",
        "hindi": "hi", "hungarian": "hu", "icelandic": "is", "indonesian": "id",
        "irish": "ga", "italian": "it", "japanese": "ja", "kannada": "kn",
        "kazakh": "kk", "korean": "ko", "latvian": "lv", "lithuanian": "lt",
        "macedonian": "mk", "malay": "ms", "malayalam": "ml", "maltese": "mt",
        "marathi": "mr", "norwegian": "no", "persian": "fa", "polish": "pl",
        "portuguese": "pt", "punjabi": "pa", "romanian": "ro", "russian": "ru",
        "serbian": "sr", "slovak": "sk", "slovenian": "sl", "spanish": "es",
        "swahili": "sw", "swedish": "sv", "tamil": "ta", "telugu": "te",
        "thai": "th", "turkish": "tr", "ukrainian": "uk", "urdu": "ur",
        "vietnamese": "vi", "welsh": "cy",
    }

    @classmethod
    def _language_code(cls, language: str = None) -> str:
        value = (language or "").strip()
        if not value:
            return ""
        return cls.LANGUAGE_CODES.get(value.lower(), value.lower())

    @staticmethod
    def transcribe(audio_path: str, model_size: str = None, language: str = None) -> list:
        """
        Transcribes audio with faster-whisper when available, otherwise falls
        back to the system Whisper CLI. Synthetic transcript generation is
        disabled by default because it produces unusable dubbing output.
        """
        model_size = model_size or API_SETTINGS.get("whisperModel", "medium")
        language = WhisperService._language_code(language or API_SETTINGS.get("sourceLanguage", ""))
        try:
            from faster_whisper import WhisperModel
            print(f"Loading faster-whisper model '{model_size}'...")
            
            # CPU-only by design: CTranslate2 has no Metal backend, so there is no
            # MPS path to take here. int8 quantization plus performance-core thread
            # pinning is the fast configuration on Apple Silicon.
            compute_type = API_SETTINGS.get("whisperComputeType", "int8")
            cpu_threads = int(API_SETTINGS.get("whisperCpuThreads", 4) or 0)
            model = WhisperModel(
                model_size,
                device="cpu",
                compute_type=compute_type,
                cpu_threads=cpu_threads,
            )
            
            kwargs = {
                "beam_size": 5,
                "word_timestamps": True,
                "vad_filter": True,
            }
            if language:
                kwargs["language"] = language
            segments, info = model.transcribe(audio_path, **kwargs)
            
            parsed_segments = []
            segment_id = 1
            for segment in segments:
                words = [
                    {
                        "word": word.word,
                        "start": round(float(word.start), 3),
                        "end": round(float(word.end), 3),
                    }
                    for word in (segment.words or [])
                    if word.start is not None and word.end is not None
                ]
                speech_start = words[0]["start"] if words else round(segment.start, 3)
                speech_end = words[-1]["end"] if words else round(segment.end, 3)
                parsed_segments.append({
                    "id": segment_id,
                    "start": speech_start,
                    "end": speech_end,
                    "duration": round(speech_end - speech_start, 3),
                    "source_text": segment.text.strip(),
                    "words": words,
                })
                segment_id += 1
                
            return parsed_segments
        except ImportError:
            print("faster_whisper not installed in backend runtime. Trying isolated ML runtime...")
            isolated_error = None
            try:
                isolated_segments = WhisperService._transcribe_with_ml_worker(
                    audio_path, model_size, language
                )
                if isolated_segments:
                    return isolated_segments
            except RuntimeError as exc:
                isolated_error = exc
                print(str(exc))

            print("Trying system Whisper CLI...")
            cli_segments = WhisperService._transcribe_with_cli(audio_path, model_size, language)
            if cli_segments:
                return cli_segments

            if API_SETTINGS.get("allowMockTranscription", False):
                return WhisperService._mock_segments(audio_path)
            if isolated_error:
                raise isolated_error
            raise RuntimeError("Whisper transcription is unavailable in the configured ML runtime.")

    @staticmethod
    def _transcribe_with_ml_worker(audio_path: str, model_size: str, language: str = None) -> list:
        ml_python = os.path.expanduser(API_SETTINGS.get("mlPythonPath", ""))
        worker = Path(__file__).resolve().parents[1] / "ml_worker.py"
        if not ml_python or not os.path.exists(ml_python) or not worker.exists():
            return []

        with tempfile.TemporaryDirectory(prefix="dubforge_faster_whisper_") as tmpdir:
            output_path = Path(tmpdir) / "transcription.json"
            command = [
                ml_python, str(worker), "transcribe",
                "--audio", audio_path,
                "--output", str(output_path),
                "--model", model_size,
                "--compute-type", API_SETTINGS.get("whisperComputeType", "int8"),
                "--cpu-threads", str(int(API_SETTINGS.get("whisperCpuThreads", 4) or 0)),
            ]
            if language:
                command.extend(["--language", language])
            try:
                result = subprocess.run(
                    command,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=int(API_SETTINGS.get("whisperTimeoutSec", 7200)),
                )
            except subprocess.TimeoutExpired as exc:
                raise RuntimeError("Faster Whisper transcription timed out.") from exc
            if result.returncode != 0:
                detail = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "Unknown ML worker error"
                raise RuntimeError(f"Faster Whisper transcription failed: {detail}")
            if not output_path.exists():
                raise RuntimeError("Faster Whisper did not produce a transcription file.")
            with open(output_path, "r", encoding="utf-8") as output_file:
                return json.load(output_file).get("segments", [])

    @staticmethod
    def _transcribe_with_cli(audio_path: str, model_size: str, language: str = None) -> list:
        whisper_bin = API_SETTINGS.get("whisperPath") or shutil.which("whisper")
        if not whisper_bin:
            return []

        with tempfile.TemporaryDirectory(prefix="dubforge_whisper_") as tmpdir:
            cmd = [
                whisper_bin,
                audio_path,
                "--model", model_size,
                "--task", "transcribe",
                "--output_format", "json",
                "--output_dir", tmpdir,
                "--fp16", "False",
                "--verbose", "False",
                "--word_timestamps", "True",
            ]
            if language:
                cmd.extend(["--language", language])

            try:
                result = subprocess.run(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=int(API_SETTINGS.get("whisperTimeoutSec", 900)),
                )
                if result.returncode != 0:
                    print(f"Whisper CLI failed: {result.stderr[-1000:]}")
                    return []

                json_files = sorted(Path(tmpdir).glob("*.json"))
                if not json_files:
                    return []

                with open(json_files[0], "r") as f:
                    payload = json.load(f)

                parsed_segments = []
                for idx, segment in enumerate(payload.get("segments", []), start=1):
                    text = (segment.get("text") or "").strip()
                    start = float(segment.get("start", 0.0))
                    end = float(segment.get("end", start))
                    words = [
                        {
                            "word": (word.get("word") or "").strip(),
                            "start": round(float(word.get("start", start)), 3),
                            "end": round(float(word.get("end", end)), 3),
                        }
                        for word in segment.get("words", [])
                        if word.get("start") is not None and word.get("end") is not None
                    ]
                    if words:
                        start = words[0]["start"]
                        end = words[-1]["end"]
                    if not text or end <= start:
                        continue
                    parsed_segments.append({
                        "id": idx,
                        "start": round(start, 3),
                        "end": round(end, 3),
                        "duration": round(end - start, 3),
                        "source_text": text,
                        "words": words,
                    })
                return parsed_segments
            except Exception as exc:
                print(f"Whisper CLI transcription failed: {exc}")
                return []

    @staticmethod
    def _mock_segments(audio_path: str) -> list:
        import wave
        duration = 10.0
        try:
            with wave.open(audio_path, 'rb') as f:
                frames = f.getnframes()
                rate = f.getframerate()
                duration = frames / float(rate)
        except Exception:
            pass

        segments = []
        seg_len = 4.0
        num_segs = max(1, int(duration // seg_len))
        for i in range(num_segs):
            start = i * seg_len
            end = min(duration, start + seg_len)
            segments.append({
                "id": i + 1,
                "start": round(start, 3),
                "end": round(end, 3),
                "duration": round(end - start, 3),
                "source_text": f"This is transcribed speech segment number {i+1}."
            })
        return segments
