import os
import json
from pathlib import Path

# Base directories
BASE_DIR = Path(__file__).resolve().parent
STORAGE_DIR = BASE_DIR / "storage"

# Subfolders matching schemas
PROJECTS_DIR = STORAGE_DIR / "projects"
UPLOADS_DIR = STORAGE_DIR / "uploads"
EXTRACTED_AUDIO_DIR = STORAGE_DIR / "extracted_audio"
TRANSCRIPTS_DIR = STORAGE_DIR / "transcripts"
SEPARATED_AUDIO_DIR = STORAGE_DIR / "separated_audio"
TTS_SEGMENTS_DIR = STORAGE_DIR / "tts_segments"
MIXES_DIR = STORAGE_DIR / "mixes"
EXPORTS_DIR = STORAGE_DIR / "exports"
LOGS_DIR = BASE_DIR / "logs"
SETTINGS_PATH = STORAGE_DIR / "settings.json"

# Ensure directories exist
for folder in [
    STORAGE_DIR, PROJECTS_DIR, UPLOADS_DIR, EXTRACTED_AUDIO_DIR,
    TRANSCRIPTS_DIR, SEPARATED_AUDIO_DIR, TTS_SEGMENTS_DIR,
    MIXES_DIR, EXPORTS_DIR, LOGS_DIR
]:
    folder.mkdir(parents=True, exist_ok=True)

# Settings variables configured via API (stored in memory or active config)
API_SETTINGS = {
    "geminiApiKey": "",
    "geminiModel": "gemini-1.5-pro",
    "geminiStructuredOutput": True,
    # Qwen3-TTS runs in-process through MLX in the isolated ML runtime, so there
    # is no inference server endpoint to configure. Leave qwenLocalPath empty to
    # resolve qwenModel against the mlx-community Hub namespace, or point it at a
    # directory of already-downloaded weights to stay fully offline.
    "qwenModel": "Qwen3-TTS-12Hz-1.7B-Base-8bit",
    "qwenLocalPath": "",
    # Empty means "auto", which lets Qwen infer the language from the text. To pin
    # it, use a lowercase name the loaded checkpoint declares ("english",
    # "chinese", ...); an unrecognised name is silently ignored and falls back to
    # auto-detection rather than failing.
    "qwenLanguage": "",
    "qwenTtsTimeoutSec": 900,
    # Qwen's 12 Hz codec can otherwise run to its 4096-token default (about
    # 5.5 minutes) when EOS is missed. Bound generation near each mouth window.
    "qwenCodecTokensPerSecond": 12.5,
    "qwenDurationTokenMargin": 1.35,
    "qwenMinGenerationTokens": 24,
    "qwenMaxGenerationTokens": 300,
    "whisperModel": "medium",
    # Apple Silicon runs Whisper through CTranslate2, which has no Metal backend
    # and no fp16 CPU kernel -- float16 is silently promoted to float32, doubling
    # resident size for no gain. int8 keeps `medium` near 1.5 GB.
    "whisperComputeType": "int8",
    # Pin to the performance-core count. CTranslate2 otherwise spreads OpenMP
    # threads across the efficiency cores too, and every parallel region then
    # waits on the slowest thread. 0 restores CTranslate2's own default.
    "whisperCpuThreads": 4,
    "whisperTimeoutSec": 7200,
    "demucsPath": str(BASE_DIR / "ml_venv" / "bin" / "demucs"),
    "mlPythonPath": str(BASE_DIR / "ml_venv" / "bin" / "python"),
    "diarizationModel": "pyannote/speaker-diarization-community-1",
    "diarizationDevice": "cpu",
    "diarizationTimeoutSec": 3600,
    "huggingFaceToken": "",
    "ytDlpPath": "",
    "separationModel": "htdemucs",
    # Demucs only auto-detects CUDA, so it lands on CPU here unless told
    # otherwise. Separation is the one stage that clearly benefits from the GPU.
    "separationDevice": "mps",
    "ffmpegPath": "ffmpeg",
    "enableTtsAiShortening": True,
    "enableTtsAiLengthening": True,
    "ttsMaxRetries": 3,
    "ttsMaxNaturalSpeed": 1.12,
    "allowMockAdaptation": False,
    "allowMockTranscription": False,
    "allowMockTTS": False
}

SENSITIVE_SETTING_KEYS = {
    "geminiApiKey", "googleTtsApiKey", "elevenlabsApiKey",
    "qwenApiKey", "huggingFaceToken",
}

try:
    if SETTINGS_PATH.exists():
        with open(SETTINGS_PATH, "r", encoding="utf-8") as settings_file:
            stored_settings = json.load(settings_file)
        API_SETTINGS.update({
            key: value for key, value in stored_settings.items()
            if key not in SENSITIVE_SETTING_KEYS
        })
except (OSError, json.JSONDecodeError):
    pass


def update_api_settings(settings: dict) -> None:
    API_SETTINGS.update(settings)
    persistent = {
        key: value for key, value in API_SETTINGS.items()
        if key not in SENSITIVE_SETTING_KEYS
    }
    with open(SETTINGS_PATH, "w", encoding="utf-8") as settings_file:
        json.dump(persistent, settings_file, indent=2)
