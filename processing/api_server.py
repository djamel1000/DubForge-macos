import os
import re
import shutil
import uuid
import json
import threading
import subprocess
from pathlib import Path
from fastapi import FastAPI, BackgroundTasks, HTTPException, Body
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, List

from processing.config import (
    API_SETTINGS, PROJECTS_DIR, LOGS_DIR, UPLOADS_DIR,
    EXTRACTED_AUDIO_DIR, TRANSCRIPTS_DIR, SEPARATED_AUDIO_DIR,
    TTS_SEGMENTS_DIR, MIXES_DIR, EXPORTS_DIR, update_api_settings
)
from processing.services.ffmpeg_service import FFmpegService
from processing.services.subtitle_parser import SubtitleParser
from processing.services.whisper_service import WhisperService
from processing.services.diarization_service import DiarizationService
from processing.services.gemini_director import GeminiDirector
from processing.services.qwen_tts_service import QwenTTSService
from processing.services.google_tts_service import GoogleTTSService
from processing.services.elevenlabs_service import ElevenLabsService
from processing.services.duration_checker import DurationChecker
from processing.services.audio_separator import AudioSeparator
from processing.services.mixer_service import MixerService
from processing.services.speaker_reference_service import SpeakerReferenceService
from processing.services.quality_checker import QualityChecker
from processing.services.media_url_service import MediaURLService

app = FastAPI(title="DubForge macOS Local Server", version="1.0")

# Enable CORS for local app calls.
# Deliberately not a wildcard: this server has no authentication, so reflecting
# arbitrary origins would let any page the user browses drive the pipeline and
# read back project data. The native SwiftUI client uses URLSession and sends no
# Origin header, so it is unaffected by this list.
LOCAL_ORIGINS = [
    "http://127.0.0.1:8765",
    "http://localhost:8765",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=LOCAL_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Job registry for async polling
ACTIVE_JOBS = {}
JOBS_LOCK = threading.Lock()
ACTIVE_PROCESSES = {}
CANCELLED_JOBS = set()

class JobStatus(BaseModel):
    job_id: str
    status: str  # pending, running, completed, failed
    progress: float  # 0.0 to 100.0
    message: str
    result: Optional[dict] = None

# Helper to register and update jobs
def set_job(job_id: str, status: str, progress: float, message: str, result: dict = None):
    with JOBS_LOCK:
        existing = ACTIVE_JOBS.get(job_id)
        if existing and existing.get("status") == "cancelled" and status != "cancelled":
            return
        ACTIVE_JOBS[job_id] = {
            "job_id": job_id,
            "status": status,
            "progress": progress,
            "message": message,
            "result": result
        }

def get_job(job_id: str) -> Optional[dict]:
    with JOBS_LOCK:
        return ACTIVE_JOBS.get(job_id)

def set_job_process(job_id: str, process):
    with JOBS_LOCK:
        if process is None:
            ACTIVE_PROCESSES.pop(job_id, None)
        else:
            ACTIVE_PROCESSES[job_id] = process

def is_job_cancelled(job_id: str) -> bool:
    with JOBS_LOCK:
        return job_id in CANCELLED_JOBS

def log_event(filename: str, message: str):
    """Saves system events in specific log files."""
    log_path = LOGS_DIR / filename
    try:
        with open(log_path, 'a') as f:
            f.write(f"[{threading.current_thread().name}] {message}\n")
    except Exception:
        pass

def _language_hint(language: str) -> str:
    """Return a conservative language hint accepted by Whisper."""
    return (language or "").strip()

def _google_language_code(language: str) -> str:
    mapping = {
        "arabic": "ar-XA",
        "english": "en-US",
        "french": "fr-FR",
        "spanish": "es-ES",
        "german": "de-DE",
        "italian": "it-IT",
        "portuguese": "pt-PT",
        "japanese": "ja-JP",
        "korean": "ko-KR",
        "chinese (simplified)": "zh-CN",
        "chinese (traditional)": "zh-TW",
        "hindi": "hi-IN",
        "turkish": "tr-TR",
        "russian": "ru-RU",
    }
    return mapping.get((language or "").strip().lower(), "")

def _prepare_tts_settings_for_project(project: dict):
    provider = API_SETTINGS.get("ttsProvider", "qwen").lower()
    if provider == "google":
        target_code = _google_language_code(project.get("targetLanguage", ""))
        current_code = (API_SETTINGS.get("googleTtsLanguageCode") or "").strip()
        if target_code and (not current_code or current_code == "en-US" and project.get("targetLanguage") != "English"):
            API_SETTINGS["googleTtsLanguageCode"] = target_code


def _ensure_qwen_speaker_references(project_id: str, project: dict) -> dict:
    if API_SETTINGS.get("ttsProvider", "qwen").lower() != "qwen":
        return project

    speakers = project.get("speakers", [])
    if speakers and all(
        speaker.get("cloneReady")
        and os.path.exists(speaker.get("referenceAudioPath", ""))
        and (speaker.get("referenceText") or "").strip()
        for speaker in speakers
    ):
        return project

    video_path = project.get("inputVideoPath", "")
    if not video_path or not os.path.exists(video_path):
        return project

    base_name = os.path.splitext(os.path.basename(video_path))[0]
    source_audio = str(EXTRACTED_AUDIO_DIR / f"{base_name}_audio.wav")
    if not os.path.exists(source_audio):
        if not FFmpegService.extract_audio(video_path, source_audio):
            return project

    old_profiles = {
        segment.get("id"): segment.get("voiceProfileId")
        for segment in project.get("segments", [])
    }
    speakers, segments = SpeakerReferenceService.build_references(
        project_id,
        source_audio,
        speakers,
        project.get("segments", []),
    )
    for segment in segments:
        if old_profiles.get(segment.get("id")) != segment.get("voiceProfileId"):
            segment["generatedAudioPath"] = None
            segment["generatedDuration"] = None
            segment["fitStatus"] = "pending"
            segment["approved"] = False

    project["speakers"] = speakers
    project["segments"] = segments
    save_project_data(project_id, project)
    return project

# ----------------- Project Data Persistence Helper -----------------
# Project IDs are minted server-side as UUID4s by /projects/create, then flow
# from request bodies into filesystem paths for transcripts, separated audio,
# TTS output, speaker references, mixes and exports. Validating here — the one
# call every endpoint makes before building any other path — keeps a crafted id
# from escaping the storage tree. The pattern excludes "." and separators, so
# no traversal sequence can be expressed.
_PROJECT_ID_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}")


def _validated_project_id(project_id: str) -> str:
    candidate = (project_id or "").strip()
    if not _PROJECT_ID_PATTERN.fullmatch(candidate):
        raise HTTPException(status_code=400, detail="Invalid project id.")
    return candidate


def load_project_data(project_id: str) -> dict:
    path = PROJECTS_DIR / f"{_validated_project_id(project_id)}.json"
    if not path.exists():
        raise HTTPException(status_code=404, detail="Project not found")
    with open(path, 'r') as f:
        return json.load(f)

def save_project_data(project_id: str, data: dict):
    path = PROJECTS_DIR / f"{_validated_project_id(project_id)}.json"
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)

ANALYSIS_STAGE_DEFAULTS = {
    "extractAudio": "pending",
    "transcription": "pending",
    "diarization": "pending",
    "integration": "pending",
}

