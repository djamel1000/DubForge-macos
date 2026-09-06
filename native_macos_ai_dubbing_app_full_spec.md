# Native macOS AI Dubbing App — Full Build Specification

## 0. Project Name

Working name: **DubForge macOS**

Build a native macOS app that creates dubbed videos using:

- **Whisper / subtitles** for transcription and timestamps.
- **Speaker diarization** to detect who speaks when.
- **Gemma/Gemini API** as the dubbing brain/director.
- **Qwen3-TTS** as the expressive TTS voice engine.
- **Audio source separation** to remove original voices while preserving background environment/music/effects.
- **FFmpeg** for extraction, alignment, mixing, and final video export.
- **Native macOS SwiftUI frontend** with a local Python processing backend.

The app is not a basic subtitle translator. It is a full AI dubbing studio.

---

## 1. Main Goal

The app must take a video and produce a dubbed version where:

1. The original voices are removed or reduced.
2. Background environment, music, and sound effects are preserved.
3. Each character/speaker gets a consistent dubbed voice.
4. The translated/adapted dialogue fits the original mouth movement period.
5. Gemma/Gemini adapts the dialogue to timing, meaning, and emotion.
6. Qwen3-TTS generates the final expressive dubbed speech.
7. The final audio is mixed naturally into the original video.

Core concept:

```text
Original video/audio/subtitles
    → transcript + timestamps
    → speaker detection
    → timing-aware translated script
    → consistent Qwen3 voices
    → remove original speech
    → preserve background
    → insert dubbed voices
    → export final dubbed video
```

---

## 2. Important Product Philosophy

The app must never simply do:

```text
Translate subtitle → Generate TTS → Replace audio
```

Instead, it must do:

```text
Understand scene timing → identify speakers → adapt dialogue → direct performance → generate expressive voices → align to mouth movement → mix with background
```

Gemma/Gemini acts like a **dubbing director**.

Qwen3-TTS acts like the **voice actor**.

The audio editor acts like the **sound engineer**.

---

## 3. Native macOS Requirement

This must be a **native macOS app**, not Electron.

Use:

```text
Swift
SwiftUI
AVFoundation
AppKit where needed
Combine / async-await
Local Python service for AI/audio processing
```

Recommended architecture:

```text
macOS SwiftUI App
    ↓
Local Processing Server / CLI Layer
    ↓
Python pipeline
    ↓
FFmpeg / Whisper / Diarization / Demucs / Gemini / Qwen3-TTS
```

The SwiftUI app should feel native:

- Drag and drop video/subtitle files.
- Native progress indicators.
- Sidebar project navigation.
- Inspector panels.
- Timeline table.
- Preview player.
- Export panel.
- Preferences window for API keys and model paths.

---

## 4. High-Level Features

### 4.1 Input

The app must support:

```text
Video:
- .mp4
- .mov
- .mkv
- .avi, optional

Audio:
- .wav
- .mp3
- .m4a
- .aac
- .flac

Subtitle/transcript:
- .srt
- .vtt
- .ass, optional
- .txt timestamped transcript
- .json project transcript
```

The user can choose:

```text
Option A: Use existing subtitles/transcript
Option B: Run Whisper transcription
Option C: Use subtitles for text but Whisper for better timing
```

---

## 5. Main User Workflow

### 5.1 Project Creation

User opens app and clicks:

```text
New Dubbing Project
```

Required fields:

```text
Project name
Source language
Target language
Input video/audio file
Optional subtitle/transcript file
```

Example:

```text
Project name: Lychee Episode 1 Dub
Source language: English
Target language: Arabic
Input: episode_1.mp4
Subtitle: english_transcript.txt
```

---

### 5.2 Analysis Stage

The app performs:

```text
1. Extract audio from video.
2. Load subtitle or run Whisper.
3. Normalize timestamps.
4. Detect speech regions.
5. Run speaker diarization.
6. Merge transcript with speaker timestamps.
7. Detect possible multi-speaker lines.
8. Create editable segment table.
```

---

### 5.3 Review Stage

The user must see a table:

