# DubForge Native macOS UI-DSL v1.0

## App

```yaml
app:
  name: DubForge
  platform: macOS
  framework: SwiftUI
  style: native-pro-dark
  purpose: AI dubbing studio with speaker-aware, timing-aware, emotion-aware dubbing
  core_principle: >
    The app is not a subtitle translator. It is a dubbing studio where Gemma/Gemini
    acts as the dubbing director, Qwen3-TTS acts as the voice actor, and the audio
    editor removes original speech while preserving background environment.

theme:
  mode: dark
  accent: soft-indigo
  background: "#13131B"
  surface_lowest: "#0D0D15"
  surface_low: "#1B1B23"
  surface: "#1F1F27"
  surface_high: "#292932"
  surface_highest: "#34343D"
  text_primary: "#E4E1ED"
  text_secondary: "#C7C4D7"
  outline: "#464554"
  primary: "#C0C1FF"
  primary_strong: "#8083FF"
  warning: "#FFB783"
  error: "#FFB4AB"
  success: "#9BE7B1"
  fonts:
    ui: Inter
    mono: JetBrains Mono
  density:
    compact_controls: true
    toolbar_height: 48
    sidebar_width: 260
    inspector_width: 340
    status_bar_height: 32
    table_row_height: 32
```

---

## Global Layout

```yaml
layout:
  type: three-pane-pro-app
  top_toolbar: true
  left_sidebar: true
  center_workspace: true
  right_inspector: true
  bottom_status_bar: true

top_toolbar:
  left:
    - AppTitle: DubForge
    - PipelineMiniStepper:
        steps:
          - Import
          - Analyze
          - Transcript
          - Speakers
          - Voices
          - AI Director
          - Dubbing
          - Mixing
          - Export
        current_binding: project.pipelineStage
  center:
    - TransportControls:
        buttons:
          - play
          - pause
          - stop
          - loop_selected_segment
    - PreviewModeSegmentedControl:
        options:
          - Original
          - Background Only
          - Dubbed Voice Only
          - Final Mix
        selected_binding: preview.mode
  right:
    - HealthBadge:
        binding: system.health
    - JobStatusBadge:
        binding: activeJob.status
    - PrimaryButton:
        title: Export
        icon: ios_share
        action: openExport

left_sidebar:
  project_header:
    icon: movie
    title_binding: project.name
    subtitle_binding: project.targetLanguage + " Dub Session"
  items:
    - Import
    - Analysis
    - Transcript
    - Speakers
    - Voices
    - AI Director
    - Dubbing
    - Mixing
    - Export
    - Settings

bottom_status_bar:
  left:
    - CurrentTask: activeJob.currentStep
    - ProgressBar: activeJob.progress
  center:
    - SelectedSegmentSummary: "Segment {id} • {speaker} • {fitStatus}"
  right:
    - Logs
    - Tasks
    - Health
    - SystemReadyLabel
```

---

## Screen: Import

```yaml
screen:
  id: import
  title: Import Project
  layout: centered-dropzone-with-options

components:
  - DropZone:
      id: media_dropzone
      title: Drop video or audio here
      subtitle: MP4, MOV, MKV, WAV, MP3, M4A
      accepted_types: [.mp4, .mov, .mkv, .wav, .mp3, .m4a]
      action: importMedia

  - OptionalDropZone:
      id: subtitle_dropzone
      title: Optional subtitle or transcript
      subtitle: SRT, VTT, ASS, timestamped TXT, JSON
      accepted_types: [.srt, .vtt, .ass, .txt, .json]
      action: importSubtitle

  - FormSection:
      title: Language
      fields:
        - LanguagePicker:
            label: Source language
            binding: project.sourceLanguage
        - LanguagePicker:
            label: Target language
            binding: project.targetLanguage

  - FormSection:
      title: Transcription Strategy
      fields:
        - RadioGroup:
            binding: project.transcriptionMode
            options:
              - subtitle_only: Use subtitle/transcript timing
              - whisper_only: Run Whisper
              - subtitle_text_whisper_timing: Use subtitle text + Whisper timing verification

  - PrimaryButton:
      title: Start Analysis
      icon: auto_awesome
      action: startAnalysis
```

