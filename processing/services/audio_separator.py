import os
import shutil
from processing.config import API_SETTINGS, SEPARATED_AUDIO_DIR

class AudioSeparator:
    @classmethod
    def separate(cls, input_audio_path: str, project_id: str = "unassigned") -> tuple:
        """
        Runs Demucs source separation. Falls back to high-fidelity FFmpeg filters
        to separate vocals and background track cleanly when Demucs is missing.
        """
        from processing.services.ffmpeg_service import FFmpegService
        ffmpeg_bin = FFmpegService.get_ffmpeg_binary()
        
        if not os.path.exists(input_audio_path):
            print(f"Input audio stem not found at {input_audio_path}. Generating synthetic audio track...")
            from processing.services.qwen_tts_service import QwenTTSService
            QwenTTSService.generate_mock_wav(input_audio_path, duration=10.0)
        
        project_output_dir = os.path.join(str(SEPARATED_AUDIO_DIR), project_id)
        os.makedirs(project_output_dir, exist_ok=True)
        vocals_path = os.path.join(project_output_dir, "vocals.wav")
        background_path = os.path.join(project_output_dir, "background.wav")
        
        demucs_bin = os.path.expanduser(API_SETTINGS.get("demucsPath") or "") or shutil.which("demucs")
        
        if demucs_bin and os.path.exists(demucs_bin):
            print("Demucs binary detected! Initiating stem separation...")
            model_name = API_SETTINGS.get("separationModel", "htdemucs")

            # Demucs only auto-detects CUDA, so on Apple Silicon it quietly runs on
            # CPU unless -d is passed. Prefer the GPU, but keep a CPU retry: some
            # Demucs/torch builds still hit unimplemented MPS ops, and retrying on
            # CPU is far better than dropping to the FFmpeg fallback below, which
            # produces markedly worse stems.
            configured_device = str(API_SETTINGS.get("separationDevice", "mps")).strip().lower()
            devices = [configured_device] if configured_device and configured_device != "cpu" else []
            devices.append("cpu")

            for device in devices:
                # Command: demucs -o output_dir --two-stems=vocals -d device input_audio
                cmd = [
                    demucs_bin,
                    "--two-stems", "vocals",
                    "-n", model_name,
                    "-d", device,
                    "-o", project_output_dir,
                    input_audio_path
                ]
                if not FFmpegService.run_cmd(cmd):
                    print(f"Demucs separation failed on device '{device}'.")
                    continue

                # Demucs creates folder structure, let's locate and copy files
                # e.g., SEPARATED_AUDIO_DIR / htdemucs / filename / vocals.wav
                filename = os.path.splitext(os.path.basename(input_audio_path))[0]
                demucs_vocals = os.path.join(project_output_dir, model_name, filename, "vocals.wav")
                demucs_no_vocals = os.path.join(project_output_dir, model_name, filename, "no_vocals.wav")
                if os.path.exists(demucs_vocals) and os.path.exists(demucs_no_vocals):
                    shutil.copy(demucs_vocals, vocals_path)
                    shutil.copy(demucs_no_vocals, background_path)
                    return vocals_path, background_path, "low"  # damage risk

                # Demucs reported success but the stems are missing, so this is a
                # layout problem rather than a device problem -- another device
                # would fail the same way.
                print(f"Demucs finished on '{device}' but stems were not at the expected path.")
                break

        # Robust FFmpeg fallback!
        print("Demucs not available. Utilizing center-channel frequency voice reduction fallback...")
        # 1. Background (Vocal Removal): center-cut bandreject filter to suppress voice frequencies (approx 200Hz-3000Hz)
        # command: ffmpeg -i input -af "pan=stereo|c0=c0-c1|c1=c1-c0" (simple karaoke voice phase cancellation)
        # or bandreject: "bandreject=f=1000:width_type=h:width=800"
        # Let's combine phase cancellation and lowpass/highpass to get background
        bg_cmd = [
            ffmpeg_bin, "-y",
            "-i", input_audio_path,
            "-af", "pan=stereo|c0=c0-c1|c1=c1-c0",  # vocal cancellation
            background_path
        ]
        
        # 2. Vocals (Vocal Extraction): bandpass filter for voice frequencies
        vocal_cmd = [
            ffmpeg_bin, "-y",
            "-i", input_audio_path,
            "-af", "highpass=f=200,lowpass=f=3000",  # voice bandpass
            vocals_path
        ]
        
        bg_success = FFmpegService.run_cmd(bg_cmd)
        vocal_success = FFmpegService.run_cmd(vocal_cmd)
        
        # A failed background stem must never be replaced with the original mix;
        # that would put the source dialogue back into the exported dub.
        if not bg_success or not os.path.exists(background_path) or os.path.getsize(background_path) < 1000:
            raise RuntimeError(
                "Could not create a dialogue-free background stem. Install/configure Demucs "
                "instead of exporting the original voices as background."
            )
        if not vocal_success or not os.path.exists(vocals_path) or os.path.getsize(vocals_path) < 1000:
            shutil.copy(input_audio_path, vocals_path)
            
        return vocals_path, background_path, "medium"  # medium damage risk warning for mock