```text
ID | Start | End | Duration | Speaker | Source Text | Target Text | Emotion | Voice | Fit Status
```

The user can edit:

```text
Speaker assignment
Speaker name
Source text
Target text
Emotion
Voice choice
Timing boundaries
```

This review step is required because automatic speaker detection can make mistakes.

---

### 5.4 Voice Assignment Stage

For each detected speaker:

```text
SPEAKER_01 → choose/create Qwen3 voice
SPEAKER_02 → choose/create Qwen3 voice
SPEAKER_03 → choose/create Qwen3 voice
```

The app must maintain a **Speaker Voice Registry** so the same speaker always uses the same voice.

---

### 5.5 Dubbing Stage

For every segment:

```text
1. Gemma/Gemini adapts the text to target language.
2. Gemma/Gemini produces performance instructions.
3. Qwen3-TTS generates speech.
4. App measures generated audio duration.
5. If too long, Gemma/Gemini rewrites shorter.
6. If too short, app may add silence or slightly slow down.
7. App places the final audio at exact timestamp.
```

---

### 5.6 Audio Editing Stage

The app must:

```text
1. Extract original audio.
2. Separate original voice from background.
3. Remove or reduce original voices.
4. Keep background/environment/music/effects.
5. Mix dubbed voices with background.
6. Duck background slightly during dubbed speech.
7. Normalize final loudness.
8. Merge final audio back with original video.
```

---

### 5.7 Export Stage

Export options:

```text
Video format:
- MP4 H.264
- MP4 H.265
- MOV

Audio:
- AAC
- WAV, optional

Extras:
- Export dubbed video
- Export dubbed audio only
- Export generated subtitles
- Export JSON project file
- Export per-speaker audio stems
```

---

## 6. Core Technical Modules

Create these modules.

```text
DubForge/
  macos_app/
    DubForgeApp.swift
    Views/
    ViewModels/
    Models/
    Services/
    Resources/

  processing/
    main.py
    api_server.py
    config.py
    requirements.txt

    services/
      ffmpeg_service.py
      subtitle_parser.py
      whisper_service.py
      diarization_service.py
      transcript_merger.py
      gemini_director.py
      qwen_tts_service.py
      duration_checker.py
      audio_separator.py
      voice_registry.py
      mixer_service.py
      export_service.py
      quality_checker.py

    schemas/
      project_schema.py
      segment_schema.py
      speaker_schema.py
      gemini_output_schema.py

    storage/
      projects/
      uploads/
      extracted_audio/
      transcripts/
      separated_audio/
      tts_segments/
      mixes/
      exports/
```

---

## 7. macOS App Architecture

### 7.1 SwiftUI Views

Create these views:

```text
ProjectListView
NewProjectView
ProjectDashboardView
MediaPreviewView
TranscriptTableView
SpeakerManagerView
VoiceManagerView
DubbingProgressView
AudioMixingView
ExportView
SettingsView
LogConsoleView
```

---

### 7.2 Main UI Layout

Use a three-column layout:

```text
Left sidebar:
- Projects
- Import
- Transcript
- Speakers
- Voices
- Dubbing
- Mixing
- Export
- Settings

Center:
- Video preview
- Timeline / table

Right inspector:
- Selected segment details
- Speaker info
- Voice settings
- Timing status
- Emotion/performance settings
```

---

### 7.3 Segment Table Columns

```text
ID
Start
End
Duration
Speaker ID
Speaker Name
Source Text
Dub Text
Emotion
Performance Instruction
Voice Profile
Generated Duration
Fit Status
Warnings
```

Fit statuses:

```text
pending
fits
too_long
too_short
needs_review
failed
approved
```

---

## 8. Processing API Between Swift and Python

The macOS app can talk to the Python pipeline through a local HTTP server:

```text
http://127.0.0.1:8765
```

Endpoints:

```text
POST /projects/create
POST /media/extract-audio
POST /transcript/parse-subtitle
POST /transcript/run-whisper
POST /speakers/diarize
POST /segments/merge
POST /gemini/adapt
POST /tts/generate-segment
POST /tts/generate-all
POST /audio/separate
POST /audio/mix
POST /export/video
GET  /projects/{id}
GET  /jobs/{id}/status
POST /jobs/{id}/cancel
```