---

## Screen: Analysis

```yaml
screen:
  id: analysis
  title: Analysis Pipeline
  layout: pipeline-dashboard

components:
  - PipelineCards:
      cards:
        - Extract Audio:
            status: analysis.extractAudio.status
            progress: analysis.extractAudio.progress
        - Parse Transcript:
            status: analysis.parseTranscript.status
            progress: analysis.parseTranscript.progress
        - Whisper Timing:
            status: analysis.whisper.status
            progress: analysis.whisper.progress
        - Speaker Diarization:
            status: analysis.diarization.status
            progress: analysis.diarization.progress
        - Merge Segments:
            status: analysis.mergeSegments.status
            progress: analysis.mergeSegments.progress

  - WarningsPanel:
      title: Analysis Warnings
      binding: analysis.warnings

  - PrimaryButton:
      title: Open Transcript Review
      action: navigate.transcript
      enabled_when: analysis.readyForReview == true
```

---

## Screen: Transcript Review

```yaml
screen:
  id: transcript
  title: Transcript Review
  layout: video-table-inspector

center_top:
  VideoPreview:
    height_percent: 40
    overlays:
      - SubtitleOverlay:
          binding: selectedSegment.dubText
      - MouthWindowOverlay:
          start: selectedSegment.start
          end: selectedSegment.end
      - FitWarningOverlay:
          visible_when: selectedSegment.fitStatus in [too_long, needs_review, failed]

center_middle:
  TimelineScrubber:
    tracks:
      - Original Speech Windows: segments.originalSpeechWindows
      - Dubbed Audio Clips: segments.generatedAudioClips
      - Playhead: preview.playhead

center_bottom:
  SegmentDataGrid:
    title: Transcript Segments
    filters:
      - All
      - Needs Review
      - Too Long
      - Missing Voice
      - Errors
    search_placeholder: Search source or dubbed text...
    columns:
      - id: id
        title: ID
        width: 48
        font: mono
      - id: start
        title: Start
        width: 90
        font: mono
      - id: end
        title: End
        width: 90
        font: mono
      - id: original_duration
        title: Orig Dur
        width: 72
        font: mono
      - id: generated_duration
        title: Gen Dur
        width: 72
        font: mono
      - id: speaker
        title: Speaker
        width: 140
        badge_color_binding: speaker.color
      - id: voice
        title: Voice
        width: 110
      - id: emotion
        title: Emotion
        width: 100
      - id: source_text
        title: Source Text
        width: flex
      - id: dub_text
        title: Dub Text
        width: flex
      - id: retry_count
        title: Retry
        width: 54
        align: center
      - id: fit_status
        title: Fit
        width: 90
        align: center
        badge_map:
          fits: success
          pending: neutral
          too_long: error
          too_short: warning
          needs_review: warning
          failed: error
    row_actions:
      - preview_segment
      - split_segment
      - merge_next
      - lock_segment
```

---

## Right Inspector: Segment Inspector

