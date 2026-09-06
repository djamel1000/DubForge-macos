# DubForge macOS

DubForge is a native macOS AI dubbing studio. It analyzes video dialogue,
identifies speakers, adapts translations to their timing windows, generates
dubbed voice tracks, preserves background audio, and exports a mixed video.

## What it uses

- SwiftUI desktop application
- Local FastAPI processing backend
- Whisper transcription, Pyannote diarization, Demucs separation, and FFmpeg
- Gemini for timing-aware dialogue adaptation
- Qwen3-TTS (local), Google Cloud TTS, or ElevenLabs for speech generation

## Requirements

- macOS with Xcode
- Python 3.12 or 3.13
- FFmpeg available on `PATH` (for example, `brew install ffmpeg`)
- Apple Silicon is recommended for local Qwen3-TTS through MLX

Optional provider credentials are configured inside DubForge Settings and are
stored in the macOS Keychain. They are deliberately not kept in this repository.

Pyannote speaker diarization also requires a Hugging Face token after accepting
the model's access conditions on its Hugging Face model page.

## Local setup

```bash
git clone https://github.com/YOUR_ACCOUNT/DubForge-macos.git
cd DubForge-macos

python3 -m venv processing/venv
processing/venv/bin/pip install -r processing/requirements.txt

python3 -m venv processing/ml_venv
processing/ml_venv/bin/pip install -r processing/requirements-ml.txt
```

Open `DubForge.xcodeproj` in Xcode and run the `DubForge` scheme. The app starts
the local Python backend automatically. For development launches outside Xcode,
set `DUBFORGE_PROJECT_ROOT` to this repository path so the app can locate the
backend and its environments.

## Development notes

Runtime data is intentionally ignored by Git:

- Imported source media and generated exports
- Extracted, separated, and synthesized audio
- Qwen/MLX and Python virtual environments
- Saved projects, logs, local settings, and API credentials

The detailed original product requirements are in
`native_macos_ai_dubbing_app_full_spec.md`.