Alternative: use Python CLI commands if local server is too much for version 1.

---

## 9. Project Data Model

Every project must save a `project.json`.

```json
{
  "project_id": "project_001",
  "project_name": "Episode Dub",
  "source_language": "en",
  "target_language": "ar",
  "input_video_path": "/path/input.mp4",
  "input_subtitle_path": "/path/subtitle.srt",
  "created_at": "2026-05-30T20:00:00+01:00",
  "status": "analysis_complete",
  "speakers": [],
  "segments": [],
  "audio_assets": {},
  "export_settings": {}
}
```

---

## 10. Speaker Schema

```json
{
  "speaker_id": "SPEAKER_01",
  "display_name": "Unknown Man 1",
  "character_name": "Li Shande",
  "gender_style": "male",
  "age_style": "middle-aged",
  "personality_style": "nervous, honest, educated",
  "voice_profile_id": "qwen_voice_speaker_01",
  "voice_type": "designed_voice",
  "reference_audio_path": null,
  "notes": ""
}
```

Voice type options:

```text
preset_voice
designed_voice
cloned_voice
imported_voice
```

Important:

- Do not force voice cloning in version 1.
- Manual voice assignment must be available.
- Voice cloning must require user confirmation and legal consent warning.
- Same speaker ID must always use same voice profile.

---

## 11. Segment Schema

```json
{
  "id": 1,
  "start": 97.0,
  "end": 103.0,
  "duration": 6.0,
  "speaker_id": "SPEAKER_01",
  "source_text": "Who built this canopy?",
  "literal_translation": "",
  "dub_text": "",
  "emotion": "concerned",
  "emotion_intensity": "medium",
  "performance_instruction": "",
  "qwen_instruction": "",
  "target_duration": 6.0,
  "generated_audio_path": "",
  "generated_duration": 0.0,
  "fit_status": "pending",
  "retry_count": 0,
  "warnings": []
}
```

---

## 12. Subtitle / Transcript Handling

The app must support subtitle parsing.

### 12.1 SRT Example

```text
1
00:00:01,000 --> 00:00:03,500
Hello everyone.
```

Parse into:

```json
{
  "start": 1.0,
  "end": 3.5,
  "text": "Hello everyone."
}
```

### 12.2 Timestamped TXT Example

Support this format:

```text
[00:01:37] Who built this canopy?
[00:01:43] The old peony's roots are weak.
```

If only start timestamps exist, infer end time from the next timestamp.

For the final line, infer end by:
- audio speech detection if available
- or default max duration
- or user manual edit

---

## 13. Whisper Transcription

Use Whisper or faster-whisper for:

```text
- transcription
- word timestamps if available
- segment timestamps
```

Recommended version 1:

```text
faster-whisper
model: medium or large-v3 if available
compute_type: int8 or float16 depending hardware
```

Because this is a macOS app, support Apple Silicon optimization where possible, but do not block MVP on perfect optimization.

Whisper output must be normalized into the same segment schema.

---

## 14. Speaker Diarization

Whisper does not reliably tell who is speaking.

Use a diarization module.

Options:

```text
pyannote.audio
NVIDIA NeMo diarization
SpeechBrain diarization
manual speaker correction
```

Version 1 must include manual correction because diarization may fail.

Output format:

```json
[
  {
    "start": 97.0,
    "end": 103.0,
    "speaker_id": "SPEAKER_01"
  }
]
```

Then merge this with transcript segments.

---

## 15. Transcript + Speaker Merge Logic

For each transcript segment:

```text
Find diarization speaker region with maximum overlap.
Assign segment.speaker_id = dominant speaker.
```

If two speakers overlap in one subtitle line:

```text
Flag segment as needs_review.
Ask Gemini/Gemini to split text if possible.
Allow user manual split.
```

Example:

```text
Original:
"Are you coming? No, I can't."

Possible split:
SPEAKER_01: "Are you coming?"
SPEAKER_02: "No, I can't."
```

Do not blindly split unless confidence is high.

---