```yaml
inspector:
  id: segment_inspector
  title: Segment Inspector
  binding: selectedSegment

sections:
  - Timing Fit:
      component: TimingFitPanel
      fields:
        - Start:
            type: timecode
            binding: selectedSegment.start
        - End:
            type: timecode
            binding: selectedSegment.end
        - Original Duration:
            type: readonly
            binding: selectedSegment.duration
        - Generated Duration:
            type: readonly
            binding: selectedSegment.generatedDuration
        - Over/Under:
            type: readonlyBadge
            binding: selectedSegment.durationDelta
      visual:
        component: DurationComparisonBar
        source_duration: selectedSegment.duration
        generated_duration: selectedSegment.generatedDuration

  - Speaker and Voice:
      fields:
        - Speaker:
            type: speakerPicker
            binding: selectedSegment.speakerId
        - Voice Profile:
            type: voicePicker
            binding: selectedSegment.voiceProfileId
        - Emotion:
            type: emotionPicker
            binding: selectedSegment.emotion
        - Emotion Intensity:
            type: slider
            min: 0
            max: 100
            binding: selectedSegment.emotionIntensity

  - Text:
      fields:
        - Source Text:
            type: readonlyTextArea
            binding: selectedSegment.sourceText
        - Dubbed Text:
            type: editableTextArea
            binding: selectedSegment.dubText
        - Performance Instruction:
            type: editableTextArea
            binding: selectedSegment.performanceInstruction
            note: This is sent to Qwen3-TTS as instruction, not spoken text.

  - AI Rewrite Suggestions:
      component: SuggestionChips
      binding: selectedSegment.rewriteSuggestions
      actions:
        - applySuggestion
        - previewSuggestion

  - Actions:
      buttons:
        - title: Shorten with Gemma
          icon: compress
          action: director.shortenSelected
          style: secondary
        - title: Regenerate TTS
          icon: sync
          action: tts.regenerateSelected
          style: primary
        - title: Approve Segment
          icon: check
          action: segment.approve
          style: success
```

---

## Screen: Speaker Registry

```yaml
screen:
  id: speakers
  title: Speaker Registry
  layout: grid-inspector

toolbar:
  - SearchField:
      placeholder: Search speakers...
  - Button:
      title: Auto Detect Speakers
      icon: auto_awesome
      action: diarization.run
  - Button:
      title: Add Speaker
      icon: add
      action: speaker.add

grid:
  component: SpeakerCardGrid
  columns: adaptive
  card_fields:
    - speaker.displayName
    - speaker.characterName
    - speaker.segmentCount
    - speaker.totalSpeakingTime
    - speaker.assignedVoice
    - speaker.confidence
  card_actions:
    - previewSpeakerLines
    - renameSpeaker
    - mergeWithAnotherSpeaker
    - assignVoice

inspector:
  title: Speaker Details
  sections:
    - Identity:
        fields:
          - Display Name: selectedSpeaker.displayName
          - Character Name: selectedSpeaker.characterName
          - Gender Style: selectedSpeaker.genderStyle
          - Age Style: selectedSpeaker.ageStyle
          - Personality Notes: selectedSpeaker.personalityStyle
    - Statistics:
        fields:
          - Segments: selectedSpeaker.segmentCount
          - Total Speech Time: selectedSpeaker.totalSpeakingTime
          - Diarization Confidence: selectedSpeaker.confidence
    - Danger Zone:
        buttons:
          - Merge Speaker
          - Delete Speaker
```

---

## Screen: Voice Registry

```yaml
screen:
  id: voices
  title: Voice Registry
  layout: voice-library
  description: Assign one stable Qwen3-TTS voice profile to each speaker.

toolbar:
  - Button:
      title: Create Designed Voice
      icon: record_voice_over
      action: voice.createDesigned
  - Button:
      title: Import Voice
      icon: upload
      action: voice.import
  - Button:
      title: Clone Voice
      icon: person_record
      action: voice.clone
      requires_consent: true

consent_banner:
  visible_when: voice.cloneModeAvailable == true
  severity: warning
  text: Only clone or imitate voices when you have permission from the voice owner.

components:
  - VoiceAssignmentMatrix:
      columns:
        - Speaker
        - Character
        - Voice Profile
        - Voice Type
        - Preview
        - Consistency Status

  - VoiceProfileInspector:
      sections:
        - Voice Description:
            fields:
              - Qwen Voice Design Prompt:
                  type: textArea
                  binding: selectedVoice.description
                  placeholder: Middle-aged male, nervous but kind, soft official tone...
              - Voice Type:
                  type: select
                  options: [preset_voice, designed_voice, cloned_voice, imported_voice]
              - Generate Voice Preview:
                  type: button
                  action: voice.preview
        - Consistency:
            fields:
              - Used By: selectedVoice.assignedSpeaker
              - Generated Segments: selectedVoice.generatedSegmentCount
```