def new_analysis_status() -> dict:
    return {
        **ANALYSIS_STAGE_DEFAULTS,
        "failedStage": None,
        "message": None,
    }

def checkpoint_analysis(project_id: str, project: dict, stage: str, status: str, message: str) -> dict:
    analysis = project.setdefault("analysisStatus", new_analysis_status())
    for key, default in ANALYSIS_STAGE_DEFAULTS.items():
        analysis.setdefault(key, default)
    analysis[stage] = status
    analysis["message"] = message
    analysis["failedStage"] = stage if status == "failed" else None
    save_project_data(project_id, project)
    return {"project": project}

# ----------------- FastAPI Models -----------------
class CreateProjectReq(BaseModel):
    name: str
    sourceLanguage: str
    targetLanguage: str
    inputVideoPath: str
    subtitlePath: Optional[str] = None

class MediaURLReq(BaseModel):
    source_url: str

# ----------------- Health / Ping -----------------

@app.get("/health")
@app.get("/ping")
def health():
    return {"status": "ok", "version": "1.0", "server": "DubForge macOS"}


@app.get("/ml/status")
def ml_status():
    ml_python = os.path.expanduser(API_SETTINGS.get("mlPythonPath", ""))
    demucs_path = os.path.expanduser(API_SETTINGS.get("demucsPath", ""))
    import_check = {"pyannote": False, "torch": False, "mps": False, "faster_whisper": False}
    if ml_python and os.path.exists(ml_python):
        try:
            result = subprocess.run(
                [
                    ml_python,
                    "-c",
                    "import json,importlib.util,torch,pyannote.audio;print(json.dumps({"
                    "'pyannote':True,'torch':True,'mps':torch.backends.mps.is_available(),"
                    "'faster_whisper':importlib.util.find_spec('faster_whisper') is not None}))",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            if result.returncode == 0:
                import_check = json.loads(result.stdout.strip().splitlines()[-1])
        except Exception:
            pass

    model_cache = Path.home() / ".cache" / "huggingface" / "hub" / "models--pyannote--speaker-diarization-community-1"
    return {
        "mlPythonPath": ml_python,
        "mlPythonReady": bool(ml_python and os.path.exists(ml_python)),
        "pyannoteInstalled": import_check.get("pyannote", False),
        "torchInstalled": import_check.get("torch", False),
        "metalAvailable": import_check.get("mps", False),
        "fasterWhisperInstalled": import_check.get("faster_whisper", False),
        "diarizationModel": API_SETTINGS.get("diarizationModel"),
        "diarizationModelCached": model_cache.exists(),
        "huggingFaceTokenConfigured": bool(API_SETTINGS.get("huggingFaceToken")),
        "demucsPath": demucs_path,
        "demucsReady": bool(demucs_path and os.path.exists(demucs_path)),
    }


@app.get("/media/url/status")
def media_url_status():
    try:
        command = MediaURLService._yt_dlp_command()
        completed = subprocess.run(
            command + ["--version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        return {
            "ready": completed.returncode == 0,
            "version": completed.stdout.strip() if completed.returncode == 0 else "",
        }
    except Exception as exc:
        return {"ready": False, "version": "", "error": str(exc)}


@app.post("/media/url/inspect")
def inspect_media_url(req: MediaURLReq):
    try:
        return MediaURLService.inspect(req.source_url)
    except (ValueError, RuntimeError) as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


def run_media_url_download(job_id: str, source_url: str):
    set_job(job_id, "running", 1.0, "Inspecting video link")

    def update_progress(progress: float, message: str):
        set_job(job_id, "running", progress, message)

    def set_process(process):
        set_job_process(job_id, process)

    try:
        result = MediaURLService.download(
            source_url,
            update_progress,
            lambda: is_job_cancelled(job_id),
            set_process,
        )
        set_job(job_id, "completed", 100.0, "Video link imported", result)
        log_event("media_import.log", f"URL import completed for job {job_id}: {result.get('path')}")
    except InterruptedError:
        set_job(job_id, "cancelled", 100.0, "Download cancelled by user")
    except Exception as exc:
        set_job(job_id, "failed", 100.0, str(exc))
        log_event("errors.log", f"URL import job {job_id} failed: {exc}")
    finally:
        set_job_process(job_id, None)


@app.post("/media/url/download")
def download_media_url(req: MediaURLReq):
    try:
        MediaURLService.validate_url(req.source_url)
        MediaURLService._yt_dlp_command()
    except (ValueError, RuntimeError) as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    job_id = str(uuid.uuid4())
    with JOBS_LOCK:
        CANCELLED_JOBS.discard(job_id)
    set_job(job_id, "pending", 0.0, "Video download queued")
    threading.Thread(
        target=run_media_url_download,
        args=(job_id, req.source_url),
        name=f"media-url-{job_id[:8]}",
        daemon=True,
    ).start()
    return {"job_id": job_id}

# ----------------- API Endpoints -----------------

@app.post("/projects/create")
def create_project(req: CreateProjectReq):
    project_id = str(uuid.uuid4())
    project_data = {
        "projectId": project_id,
        "name": req.name,
        "sourceLanguage": req.sourceLanguage,
        "targetLanguage": req.targetLanguage,
        "inputVideoPath": req.inputVideoPath,
        "subtitlePath": req.subtitlePath,
        "pipelineStage": "Import",
        "analysisStatus": new_analysis_status(),
        "speakers": [],
        "segments": [],
        "mix": {
            "voiceRemovalStrength": "Medium",
            "vocalStemGainDb": -80.0,
            "backgroundGainDb": 0.0,
            "dubbedVoiceGainDb": 0.0,
            "duckingEnabled": True,
            "duckingAmountDb": 4.0,
            "duckingAttackMs": 80.0,
            "duckingReleaseMs": 250.0,
            "limiterEnabled": True,
            "targetLoudness": "-16 LUFS Web Video"
        },
        "export": {
            "videoFormat": "MP4 H.264",
            "audioFormat": "AAC 320 kbps",
            "includeProjectJson": True,
            "includeStems": False,
            "includeSubtitles": True,
            "burnInSubtitles": False
        }
    }
    save_project_data(project_id, project_data)
    log_event("project.log", f"Created project '{req.name}' with ID {project_id}")
    return project_data

@app.get("/projects/{project_id}")
def get_project(project_id: str):
    return load_project_data(project_id)

@app.post("/projects/{project_id}/save")
def save_project(project_id: str, project: dict = Body(...)):
    if project.get("projectId") != project_id:
        raise HTTPException(status_code=400, detail="Project ID mismatch")
    save_project_data(project_id, project)
    log_event("project.log", f"Saved project '{project.get('name', project_id)}' with ID {project_id}")
    return {"status": "success", "project": project}

@app.post("/settings/update")
def update_settings(settings: dict = Body(...)):
    """Updates API Keys and local model configuration paths."""
    update_api_settings(settings)
    return {"status": "success"}


@app.get("/gemini/models")
def list_gemini_models():
    """
    Fetches all available Gemini and Gemma models from the Google Generative
    Language API using the stored API key. Returns a curated list of models
    suitable for text generation (dubbing direction).
    Falls back to a static curated list when the key is absent or the request fails.
    """
    import requests as _req

    STATIC_FALLBACK = [
        {"id": "gemini-2.5-pro-preview-05-06",  "display": "Gemini 2.5 Pro Preview",       "provider": "gemini"},
        {"id": "gemini-2.5-flash-preview-05-20", "display": "Gemini 2.5 Flash Preview",     "provider": "gemini"},
        {"id": "gemini-2.0-flash",               "display": "Gemini 2.0 Flash",              "provider": "gemini"},
        {"id": "gemini-2.0-flash-lite",          "display": "Gemini 2.0 Flash Lite",         "provider": "gemini"},
        {"id": "gemini-1.5-pro",                 "display": "Gemini 1.5 Pro",                "provider": "gemini"},
        {"id": "gemini-1.5-flash",               "display": "Gemini 1.5 Flash",              "provider": "gemini"},
        {"id": "gemini-1.5-flash-8b",            "display": "Gemini 1.5 Flash-8B",           "provider": "gemini"},
        {"id": "gemma-3-27b-it",                 "display": "Gemma 3 27B Instruct",          "provider": "gemma"},
        {"id": "gemma-3-12b-it",                 "display": "Gemma 3 12B Instruct",          "provider": "gemma"},
        {"id": "gemma-3-4b-it",                  "display": "Gemma 3 4B Instruct",           "provider": "gemma"},
        {"id": "gemma-3-1b-it",                  "display": "Gemma 3 1B Instruct",           "provider": "gemma"},
        {"id": "gemma-3n-e4b-it",                "display": "Gemma 3n E4B Instruct",         "provider": "gemma"},
    ]

    api_key = API_SETTINGS.get("geminiApiKey", "").strip()
    if not api_key:
        return {"models": STATIC_FALLBACK, "source": "static_fallback", "reason": "no_api_key"}

    try:
        url = f"https://generativelanguage.googleapis.com/v1beta/models?key={api_key}&pageSize=100"
        resp = _req.get(url, timeout=8)
        if resp.status_code != 200:
            return {"models": STATIC_FALLBACK, "source": "static_fallback", "reason": f"api_error_{resp.status_code}"}

        raw = resp.json().get("models", [])

        # Filter to text-generation capable models only (generateContent support)
        generation_models = []
        for m in raw:
            name = m.get("name", "")          # "models/gemini-1.5-pro"
            model_id = name.replace("models/", "")
            supported = m.get("supportedGenerationMethods", [])

            if "generateContent" not in supported:
                continue

            # Keep only Gemini and Gemma models (exclude embedding, vision-only, etc.)
            base = model_id.lower()
            if not (base.startswith("gemini") or base.startswith("gemma")):
                continue

            # Build friendly display name from model metadata
            display = m.get("displayName") or model_id
            provider = "gemma" if base.startswith("gemma") else "gemini"

            generation_models.append({
                "id": model_id,
                "display": display,
                "provider": provider,
                "inputTokenLimit": m.get("inputTokenLimit"),
                "outputTokenLimit": m.get("outputTokenLimit"),
            })

        # Sort: gemini first, then gemma; latest versions first
        generation_models.sort(key=lambda x: (
            0 if x["provider"] == "gemini" else 1,
            x["id"]
        ), reverse=False)

        if not generation_models:
            return {"models": STATIC_FALLBACK, "source": "static_fallback", "reason": "no_matching_models"}

        return {"models": generation_models, "source": "live_api", "count": len(generation_models)}

    except Exception as e:
        log_event("errors.log", f"Failed to fetch Gemini models: {e}")
        return {"models": STATIC_FALLBACK, "source": "static_fallback", "reason": str(e)}

# Async Job executor for analysis
def run_analysis_task(job_id: str, project_id: str):
    proj = None
    current_stage = "extractAudio"
    current_progress = 5.0
    try:
        proj = load_project_data(project_id)
        proj["analysisStatus"] = new_analysis_status()
        result = checkpoint_analysis(
            project_id, proj, current_stage, "running", "Extracting video audio streams..."
        )
        set_job(job_id, "running", current_progress, "Extracting video audio streams...", result)
        
        video_path = proj["inputVideoPath"]
        if not os.path.exists(video_path):
            raise FileNotFoundError(f"Source video file not found at: {video_path}")
            
        base_name = os.path.splitext(os.path.basename(video_path))[0]
        
        # 1. Extract audio tracks
        audio_out = str(EXTRACTED_AUDIO_DIR / f"{base_name}_audio.wav")
        whisper_out = str(EXTRACTED_AUDIO_DIR / f"{base_name}_whisper.wav")
        
        if not FFmpegService.extract_audio(video_path, audio_out):
            raise RuntimeError("FFmpeg failed to extract source audio.")
        checkpoint_analysis(project_id, proj, "extractAudio", "completed", "Audio extraction completed.")
        current_stage = "transcription"
        current_progress = 30.0
        result = checkpoint_analysis(
            project_id, proj, current_stage, "running", "Running Whisper speech transcription..."
        )
        set_job(job_id, "running", current_progress, "Running Whisper speech transcription...", result)
        
        # 2. Transcription / Subtitle Parsing
        raw_segments = []
        if proj.get("subtitlePath") and os.path.exists(proj["subtitlePath"]):
            log_event("audio_processing.log", f"Parsing local subtitle file: {proj['subtitlePath']}")
            raw_segments = SubtitleParser.parse(proj["subtitlePath"])
        else:
            log_event("audio_processing.log", "No local subtitle path provided. Invoking Whisper transcription...")
            if not FFmpegService.extract_whisper_audio(video_path, whisper_out):
                raise RuntimeError("FFmpeg failed to prepare Whisper audio.")
            raw_segments = WhisperService.transcribe(
                whisper_out,
                model_size=API_SETTINGS.get("whisperModel", "medium"),
                language=_language_hint(proj.get("sourceLanguage", "")),
            )

        if not raw_segments:
            raise RuntimeError("Transcription produced no segments.")

        checkpoint_analysis(project_id, proj, "transcription", "completed", "Speech transcription completed.")
        current_stage = "diarization"
        current_progress = 60.0
        result = checkpoint_analysis(
            project_id, proj, current_stage, "running", "Detecting speakers and diarizing..."
        )
        set_job(job_id, "running", current_progress, "Detecting speakers and diarizing...", result)
        
        # 3. Speaker Diarization
        speaker_regions = DiarizationService.diarize(audio_out, project_id=project_id)

        checkpoint_analysis(project_id, proj, "diarization", "completed", "Speaker diarization completed.")
        current_stage = "integration"
        current_progress = 80.0
        result = checkpoint_analysis(
            project_id, proj, current_stage, "running", "Merging transcripts with speaker tracks..."
        )
        set_job(job_id, "running", current_progress, "Merging transcripts with speaker tracks...", result)
        
        # 4. Merge transcripts and speakers
        merged_segments = DiarizationService.merge_segments_with_speakers(raw_segments, speaker_regions)
        
        # Build unique speakers registry
        speakers = []
        speaker_ids = set([s["speakerId"] for s in merged_segments])
        
        colors = ["#C0C1FF", "#FFB783", "#9BE7B1", "#FFB4AB", "#C7C4D7"]
        for idx, sp_id in enumerate(sorted(speaker_ids)):
            speakers.append({
                "speakerId": sp_id,
                "displayName": f"Speaker {idx+1}",
                "characterName": f"Character {idx+1}",
                "genderStyle": "Original voice",
                "ageStyle": "Auto",
                "personalityStyle": "Neutral",
                "color": colors[idx % len(colors)],
                "voiceProfileId": f"qwen_voice_{sp_id.lower()}",
                "segmentCount": len([s for s in merged_segments if s["speakerId"] == sp_id]),
                "totalSpeakingTime": round(sum([s["duration"] for s in merged_segments if s["speakerId"] == sp_id]), 2),
                "confidence": 0.90
            })

        speakers, merged_segments = SpeakerReferenceService.build_references(
            project_id,
            audio_out,
            speakers,
            merged_segments,
        )
            
        # Update project data
        proj["segments"] = merged_segments
        proj["speakers"] = speakers
        proj["pipelineStage"] = "Transcript"
        checkpoint_analysis(project_id, proj, "integration", "completed", "Analysis complete. Ready for review.")
        
        set_job(job_id, "completed", 100.0, "Analysis complete! Ready for Review.", {"project": proj})
        log_event("project.log", f"Project {project_id} analysis completed successfully.")
        
    except Exception as e:
        log_event("errors.log", f"Analysis job {job_id} failed: {e}")
        message = f"Analysis failed: {str(e)}"
        result = None
        if proj is not None:
            result = checkpoint_analysis(project_id, proj, current_stage, "failed", message)
        set_job(job_id, "failed", current_progress, message, result)

@app.post("/media/extract-audio")
def start_analysis(project_id: str = Body(..., embed=True), background_tasks: BackgroundTasks = BackgroundTasks()):
    job_id = str(uuid.uuid4())
    set_job(job_id, "pending", 0.0, "Queued project media analysis...")
    background_tasks.add_task(run_analysis_task, job_id, project_id)
    return {"job_id": job_id}

# Async Job executor for Gemini Dialogue Adaptation
def run_adaptation_task(job_id: str, project_id: str):
    try:
        set_job(job_id, "running", 5.0, "Starting Gemini director adaptation...")
        proj = load_project_data(project_id)
        segments = proj["segments"]
        speakers_dict = {s["speakerId"]: s for s in proj["speakers"]}
        
        total = len(segments)
        for idx, seg in enumerate(segments):
            # Skip locked segments
            if seg.get("locked"):
                continue
            dub_text = (seg.get("dubText") or "").strip()
            source_text = (seg.get("sourceText") or "").strip()
            needs_translation = (
                proj.get("sourceLanguage") != proj.get("targetLanguage")
                and (not dub_text or dub_text == source_text)
            )
            if dub_text and not needs_translation:
                continue
                
            prev_seg = segments[idx - 1] if idx > 0 else None
            next_seg = segments[idx + 1] if idx < total - 1 else None
            speaker = speakers_dict.get(seg["speakerId"], {})
            
            set_job(job_id, "running", 5.0 + (idx / total * 85.0), f"Director adapting line {idx+1}/{total}...")
            
            adapted = GeminiDirector.adapt_segment(
                seg, speaker, prev_seg, next_seg,
                src_lang=proj["sourceLanguage"],
                tgt_lang=proj["targetLanguage"]
            )
            
            # Apply adapted parameters
            seg["dubText"] = adapted.get("dub_text", seg["sourceText"])
            seg["literalTranslation"] = adapted.get("literal_translation", "")
            seg["emotion"] = adapted.get("emotion", "neutral")
            seg["performanceInstruction"] = adapted.get("performance_instruction", "")
            seg["qwenInstruction"] = adapted.get("qwen_instruction", "")
            seg["fitStatus"] = "pending"
            seg["warnings"] = seg.get("warnings", [])
            
            log_event("gemini_requests.log", f"Segment {seg['id']} adapted successfully.")
            save_project_data(project_id, proj)
            
        proj["pipelineStage"] = "AI Director"
        save_project_data(project_id, proj)
        set_job(job_id, "completed", 100.0, "Dialogue adaptation completed!", {"project": proj})
        
    except Exception as e:
        log_event("errors.log", f"Adaptation failed: {e}")
        set_job(job_id, "failed", 100.0, f"Adaptation failed: {str(e)}")

@app.post("/gemini/adapt")
def start_adaptation(project_id: str = Body(..., embed=True), background_tasks: BackgroundTasks = BackgroundTasks()):
    job_id = str(uuid.uuid4())
    set_job(job_id, "pending", 0.0, "Queued dialogue translation...")
    background_tasks.add_task(run_adaptation_task, job_id, project_id)
    return {"job_id": job_id}


def _generate_segment_with_timing(seg: dict, proj: dict, project_id: str, speaker: dict) -> dict:
    """Synthesizes, rewrites, and aligns one segment without manual intervention."""
    target_duration = max(0.1, float(seg.get("duration") or 0.1))
    current_dub_text = (seg.get("dubText") or "").strip()
    retry_count = 0
    accumulated_warnings = []

    audio_path = _synthesize_segment(
        seg, speed=1.0, project_id=project_id, speaker=speaker
    )
    status, gen_dur, warnings = DurationChecker.check_fit(target_duration, audio_path)
    accumulated_warnings.extend(warnings)

    best_audio_path = ""
    best_text = current_dub_text
    best_duration = gen_dur
    best_status = status
    best_score = abs(gen_dur - target_duration) / target_duration if gen_dur else float("inf")

    def preserve_if_better(candidate_path: str, candidate_duration: float, candidate_status: str, candidate_text: str):
        nonlocal best_audio_path, best_text, best_duration, best_status, best_score
        if not candidate_duration:
            return
        score = abs(candidate_duration - target_duration) / target_duration
        if candidate_status == "too_long":
            score += 0.03
        if score > best_score:
            return
        root, extension = os.path.splitext(candidate_path)
        snapshot = f"{root}_bestfit{extension or '.wav'}"
        shutil.copy2(candidate_path, snapshot)
        best_audio_path = snapshot
        best_text = candidate_text
        best_duration = candidate_duration
        best_status = candidate_status
        best_score = score

    preserve_if_better(audio_path, gen_dur, status, current_dub_text)

    max_retries = max(0, int(API_SETTINGS.get("ttsMaxRetries", 3)))
    while status == "too_long" and retry_count < max_retries:
        retry_count += 1
        log_event(
            "tts_generation.log",
            f"Segment {seg['id']} too long ({gen_dur}s > {target_duration}s). Retry {retry_count}...",
        )
        if not API_SETTINGS.get("enableTtsAiShortening", True):
            accumulated_warnings.append("AI shortening is disabled.")
            break

        try:
            shortened = GeminiDirector.shorten_for_duration(
                source_text=seg.get("sourceText", ""),
                current_dub_text=current_dub_text,
                target_language=proj.get("targetLanguage", ""),
                target_duration=target_duration,
                measured_duration=float(gen_dur),
                speaker=speaker,
            )
            candidate = (shortened.get("dub_text") or "").strip()
        except Exception as shorten_error:
            accumulated_warnings.append(f"AI shortening unavailable: {shorten_error}")
            break

        if not candidate or candidate == current_dub_text:
            accumulated_warnings.append("AI returned no shorter alternative.")
            break

        current_dub_text = candidate
        seg["dubText"] = candidate
        audio_path = _synthesize_segment(
            seg,
            speed=1.0,
            text_override=candidate,
            project_id=project_id,
            speaker=speaker,
        )
        status, gen_dur, retry_warnings = DurationChecker.check_fit(target_duration, audio_path)
        accumulated_warnings.extend(retry_warnings)
        preserve_if_better(audio_path, gen_dur, status, candidate)

    while status == "too_short" and retry_count < max_retries:
        retry_count += 1
        log_event(
            "tts_generation.log",
            f"Segment {seg['id']} too short ({gen_dur}s < {target_duration}s). Retry {retry_count}...",
        )
        if not API_SETTINGS.get("enableTtsAiLengthening", True):
            accumulated_warnings.append("AI expansion is disabled.")
            break

        try:
            expanded = GeminiDirector.lengthen_for_duration(
                source_text=seg.get("sourceText", ""),
                current_dub_text=current_dub_text,
                target_language=proj.get("targetLanguage", ""),
                target_duration=target_duration,
                measured_duration=float(gen_dur),
                speaker=speaker,
            )
            candidate = (expanded.get("dub_text") or "").strip()
        except Exception as expand_error:
            accumulated_warnings.append(f"AI expansion unavailable: {expand_error}")
            break

        if not candidate or candidate == current_dub_text:
            accumulated_warnings.append("AI returned no longer alternative.")
            break

        current_dub_text = candidate
        seg["dubText"] = candidate
        audio_path = _synthesize_segment(
            seg,
            speed=1.0,
            text_override=candidate,
            project_id=project_id,
            speaker=speaker,
        )
        status, gen_dur, retry_warnings = DurationChecker.check_fit(target_duration, audio_path)
        accumulated_warnings.extend(retry_warnings)
        preserve_if_better(audio_path, gen_dur, status, candidate)

    if best_audio_path:
        audio_path = best_audio_path
        gen_dur = best_duration
        status = best_status
        seg["dubText"] = best_text

    if status == "too_long":
        speed_factor = max(1.0, gen_dur / target_duration)
        configured_limit = float(API_SETTINGS.get("ttsMaxNaturalSpeed", 1.12))
        if target_duration < 1.0:
            max_natural_speed = max(configured_limit, 1.35)
        elif target_duration < 2.0:
            max_natural_speed = max(configured_limit, 1.25)
        else:
            max_natural_speed = configured_limit
        root, _ = os.path.splitext(audio_path)
        adjusted_path = f"{root}_timefit.wav"
        if speed_factor <= max_natural_speed and DurationChecker.apply_speed_or_padding(
            audio_path, adjusted_path, speed_factor=speed_factor
        ):
            audio_path = adjusted_path
            status, gen_dur, fit_warnings = DurationChecker.check_fit(target_duration, audio_path)
            accumulated_warnings.extend(fit_warnings)
            accumulated_warnings.append(
                f"Time-compressed generated speech by {speed_factor:.2f}x to fit segment bounds."
            )
        else:
            status = "needs_review"
            accumulated_warnings.append(
                f"Still too long after semantic rewrites; required {speed_factor:.2f}x speed "
                f"exceeds the natural limit of {max_natural_speed:.2f}x."
            )

    if status == "too_short":
        status = "needs_review"
        accumulated_warnings.append(
            "Still too short after semantic expansion; refusing to hide the mismatch with excessive silence."
        )

    if status == "fits":
        resolved_fit_warnings = {
            "Segment is significantly shorter than original (over 30% gap).",
            "Segment is too long to fit in mouth movement window.",
        }
        accumulated_warnings = [
            warning for warning in accumulated_warnings
            if warning not in resolved_fit_warnings
        ]

    seg["generatedAudioPath"] = audio_path
    seg["generatedDuration"] = gen_dur
    seg["fitStatus"] = status
    seg["warnings"] = list(dict.fromkeys(accumulated_warnings))
    seg["retryCount"] = retry_count
    seg["approved"] = status == "fits"
    return seg

# Async Job executor for TTS Generation
def run_tts_generation_task(job_id: str, project_id: str):
    try:
        provider = API_SETTINGS.get("ttsProvider", "qwen").lower()
        provider_name = {
            "google": "Google Cloud TTS",
            "elevenlabs": "ElevenLabs",
            "qwen": "Qwen3-TTS",
        }.get(provider, provider)
        set_job(job_id, "running", 5.0, f"Starting {provider_name} generation loop...")
        proj = load_project_data(project_id)
        _prepare_tts_settings_for_project(proj)
        proj = _ensure_qwen_speaker_references(project_id, proj)
        segments = proj["segments"]
        speakers_dict = {s["speakerId"]: s for s in proj.get("speakers", [])}

        missing_adapted = [
            str(seg.get("id"))
            for seg in segments
            if (
                proj.get("sourceLanguage") != proj.get("targetLanguage")
                and (
                    not (seg.get("dubText") or "").strip()
                    or (seg.get("dubText") or "").strip() == (seg.get("sourceText") or "").strip()
                )
            )
        ]
        if missing_adapted:
            preview = ", ".join(missing_adapted[:8])
            raise RuntimeError(
                f"Target-language dub text is missing for segment(s) {preview}. "
                "Run AI Director adaptation before TTS generation."
            )
        
        # Audio length checking and alignment loop
        total = len(segments)
        for idx, seg in enumerate(segments):
            if seg.get("locked") and seg.get("generatedAudioPath"):
                continue
            if seg.get("generatedAudioPath") and seg.get("fitStatus") in ("fits", "approved"):
                continue
                
            set_job(job_id, "running", 5.0 + (idx / total * 90.0), f"Synthesizing expressive voice {idx+1}/{total}...")
            
            speaker = speakers_dict.get(seg.get("speakerId"), {})
            _generate_segment_with_timing(seg, proj, project_id, speaker)
            save_project_data(project_id, proj)
            
        proj["pipelineStage"] = "Dubbing"
        save_project_data(project_id, proj)
        set_job(job_id, "completed", 100.0, "Speech synthesis complete!", {"project": proj})
        
    except Exception as e:
        log_event("errors.log", f"TTS Generation failed: {e}")
        set_job(job_id, "failed", 100.0, f"Synthesis failed: {str(e)}")

@app.get("/tts/providers")
def list_tts_providers():
    """Returns the list of supported TTS providers and the currently selected one.

    Each provider reports readiness so an unusable engine is visible before a run
    starts, rather than after transcription and translation have been paid for.
    """
    return {
        "current": API_SETTINGS.get("ttsProvider", "qwen"),
        "providers": [
            {
                "id": "qwen",
                "name": "Qwen3-TTS (Local)",
                "description": "Runs on-device through MLX, no API cost and no server to start",
                "ready": QwenTTSService.quick_ready(),
            },
            {
                "id": "google",
                "name": "Google Cloud TTS",
                "description": "Neural2, WaveNet, Studio voices",
                "ready": bool(API_SETTINGS.get("googleTtsApiKey", "").strip()),
            },
            {
                "id": "elevenlabs",
                "name": "ElevenLabs",
                "description": "Highest-quality expressive voices",
                "ready": bool(API_SETTINGS.get("elevenlabsApiKey", "").strip()),
            },
        ]
    }


@app.get("/tts/qwen/status")
def qwen_tts_status():
    """Full local Qwen3-TTS readiness probe, including the MLX package check."""
    return QwenTTSService.readiness()


@app.get("/tts/google/voices")
def list_google_voices(language_code: str = ""):
    """Lists available Google Cloud TTS voices."""
    api_key = API_SETTINGS.get("googleTtsApiKey", "").strip()
    voices = GoogleTTSService.list_voices(api_key, language_code)
    simplified = [
        {
            "name": v.get("name"),
            "languageCodes": v.get("languageCodes", []),
            "ssmlGender": v.get("ssmlGender"),
            "naturalSampleRateHertz": v.get("naturalSampleRateHertz"),
        }
        for v in voices
    ]
    return {"voices": simplified, "count": len(simplified)}


@app.get("/tts/elevenlabs/voices")
def list_elevenlabs_voices():
    """Lists available ElevenLabs voices for the configured account."""
    api_key = API_SETTINGS.get("elevenlabsApiKey", "").strip()
    voices = ElevenLabsService.list_voices(api_key)
    simplified = [
        {
            "voice_id": v.get("voice_id"),
            "name": v.get("name"),
            "category": v.get("category"),
            "labels": v.get("labels", {}),
        }
        for v in voices
    ]
    return {"voices": simplified, "count": len(simplified)}


@app.get("/tts/elevenlabs/models")
def list_elevenlabs_models():
    """Lists available ElevenLabs TTS models."""
    api_key = API_SETTINGS.get("elevenlabsApiKey", "").strip()
    models = ElevenLabsService.list_models(api_key)
    return {"models": models}


@app.post("/tts/generate-all")
def start_tts_generation(project_id: str = Body(..., embed=True), background_tasks: BackgroundTasks = BackgroundTasks()):
    job_id = str(uuid.uuid4())
    set_job(job_id, "pending", 0.0, "Queued speech synthesis...")
    background_tasks.add_task(run_tts_generation_task, job_id, project_id)
    return {"job_id": job_id}

# Single segment manual adaptation endpoints
@app.post("/tts/generate-segment")
def generate_segment(payload: dict = Body(...)):
    project_id = payload.get("project_id")
    segment = dict(payload.get("segment", payload))
    speaker = {}
    project = None
    try:
        if project_id:
            project = load_project_data(project_id)
            _prepare_tts_settings_for_project(project)
            project = _ensure_qwen_speaker_references(project_id, project)
            dub_text = (segment.get("dubText") or "").strip()
            source_text = (segment.get("sourceText") or "").strip()
            if (
                project.get("sourceLanguage") != project.get("targetLanguage")
                and (not dub_text or dub_text == source_text)
            ):
                raise HTTPException(
                    status_code=400,
                    detail=(
                        f"Target-language text is missing for segment {segment.get('id')}. "
                        "Run AI Director adaptation or enter translated dialogue before TTS generation."
                    ),
                )
            speaker = next(
                (item for item in project.get("speakers", []) if item.get("speakerId") == segment.get("speakerId")),
                {},
            )
        result_segment = _generate_segment_with_timing(
            segment,
            project or {
                "sourceLanguage": "",
                "targetLanguage": "",
                "segments": [segment],
            },
            project_id or "manual",
            speaker,
        )
        if project_id and project is not None:
            for index, item in enumerate(project.get("segments", [])):
                if item.get("id") == result_segment.get("id"):
                    project["segments"][index] = result_segment
                    break
            save_project_data(project_id, project)
        return {
            "status": result_segment.get("fitStatus", "failed"),
            "generated_duration": result_segment.get("generatedDuration"),
            "generated_audio_path": result_segment.get("generatedAudioPath"),
            "warnings": result_segment.get("warnings", []),
            "dub_text": result_segment.get("dubText", ""),
            "retry_count": result_segment.get("retryCount", 0),
        }
    except HTTPException:
        raise
    except Exception as e:
        log_event("errors.log", f"Segment TTS generation failed: {e}")
        return {
            "status": "failed",
            "generated_duration": None,
            "generated_audio_path": None,
            "warnings": [str(e)]
        }


def _synthesize_segment(
    seg: dict,
    speed: float = 1.0,
    text_override: str = None,
    project_id: str = "unassigned",
    speaker: dict = None,
) -> str:
    """
    Routes TTS synthesis to the provider configured in API_SETTINGS["ttsProvider"].
    Providers: 'qwen' (default) | 'google' | 'elevenlabs'
    """
    provider = API_SETTINGS.get("ttsProvider", "qwen").lower()
    text = text_override or seg.get("dubText") or seg.get("sourceText", "")
    segment_id = seg.get("id", 1)
    target_duration = seg.get("duration", 3.0)
    speaker = speaker or {}

    if provider == "google":
        return GoogleTTSService.generate(
            text=text,
            voice_name=API_SETTINGS.get("googleTtsVoiceName", ""),
            language_code=API_SETTINGS.get("googleTtsLanguageCode", "en-US"),
            speaking_rate=speed,
            pitch=float(API_SETTINGS.get("googleTtsPitch", 0)),
            target_duration=target_duration,
            segment_id=segment_id,
            project_id=project_id,
        )
    elif provider == "elevenlabs":
        voice_id = seg.get("voiceProfileId") or ""
        if voice_id.startswith("qwen_voice_"):
            voice_id = ""
        return ElevenLabsService.generate(
            text=text,
            voice_id=voice_id or API_SETTINGS.get("elevenlabsVoiceId", ""),
            model_id=API_SETTINGS.get("elevenlabsModelId", "eleven_multilingual_v2"),
            stability=float(API_SETTINGS.get("elevenlabsStability", 0.5)),
            similarity_boost=float(API_SETTINGS.get("elevenlabsSimilarityBoost", 0.75)),
            style=float(API_SETTINGS.get("elevenlabsStyle", 0.0)),
            speed=speed,
            target_duration=target_duration,
            segment_id=segment_id,
            project_id=project_id,
        )
    else:
        # Default: Qwen3-TTS
        return QwenTTSService.generate(
            text=text,
            instruction=seg.get("qwenInstruction", ""),
            voice_profile_id=seg.get("voiceProfileId", ""),
            speed=speed,
            target_duration=target_duration,
            segment_id=segment_id,
            project_id=project_id,
            reference_audio_path=speaker.get("referenceAudioPath", ""),
            reference_text=speaker.get("referenceText", ""),
        )

# Source Separation Async Job
def run_separation_task(job_id: str, project_id: str):
    try:
        set_job(job_id, "running", 10.0, "Isolating audio track background layers...")
        proj = load_project_data(project_id)
        
        video_path = proj["inputVideoPath"]
        base_name = os.path.splitext(os.path.basename(video_path))[0]
        audio_path = str(EXTRACTED_AUDIO_DIR / f"{base_name}_audio.wav")
        
        if not os.path.exists(audio_path):
            if not FFmpegService.extract_audio(video_path, audio_path):
                raise RuntimeError("FFmpeg failed to extract source audio.")
            
        set_job(job_id, "running", 30.0, "Executing sound isolation stems...")
        
        vocals, background, risk = AudioSeparator.separate(audio_path, project_id=project_id)

        speakers, segments = SpeakerReferenceService.build_references(
            project_id,
            vocals,
            proj.get("speakers", []),
            proj.get("segments", []),
        )
        for segment in segments:
            segment["generatedAudioPath"] = None
            segment["generatedDuration"] = None
            segment["fitStatus"] = "pending"
            segment["approved"] = False
        proj["speakers"] = speakers
        proj["segments"] = segments
        
        proj["pipelineStage"] = "Mixing"
        proj["mix"]["backgroundDamageRisk"] = risk
        proj["mix"]["backgroundPath"] = background
        proj["mix"]["vocalResidualPath"] = vocals
        proj["mix"]["vocalStemGainDb"] = -80.0
        save_project_data(project_id, proj)
        
        set_job(job_id, "completed", 100.0, "Voice isolation completed!", {
            "vocals_path": vocals,
            "background_path": background,
            "background_damage_risk": risk
        })
        
    except Exception as e:
        log_event("errors.log", f"Separation failed: {e}")
        set_job(job_id, "failed", 100.0, f"Separation failed: {str(e)}")

@app.post("/audio/separate")
def start_separation(project_id: str = Body(..., embed=True), background_tasks: BackgroundTasks = BackgroundTasks()):
    job_id = str(uuid.uuid4())
    set_job(job_id, "pending", 0.0, "Queued vocal removal...")
    background_tasks.add_task(run_separation_task, job_id, project_id)
    return {"job_id": job_id}

# Mixing Async Job
def run_mixing_task(job_id: str, project_id: str):
    try:
        set_job(job_id, "running", 10.0, "Constructing dubbed voice timeline canvas...")
        proj = load_project_data(project_id)
        
        # 1. Find or extract total video duration
        video_path = proj["inputVideoPath"]
        base_name = os.path.splitext(os.path.basename(video_path))[0]
        audio_path = str(EXTRACTED_AUDIO_DIR / f"{base_name}_audio.wav")
        if not os.path.exists(audio_path):
            if not FFmpegService.extract_audio(video_path, audio_path):
                raise RuntimeError("FFmpeg failed to extract source audio.")
        total_duration = DurationChecker.get_audio_duration(audio_path)
        if total_duration <= 0:
            total_duration = DurationChecker.get_audio_duration(video_path)
        if total_duration <= 0:
            raise RuntimeError("Could not determine source media duration.")
        
        # 2. Build dubbed track canvas
        dub_canvas_wav = os.path.join(str(MIXES_DIR), f"{project_id}_dubbed_voices_canvas.wav")
        MixerService.assemble_dubbed_voice_canvas(proj["segments"], total_duration, dub_canvas_wav)
        
        set_job(job_id, "running", 50.0, "Applying ducking and loudness controls...")
        
        # Stems
        bg_wav = proj.get("mix", {}).get("backgroundPath") or os.path.join(str(SEPARATED_AUDIO_DIR), "background.wav")
        vocal_residual_wav = proj.get("mix", {}).get("vocalResidualPath") or os.path.join(str(SEPARATED_AUDIO_DIR), "vocals.wav")
        
        if not os.path.exists(bg_wav) or not os.path.exists(vocal_residual_wav):
            vocal_residual_wav, bg_wav, risk = AudioSeparator.separate(
                audio_path, project_id=project_id
            )
            proj["mix"]["backgroundDamageRisk"] = risk
            proj["mix"]["backgroundPath"] = bg_wav
            proj["mix"]["vocalResidualPath"] = vocal_residual_wav
            
        final_mix_wav = os.path.join(str(MIXES_DIR), f"{project_id}_final_mix.wav")
        success = MixerService.mix(bg_wav, vocal_residual_wav, dub_canvas_wav, final_mix_wav, proj["mix"])
        
        if success:
            proj["pipelineStage"] = "Export"
            proj["mix"]["dubbedVoiceCanvasPath"] = dub_canvas_wav
            proj["mix"]["finalMixPath"] = final_mix_wav
            save_project_data(project_id, proj)
            set_job(job_id, "completed", 100.0, "Mixing and mastering complete!", {"final_mix_path": final_mix_wav})
        else:
            raise RuntimeError("FFmpeg mixing command execution failed.")
            
    except Exception as e:
        log_event("errors.log", f"Mixing failed: {e}")
        set_job(job_id, "failed", 100.0, f"Mixing failed: {str(e)}")

@app.post("/audio/mix")
def start_mixing(project_id: str = Body(..., embed=True), background_tasks: BackgroundTasks = BackgroundTasks()):
    job_id = str(uuid.uuid4())
    set_job(job_id, "pending", 0.0, "Queued mixing operations...")
    background_tasks.add_task(run_mixing_task, job_id, project_id)
    return {"job_id": job_id}

# Video Export Async Job
def run_export_task(job_id: str, project_id: str):
    try:
        set_job(job_id, "running", 20.0, "Synthesizing master dubbed video...")
        proj = load_project_data(project_id)

        blocking_segments = [
            segment for segment in proj.get("segments", [])
            if not segment.get("generatedAudioPath")
            or not os.path.exists(segment.get("generatedAudioPath", ""))
            or segment.get("fitStatus") not in ("fits", "approved")
            or not segment.get("approved")
        ]
        if blocking_segments:
            ids = ", ".join(str(segment.get("id")) for segment in blocking_segments[:12])
            raise RuntimeError(
                f"Export blocked: segment(s) {ids} are missing, outside timing limits, or not approved."
            )

        quality_warnings = QualityChecker.check_project(proj)
        quality_errors = [item for item in quality_warnings if item.get("level") == "error"]
        if quality_errors:
            raise RuntimeError(f"Export blocked by quality control: {quality_errors[0]['message']}")
        
        mix_wav = proj.get("mix", {}).get("finalMixPath") or os.path.join(str(MIXES_DIR), f"{project_id}_final_mix.wav")
        if not os.path.exists(mix_wav):
            raise RuntimeError("Final mix is missing. Run Mixing before Export.")
        output_mp4 = os.path.join(str(EXPORTS_DIR), f"{proj['name']}_dubbed.mp4")
        
        success = FFmpegService.merge_video_audio(proj["inputVideoPath"], mix_wav, output_mp4)
        if success:
            set_job(job_id, "completed", 100.0, "Dubbed media exported successfully!", {"output_path": output_mp4})
            log_event("project.log", f"Exported project {project_id} successfully.")
        else:
            raise RuntimeError("FFmpeg merge process failed.")
    except Exception as e:
        log_event("errors.log", f"Export failed: {e}")
        set_job(job_id, "failed", 100.0, f"Export failed: {str(e)}")

@app.post("/export/video")
def start_export(project_id: str = Body(..., embed=True), background_tasks: BackgroundTasks = BackgroundTasks()):
    job_id = str(uuid.uuid4())
    set_job(job_id, "pending", 0.0, "Queued final video export...")
    background_tasks.add_task(run_export_task, job_id, project_id)
    return {"job_id": job_id}

# -------- Transcript / Speaker / Segment dedicated endpoints --------

@app.post("/transcript/parse-subtitle")
def parse_subtitle(project_id: str = Body(..., embed=True)):
    """Parses the project's subtitle file and saves segments."""
    proj = load_project_data(project_id)
    subtitle_path = proj.get("subtitlePath")
    if not subtitle_path or not os.path.exists(subtitle_path):
        raise HTTPException(status_code=400, detail="No subtitle file found for this project.")
    raw_segments = SubtitleParser.parse(subtitle_path)
    # Store parsed segments into project (without speaker assignment yet)
    proj["segments"] = [
        {
            "id": s["id"],
            "start": s["start"],
            "end": s["end"],
            "duration": s["duration"],
            "speakerId": "SPEAKER_01",
            "sourceText": s["source_text"],
            "dubText": "",
            "literalTranslation": "",
            "emotion": "neutral",
            "emotionIntensity": 50.0,
            "performanceInstruction": "",
            "qwenInstruction": "",
            "voiceProfileId": "qwen_voice_speaker_01",
            "generatedAudioPath": None,
            "generatedDuration": None,
            "retryCount": 0,
            "fitStatus": "pending",
            "approved": False,
            "locked": False,
            "warnings": []
        }
        for s in raw_segments
    ]
    save_project_data(project_id, proj)
    log_event("project.log", f"Parsed subtitle for project {project_id}: {len(raw_segments)} segments.")
    return {"segments": proj["segments"]}


def _run_whisper_task(job_id: str, project_id: str):
    try:
        set_job(job_id, "running", 10.0, "Extracting audio for Whisper...")
        proj = load_project_data(project_id)
        video_path = proj["inputVideoPath"]
        base_name = os.path.splitext(os.path.basename(video_path))[0]
        whisper_out = str(EXTRACTED_AUDIO_DIR / f"{base_name}_whisper.wav")
        if not FFmpegService.extract_whisper_audio(video_path, whisper_out):
            raise RuntimeError("FFmpeg failed to prepare Whisper audio.")

        set_job(job_id, "running", 40.0, "Running Whisper transcription...")
        raw_segments = WhisperService.transcribe(
            whisper_out,
            model_size=API_SETTINGS.get("whisperModel", "medium"),
            language=_language_hint(proj.get("sourceLanguage", "")),
        )
        if not raw_segments:
            raise RuntimeError("Transcription produced no segments.")

        proj["segments"] = [
            {
                "id": s["id"],
                "start": s["start"],
                "end": s["end"],
                "duration": s["duration"],
                "speakerId": "SPEAKER_01",
                "sourceText": s["source_text"],
                "dubText": "",
                "literalTranslation": "",
                "emotion": "neutral",
                "emotionIntensity": 50.0,
                "performanceInstruction": "",
                "qwenInstruction": "",
                "voiceProfileId": "qwen_voice_speaker_01",
                "generatedAudioPath": None,
                "generatedDuration": None,
                "retryCount": 0,
                "fitStatus": "pending",
                "approved": False,
                "locked": False,
                "warnings": []
            }
            for s in raw_segments
        ]
        save_project_data(project_id, proj)
        set_job(job_id, "completed", 100.0, "Whisper transcription complete!", {"segments": proj["segments"]})
    except Exception as e:
        log_event("errors.log", f"Whisper job {job_id} failed: {e}")
        set_job(job_id, "failed", 100.0, f"Whisper failed: {str(e)}")


@app.post("/transcript/run-whisper")
def run_whisper(project_id: str = Body(..., embed=True), background_tasks: BackgroundTasks = BackgroundTasks()):
    """Extracts audio and runs Whisper transcription as a background job."""
    job_id = str(uuid.uuid4())
    set_job(job_id, "pending", 0.0, "Queued Whisper transcription...")
    background_tasks.add_task(_run_whisper_task, job_id, project_id)
    return {"job_id": job_id}


def _run_diarization_task(job_id: str, project_id: str):
    try:
        set_job(job_id, "running", 10.0, "Running speaker diarization...")
        proj = load_project_data(project_id)
        video_path = proj["inputVideoPath"]
        base_name = os.path.splitext(os.path.basename(video_path))[0]
        audio_path = str(EXTRACTED_AUDIO_DIR / f"{base_name}_audio.wav")

        if not os.path.exists(audio_path):
            FFmpegService.extract_audio(video_path, audio_path)

        speaker_regions = DiarizationService.diarize(audio_path, project_id=project_id)
        proj["speakerRegions"] = speaker_regions
        save_project_data(project_id, proj)
        set_job(job_id, "completed", 100.0, "Diarization complete!", {"speaker_regions": speaker_regions})
    except Exception as e:
        log_event("errors.log", f"Diarization job {job_id} failed: {e}")
        set_job(job_id, "failed", 100.0, f"Diarization failed: {str(e)}")


@app.post("/speakers/diarize")
def run_diarization(project_id: str = Body(..., embed=True), background_tasks: BackgroundTasks = BackgroundTasks()):
    """Runs speaker diarization on extracted audio as a background job."""
    job_id = str(uuid.uuid4())
    set_job(job_id, "pending", 0.0, "Queued speaker diarization...")
    background_tasks.add_task(_run_diarization_task, job_id, project_id)
    return {"job_id": job_id}


@app.post("/segments/merge")
def merge_segments(project_id: str = Body(..., embed=True)):
    """Merges transcript segments with speaker regions and returns merged segments."""
    proj = load_project_data(project_id)
    raw_segments = proj.get("segments", [])
    speaker_regions = proj.get("speakerRegions", [])
    if not raw_segments:
        raise HTTPException(status_code=400, detail="No transcript segments found. Run transcription first.")
    if not speaker_regions:
        raise HTTPException(status_code=400, detail="No speaker regions found. Run diarization first.")

    # Convert stored segments to the format expected by merge_segments_with_speakers
    raw_for_merge = []
    for s in raw_segments:
        raw_for_merge.append({
            "id": s["id"],
            "start": s["start"],
            "end": s["end"],
            "duration": s["duration"],
            "source_text": s.get("sourceText", s.get("source_text", ""))
        })

    merged = DiarizationService.merge_segments_with_speakers(raw_for_merge, speaker_regions)

    # Build speakers registry
    speaker_ids = set(s["speakerId"] for s in merged)
    colors = ["#C0C1FF", "#FFB783", "#9BE7B1", "#FFB4AB", "#C7C4D7"]
    speakers = []
    for idx, sp_id in enumerate(sorted(speaker_ids)):
        speakers.append({
            "speakerId": sp_id,
            "displayName": f"Speaker {idx + 1}",
            "characterName": f"Character {idx + 1}",
            "genderStyle": "Original voice",
            "ageStyle": "Auto",
            "personalityStyle": "Neutral",
            "color": colors[idx % len(colors)],
            "voiceProfileId": f"qwen_voice_{sp_id.lower()}",
            "segmentCount": len([s for s in merged if s["speakerId"] == sp_id]),
            "totalSpeakingTime": round(sum(s["duration"] for s in merged if s["speakerId"] == sp_id), 2),
            "confidence": 0.90
        })

    base_name = os.path.splitext(os.path.basename(proj.get("inputVideoPath", "source")))[0]
    source_audio = str(EXTRACTED_AUDIO_DIR / f"{base_name}_audio.wav")
    if os.path.exists(source_audio):
        speakers, merged = SpeakerReferenceService.build_references(
            project_id,
            source_audio,
            speakers,
            merged,
        )

    proj["segments"] = merged
    proj["speakers"] = speakers
    proj["pipelineStage"] = "Transcript"
    save_project_data(project_id, proj)
    log_event("project.log", f"Merged segments for project {project_id}: {len(merged)} segments, {len(speakers)} speakers.")
    return {"segments": merged, "speakers": speakers}


# Job status poller endpoint
@app.get("/jobs/{job_id}/status", response_model=JobStatus)
def check_job_status(job_id: str):
    job = get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job ID not found")
    return job

@app.post("/jobs/{job_id}/cancel")
def cancel_job(job_id: str):
    with JOBS_LOCK:
        job = ACTIVE_JOBS.get(job_id)
        if not job:
            raise HTTPException(status_code=404, detail="Job ID not found")
        CANCELLED_JOBS.add(job_id)
        process = ACTIVE_PROCESSES.get(job_id)
    if process and process.poll() is None:
        process.terminate()
    set_job(job_id, "cancelled", 100.0, "Cancelled by user.")
    return {"status": "cancelled"}