## 16. Gemini/Gemma Role

Gemma/Gemini is the **director**.

It must handle:

```text
- translation
- adaptation
- shortening
- emotion detection
- performance instruction creation
- timing-aware rewriting
- line-by-line consistency
- speaker personality consistency
- strict JSON output
```

Use Gemini structured output / JSON schema mode where possible.

Do not ask Gemini to produce unstructured prose.

---

## 17. Gemini/Gemma Must Respect Timing

This is the most important feature.

For every line, provide Gemini/Gemma:

```text
source_text
source_language
target_language
speaker identity
speaker personality
scene context
start time
end time
duration
emotion
max duration
previous line
next line
```

Gemini/Gemma must output a dubbed version that fits the time box.

Priority order:

```text
1. Fit the original mouth movement period.
2. Preserve meaning.
3. Preserve emotion.
4. Sound natural in target language.
5. Match speaker personality.
6. Avoid literal translation if it is too long.
```

---

## 18. Timing-Aware Rewriting Examples

Example 1:

```text
Source:
Thank you so much.

Literal:
Thank you very much.

If too long:
Thanks a lot.

If still too long:
Thanks.
```

Example 2:

```text
Source:
I can't believe this is happening.

Long target version:
I really cannot believe that this is happening right now.

Short dubbed version:
I can't believe this.
```

Example 3:

```text
Source:
What are you talking about?

Short version:
What do you mean?
```

Gemini/Gemma must know that shorter natural phrases are preferred when timing is tight.

---

## 19. Gemini Output Schema

Gemini must return strict JSON:

```json
{
  "segment_id": 1,
  "speaker_id": "SPEAKER_01",
  "dub_text": "Thanks a lot.",
  "literal_translation": "Thank you very much.",
  "emotion": "grateful",
  "emotion_intensity": "medium",
  "performance_instruction": "Warm and grateful, quick delivery, no extra words.",
  "qwen_instruction": "Speak warmly and naturally, with a grateful tone. Keep it short and fit within 1.1 seconds. Do not speak the instruction text.",
  "estimated_spoken_duration": 1.1,
  "timing_strategy": "shortened_expression",
  "meaning_preserved": true,
  "needs_review": false
}
```

---

## 20. Gemini Prompt Template

Use this prompt in `gemini_director.py`.

```text
You are the dubbing director of a professional AI dubbing application.

You receive timestamped dialogue segments from a video. Your job is to adapt each line into the target language for dubbing.

You are not a normal translator.

You must:
- Preserve meaning.
- Preserve emotion.
- Preserve speaker personality.
- Produce natural spoken dialogue.
- Fit the original mouth movement duration.
- Prefer shorter equivalent expressions when needed.
- Avoid literal translation if it becomes too long.
- Create performance instructions for Qwen3-TTS.
- Keep spoken text separate from performance instructions.
- Never put fake tags like [sigh], [laugh], [cry] inside the spoken text unless explicitly supported by the TTS API.
- Do not include stage directions in the spoken text.
- Return only valid JSON matching the schema.

Priority:
1. Fit the original speech duration.
2. Keep meaning.
3. Keep emotion.
4. Sound natural.
5. Match character voice.

Input segment:
{segment_json}

Context:
Previous segment:
{previous_segment}

Next segment:
{next_segment}

Speaker profile:
{speaker_json}

Return JSON only.
```

---

## 21. Qwen3-TTS Control

Important rule:

```text
Do not put fake tags inside the spoken text.
```

Bad:

```text
[sigh] I can't believe it...
```

This may be spoken literally.

Good:

```json
{
  "text": "I can't believe it.",
  "instruction": "Speak in a tired, disappointed voice with a soft sighing tone before the sentence. Do not pronounce stage directions."
}
```

Qwen3-TTS should receive:

```json
{
  "text": "I can't believe it.",
  "voice_profile_id": "qwen_voice_speaker_01",
  "instruction": "Speak in a tired, disappointed voice. Keep it under 2.4 seconds. Do not speak the instruction text.",
  "speed": 0.96,
  "target_duration": 2.4,
  "language": "en"
}
```

---