---

## Screen: AI Director

```yaml
screen:
  id: director
  title: AI Director
  layout: director-console
  purpose: Gemma/Gemini controls timing-aware adaptation, emotion, and Qwen instructions.

components:
  - DirectorStatusCards:
      cards:
        - Gemma/Gemini Model: settings.geminiModel
        - JSON Schema Mode: director.structuredOutputEnabled
        - Timing Priority: Highest
        - Pending Lines: director.pendingCount

  - DirectorPromptPanel:
      editable: true
      sections:
        - Core Rules: director.coreRules
        - Timing Rewrite Examples: director.examples

  - BatchAdaptationControls:
      buttons:
        - Adapt Selected: director.adaptSelected
        - Adapt All Pending: director.adaptAllPending
        - Shorten Too-Long Lines: director.shortenTooLong
        - Recheck JSON: director.validateAll

  - DirectorOutputTable:
      columns:
        - Segment ID
        - Dub Text
        - Emotion
        - Qwen Instruction
        - Timing Strategy
        - Needs Review
```

---

## Screen: TTS Generation

```yaml
screen:
  id: dubbing
  title: TTS Generation
  layout: generation-dashboard

components:
  - GenerationQueue:
      columns:
        - Segment
        - Speaker
        - Voice
        - Text
        - Target Duration
        - Generated Duration
        - Retry Count
        - Status

  - QwenStatusPanel:
      fields:
        - Qwen3-TTS Endpoint: settings.qwenEndpoint
        - Current Voice: tts.currentVoice
        - Current Instruction: tts.currentInstruction
        - Do Not Speak Instructions: true

  - GenerationControls:
      buttons:
        - Generate Selected: tts.generateSelected
        - Generate All Pending: tts.generateAll
        - Regenerate Failed: tts.regenerateFailed
        - Stop Queue: tts.stopQueue

  - AudioPreviewPanel:
      modes:
        - Generated segment only
        - With background
        - Final mix preview
```

---

## Screen: Mixing and Background Preservation

```yaml
screen:
  id: mixing
  title: Mixing and Background Preservation
  layout: tracks-plus-inspector

components:
  - SourceSeparationPanel:
      title: Original Voice Removal
      fields:
        - Removal Strength:
            type: segmentedControl
            binding: mix.voiceRemovalStrength
            options: [Light, Medium, Strong, Manual]
        - Original Vocal Stem Gain:
            type: slider
            min: -60
            max: 0
            unit: dB
            binding: mix.vocalStemGainDb
        - Background Damage Risk:
            type: readonlyBadge
            binding: mix.backgroundDamageRisk
        - Run Separation:
            type: button
            icon: auto_awesome
            action: audio.separate

  - MixerTracks:
      tracks:
        - id: background
          title: Preserved Background
          icon: waves
          color: secondary
          gain_binding: mix.backgroundGainDb
          waveform_binding: audio.backgroundWaveform
          mute_binding: mix.backgroundMuted
          solo_binding: mix.backgroundSolo
        - id: original_vocals
          title: Original Voice Residual
          icon: hearing
          color: warning
          gain_binding: mix.originalVocalResidualGainDb
          waveform_binding: audio.vocalsWaveform
          mute_binding: mix.originalVocalsMuted
          solo_binding: mix.originalVocalsSolo
        - id: dubbed_voices
          title: Dubbed Voices
          icon: mic
          color: primary
          gain_binding: mix.dubbedVoiceGainDb
          waveform_binding: audio.dubbedVoicesWaveform
          mute_binding: mix.dubbedVoicesMuted
          solo_binding: mix.dubbedVoicesSolo
        - id: final_mix
          title: Final Mix
          icon: graphic_eq
          color: success
          gain_binding: mix.masterGainDb
          waveform_binding: audio.finalMixWaveform

  - DuckingPanel:
      title: Background Ducking
      fields:
        - Enable Ducking:
            type: toggle
            binding: mix.duckingEnabled
        - Ducking Amount:
            type: slider
            min: 0
            max: 12
            unit: dB
            binding: mix.duckingAmountDb
        - Attack:
            type: slider
            min: 10
            max: 300
            unit: ms
            binding: mix.duckingAttackMs
        - Release:
            type: slider
            min: 50
            max: 800
            unit: ms
            binding: mix.duckingReleaseMs

  - LoudnessPanel:
      title: Loudness and Mastering
      fields:
        - Target Loudness:
            type: select
            binding: mix.targetLoudness
            options:
              - -16 LUFS Web Video
              - -14 LUFS Loud Online
              - -23 LUFS Broadcast
        - Limiter:
            type: toggle
            binding: mix.limiterEnabled
        - Peak:
            type: readonly
            binding: mix.truePeak
        - Integrated LUFS:
            type: readonly
            binding: mix.integratedLufs
```

---

## Screen: Export

```yaml
screen:
  id: export
  title: Export
  layout: export-summary-inspector

components:
  - ProjectSummaryCard:
      fields:
        - project.name
        - project.duration
        - project.targetLanguage
        - segments.approvedCount
        - segments.warningCount
        - mix.integratedLufs

  - ExportSettings:
      fields:
        - Video Format:
            type: radioGroup
            binding: export.videoFormat
            options:
              - MP4 H.264
              - MP4 H.265
              - MOV ProRes 422
        - Audio Format:
            type: select
            binding: export.audioFormat
            options:
              - AAC 320 kbps
              - WAV 24-bit 48kHz
              - FLAC
        - Export project JSON:
            type: checkbox
            binding: export.includeProjectJson
        - Export stems:
            type: checkbox
            binding: export.includeStems
        - Export subtitles:
            type: checkbox
            binding: export.includeSubtitles
        - Burn-in subtitles:
            type: checkbox
            binding: export.burnInSubtitles

  - PreflightChecklist:
      checks:
        - No missing voices: preflight.noMissingVoices
        - No failed TTS segments: preflight.noFailedSegments
        - Timing fit acceptable: preflight.timingAcceptable
        - Final mix generated: preflight.mixReady

  - PrimaryButton:
      title: Export Dubbed Video
      icon: download
      action: export.start
      enabled_when: preflight.exportAllowed == true
```

---

## Screen: Settings

```yaml
screen:
  id: settings
  title: Settings
  layout: settings-form

sections:
  - Gemma / Gemini API:
      fields:
        - Gemini API Key:
            type: secureText
            binding: settings.geminiApiKey
        - Model Name:
            type: text
            binding: settings.geminiModel
        - Use Structured JSON Output:
            type: toggle
            binding: settings.geminiStructuredOutput

  - Qwen3-TTS:
      fields:
        - Qwen3-TTS Endpoint:
            type: text
            binding: settings.qwenEndpoint
        - Local Qwen Model Path:
            type: folderPicker
            binding: settings.qwenLocalPath
        - Keep text and instruction separate:
            type: toggle
            binding: settings.qwenSeparateInstruction
            locked: true

  - Whisper:
      fields:
        - Whisper Model:
            type: select
            binding: settings.whisperModel
            options: [small, medium, large-v3]
        - Compute Type:
            type: select
            binding: settings.whisperComputeType
            options: [int8, float16, float32]

  - Audio Separation:
      fields:
        - Demucs Path:
            type: folderPicker
            binding: settings.demucsPath
        - Separation Model:
            type: select
            binding: settings.separationModel
            options: [htdemucs, htdemucs_ft, two_stem_vocals]

  - FFmpeg:
      fields:
        - FFmpeg Binary:
            type: filePicker
            binding: settings.ffmpegPath
        - Test FFmpeg:
            type: button
            action: settings.testFFmpeg
```

---

## Data Models