## 22. Qwen3 Emotion / Performance Categories

Support these performance controls:

```text
neutral
happy
sad
angry
afraid
surprised
disappointed
tired
warm
serious
formal
whispered
excited
calm
crying tone
laughing tone
sighing tone
hesitant
confused
sarcastic
urgent
```

Nonverbal performance should be requested only through the instruction field:

```text
Use a short laughing tone before the sentence.
Use a tired sighing tone.
Speak as if holding back tears.
Speak with nervous hesitation.
```

Never insert unsupported tags into the actual spoken text.

---

## 23. Qwen3 Voice Registry

Create `voice_registry.json`.

```json
{
  "voices": [
    {
      "voice_profile_id": "qwen_voice_speaker_01",
      "speaker_id": "SPEAKER_01",
      "voice_type": "designed_voice",
      "description": "Middle-aged male, nervous but kind, soft official tone",
      "qwen_voice_reference": "local_or_api_voice_id",
      "created_at": "2026-05-30T20:00:00+01:00"
    }
  ]
}
```

Every TTS call must use the voice profile connected to the speaker.

---

## 24. TTS Generation Loop

For each segment:

```python
MAX_RETRIES = 3

for segment in segments:
    gemini_output = adapt_line_with_gemini(segment)
    segment.dub_text = gemini_output["dub_text"]
    segment.qwen_instruction = gemini_output["qwen_instruction"]

    audio = qwen_generate(segment.dub_text, segment.qwen_instruction, segment.voice_profile)

    generated_duration = measure_audio_duration(audio)

    if generated_duration <= segment.duration * 1.05:
        accept_segment(audio)
    else:
        ask_gemini_to_shorten(segment, generated_duration)
        retry
```

Allowed timing tolerance:

```text
Perfect: generated_duration <= original_duration
Acceptable: generated_duration <= original_duration * 1.05
Needs fix: generated_duration > original_duration * 1.05
Bad: generated_duration > original_duration * 1.15
```

---

## 25. Duration Fix Strategy

If generated audio is too long:

```text
1. Ask Gemini to shorten the expression.
2. Regenerate TTS.
3. Slightly increase TTS speed, max 1.12x.
4. If still too long, mark needs_review.
```

If generated audio is too short:

```text
1. Add silence after the line.
2. Slightly slow TTS, max 0.92x.
3. Keep inside the original speech window.
```

Do not stretch heavily because it sounds unnatural.

---

## 26. Audio Source Separation

Goal:

```text
Remove original voices while preserving background environment, music, sound effects.
```

Use a source separation model.

Recommended first option:

```text
Demucs / HT-Demucs
```

Demucs can separate stems such as:

```text
vocals
drums
bass
other
```

For dubbing:

```text
background = drums + bass + other
original_voice = vocals
```

But for normal movie dialogue, vocals stem may include speech and some environmental sounds. Therefore, create a removal strength slider.

---

## 27. Voice Removal Modes

The app must support:

```text
Light removal:
- Keep some original voice ambience
- Less damage to background

Medium removal:
- Balanced default

Strong removal:
- Remove as much original voice as possible
- May damage background

Manual:
- User controls vocal stem volume
```

Settings:

```json
{
  "voice_removal_strength": "medium",
  "vocal_stem_gain_db": -24,
  "background_gain_db": 0,
  "ducking_enabled": true
}
```

---

## 28. Background Preservation

After separation:

```text
background_track = drums + bass + other
```

If only two-stem separation is available:

```text
background_track = no_vocals.wav
```

The background track must remain aligned with original video from time 0.

Do not cut or shift the background.

---

## 29. Dubbed Voice Placement

Create a silent audio canvas equal to original video duration.

For each generated TTS segment:

```text
Place generated_audio at segment.start
Apply short fade in/out
Normalize segment volume
```

Fade settings:

```text
fade_in: 10-30 ms
fade_out: 20-50 ms
```

Do not create clicks or hard cuts.

---

## 30. Audio Mixing

Final audio:

```text
final_audio = preserved_background + dubbed_voice_track
```

Apply:

```text
- loudness normalization
- limiter
- voice volume matching
- optional room reverb
- background ducking during speech
```