```yaml
Project:
  projectId: String
  name: String
  sourceLanguage: String
  targetLanguage: String
  inputVideoPath: String
  subtitlePath: String?
  pipelineStage: PipelineStage
  speakers: [Speaker]
  segments: [Segment]
  mix: MixSettings
  export: ExportSettings

Segment:
  id: Int
  start: Double
  end: Double
  duration: Double
  speakerId: String
  sourceText: String
  dubText: String
  literalTranslation: String
  emotion: String
  emotionIntensity: Double
  performanceInstruction: String
  qwenInstruction: String
  voiceProfileId: String
  generatedAudioPath: String?
  generatedDuration: Double?
  retryCount: Int
  fitStatus: FitStatus
  approved: Bool
  locked: Bool
  warnings: [String]

Speaker:
  speakerId: String
  displayName: String
  characterName: String?
  genderStyle: String?
  ageStyle: String?
  personalityStyle: String?
  color: Color
  voiceProfileId: String?
  segmentCount: Int
  totalSpeakingTime: Double
  confidence: Double

VoiceProfile:
  voiceProfileId: String
  speakerId: String?
  voiceType: VoiceType
  description: String
  qwenVoiceReference: String?
  referenceAudioPath: String?
  consentConfirmed: Bool
  generatedSegmentCount: Int

MixSettings:
  voiceRemovalStrength: Light | Medium | Strong | Manual
  vocalStemGainDb: Double
  backgroundGainDb: Double
  dubbedVoiceGainDb: Double
  duckingEnabled: Bool
  duckingAmountDb: Double
  duckingAttackMs: Double
  duckingReleaseMs: Double
  limiterEnabled: Bool
  targetLoudness: String
```

---

## Interaction Rules

```yaml
timing_fit:
  - If generatedDuration <= originalDuration: show FITS.
  - If generatedDuration <= originalDuration * 1.05: show FITS with minor warning.
  - If generatedDuration > originalDuration * 1.05: show TOO LONG.
  - If generatedDuration < originalDuration * 0.70: show TOO SHORT.
  - Too-long segments must expose "Shorten with Gemma".

qwen_instruction_safety:
  - Never place fake tags like [sigh], [laugh], [cry] inside spoken dubText.
  - Store acting directions in performanceInstruction and qwenInstruction.
  - Show visible note: "Instructions are not spoken text."
  - If user types bracket tags into dubText, warn that TTS may read them literally.

speaker_voice_consistency:
  - Every speaker must have one assigned voice before batch generation.
  - Changing a speaker voice warns that previously generated segments may need regeneration.
  - Voice profile is stored in voice registry and reused for all lines by that speaker.

background_preservation:
  - Background track must stay aligned from time zero.
  - Voice removal strength must be adjustable.
  - Show background damage warning after separation.
  - Final mix preview must include Original, Background Only, Dubbed Voice Only, and Final Mix.

human_review:
  - Segments with low speaker confidence are marked Needs Review.
  - Segments with multi-speaker text are marked Needs Review.
  - Segments with failed JSON or failed TTS are marked Failed.
  - Export preflight warns if unresolved segments remain.
```

---

## Acceptance Criteria

```yaml
acceptance_criteria:
  - UI clearly shows: Import → Analyze → Transcript → Speakers → Voices → AI Director → Dubbing → Mixing → Export.
  - Transcript table includes original duration, generated duration, emotion, voice, retry count, and fit status.
  - Right inspector allows editing timing, speaker, voice, emotion, dubbed text, and performance instruction.
  - Gemma/Gemini status is visible in AI Director screen.
  - Qwen3-TTS status is visible in Dubbing screen.
  - Voice registry ensures speaker voice consistency.
  - Mixing screen includes original voice removal strength and background damage warning.
  - Preview modes include Original, Background Only, Dubbed Voice Only, and Final Mix.
  - Export screen includes preflight checklist.
  - The UI is implementable in native SwiftUI without web dependencies.
```