Default mix:

```text
dubbed_voice_gain_db: 0
background_gain_db: -1
ducking_amount_db: -4
limiter_ceiling_db: -1
target_loudness_lufs: -16 for web/video
```

---

## 31. Ducking Logic

When dubbed voice is active:

```text
lower background volume by 3-6 dB
```

Use smooth attack/release:

```text
attack: 80 ms
release: 250 ms
```

Do not make the background pump aggressively.

---

## 32. Loudness Normalization

Normalize final audio to:

```text
-16 LUFS for general online video
-14 LUFS optional
-23 LUFS broadcast optional
```

Use FFmpeg loudnorm filter or pyloudnorm.

---

## 33. FFmpeg Commands

### 33.1 Extract Audio

```bash
ffmpeg -y -i input.mp4 -vn -ac 2 -ar 48000 extracted_audio.wav
```

### 33.2 Extract Audio for Whisper

```bash
ffmpeg -y -i input.mp4 -vn -ac 1 -ar 16000 whisper_audio.wav
```

### 33.3 Merge Final Audio With Original Video

```bash
ffmpeg -y -i input.mp4 -i final_mix.wav -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -shortest output_dubbed.mp4
```

### 33.4 Loudness Normalize

```bash
ffmpeg -y -i mixed.wav -af loudnorm=I=-16:TP=-1.5:LRA=11 normalized.wav
```

---

## 34. Quality Control

The app must show warnings:

```text
Segment too long
Segment too short
Speaker changed unexpectedly
No voice assigned
Gemini output invalid
TTS failed
Audio separation failed
Background damaged
Overlapping generated voices
Dubbed voice too loud
Dubbed voice too quiet
```

---

## 35. Segment Quality Score

For each segment calculate:

```json
{
  "duration_fit_score": 0.95,
  "translation_confidence": 0.9,
  "speaker_confidence": 0.8,
  "emotion_confidence": 0.85,
  "needs_human_review": false
}
```

---

## 36. Timeline Editing

User must be able to:

```text
Split segment
Merge segments
Change start/end time
Assign speaker
Change voice
Regenerate line
Regenerate only TTS
Regenerate only Gemini adaptation
Lock approved segment
Preview selected segment
Preview with background
```

---

## 37. Preview System

The app must support:

```text
Preview original video
Preview background-only audio
Preview dubbed voice only
Preview final mixed audio
Preview selected segment
Preview selected speaker voice
```

---

## 38. Preferences / Settings

Settings screen must include:

```text
Gemini API key
Gemini model name
Qwen3-TTS endpoint or local path
Whisper model path
Diarization model settings
Demucs path
FFmpeg path
Default target language
Default output folder
Hardware acceleration options
Privacy settings
```

---

## 39. Local/Cloud Model Strategy

Recommended:

```text
Gemini/Gemma:
- via Gemini API

Whisper:
- local faster-whisper

Qwen3-TTS:
- local if possible
- or local server endpoint
- or remote API wrapper if available

Demucs:
- local Python model
```

The app must abstract each service behind an interface so the implementation can change later.

Example:

```python
class TTSService:
    def generate(self, text, instruction, voice_profile, target_duration):
        pass
```

---

## 40. Error Handling

The app must never crash on pipeline failure.

If a stage fails:

```text
Show clear error
Keep project state
Allow retry
Allow skipping segment
Allow manual import of generated audio
Save logs
```

---

## 41. Logging

Create logs:

```text
project.log
gemini_requests.log
tts_generation.log
audio_processing.log
errors.log
```

Do not log API keys.

Do not log private voice samples unless user enables debug.

---

## 42. Privacy and Legal Rules

The app must include a notice:

```text
Only dub content you own, have permission to modify, or are legally allowed to use.
Only clone or imitate voices when you have permission from the voice owner.
```

Voice cloning must be optional.

Do not enable hidden impersonation features.

---

## 43. MVP Scope

Version 1 must include:

```text
Native macOS SwiftUI app
Project creation
Video import
Public video-link import through yt-dlp with metadata inspection, progress, cancellation, and local MP4 normalization
Subtitle import
Whisper transcription
Basic speaker diarization or manual speaker assignment
Speaker voice registry
Gemini timing-aware adaptation
Qwen3-TTS generation
Duration checking and retry loop
Original voice removal using Demucs
Background preservation
Audio mixing
Video export
Review/edit table
Settings screen
Logs
```

Do not include in MVP:

```text
Perfect lip-sync face modification
Real-time dubbing
Automatic character name recognition
Cloud project sync
Team collaboration
Advanced voice cloning
Full subtitle styling
```

---

## 44. Version 2 Features

Add later:

```text
Better speaker diarization
Automatic character naming
Multi-language batch dubbing
Scene-level emotion memory
Lip-sync correction model
Voice cloning consent workflow
Subtitle burn-in
Batch episode processing
Background damage repair
Manual waveform editor
```

---

## 45. Minimum Acceptance Tests

The AI coding agent must verify:

```text
1. App imports MP4 successfully.
2. App extracts audio.
3. App parses SRT and timestamped TXT.
4. App runs Whisper when no subtitle exists.
5. App creates segments with start/end/duration.
6. App assigns speakers.
7. User can edit speaker manually.
8. Gemini returns valid JSON.
9. Gemini shortens long lines when timing is tight.
10. Qwen3-TTS receives text and instruction separately.
11. Unsupported tags are not inserted into spoken text.
12. Generated audio duration is measured.
13. Too-long TTS is regenerated shorter.
14. Speaker voice stays consistent.
15. Demucs separates vocals/background.
16. App keeps background track aligned.
17. App places dubbed voice at correct timestamp.
18. App mixes background + dubbed voices.
19. App exports MP4 with original video and dubbed audio.
20. Project can be saved and reopened.
```

---

## 46. Important Implementation Notes for AI Agent

When building this app:

1. Do not hard-code fake Qwen tags.
2. Keep spoken text and TTS instruction separate.
3. Use structured JSON from Gemini.
4. Save every intermediate file.
5. Make every pipeline stage retryable.
6. Keep a project JSON as source of truth.
7. Never destroy original media.
8. Manual correction is required for speakers and timing.
9. Timing fit is more important than literal translation.
10. Background preservation is required, not optional.
11. The app must be native macOS SwiftUI.
12. Python processing should be modular and callable from the Swift app.
13. Use FFmpeg for media operations.
14. Use a clear logs folder.
15. Make the first version reliable before adding perfect lip-sync.

---

## 47. Example End-to-End Flow

```text
User imports episode.mp4 and english_transcript.txt.

App extracts audio:
episode_audio.wav

App parses transcript:
segments_raw.json

App runs diarization:
speaker_timeline.json

App merges transcript + speakers:
segments_speaker_aware.json

User reviews speakers:
SPEAKER_01 = Li Shande
SPEAKER_02 = Official
SPEAKER_03 = Woman

User assigns voices:
Li Shande → nervous middle-aged male voice
Official → serious older male voice
Woman → calm female voice

Gemini adapts each line:
source: "Thank you so much."
duration: 1.1 sec
output: "Thanks a lot."
instruction: "Warm grateful tone, quick natural delivery."

Qwen3-TTS generates:
segment_001.wav

App checks:
original duration: 1.1 sec
generated duration: 1.0 sec
status: fits

App separates original audio:
background.wav
vocals.wav

App builds dubbed voice track:
dubbed_voices.wav

App mixes:
background.wav + dubbed_voices.wav = final_mix.wav

App exports:
episode_dubbed.mp4
```

---

## 48. Final Definition

Build a native macOS AI dubbing app where:

```text
Gemma/Gemini controls:
- meaning
- timing
- sentence shortening
- emotion
- performance direction
- structured dubbing script

Qwen3-TTS controls:
- final speech generation
- consistent speaker voices
- expressive delivery from natural-language instructions

Audio pipeline controls:
- original voice removal
- background preservation
- dubbed voice placement
- final mix and export
```

The final result must be a dubbed video that keeps the original visual timing and environmental sound while replacing the original dialogue with natural, expressive, speaker-consistent dubbed voices.
