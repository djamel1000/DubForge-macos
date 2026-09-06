import os
from processing.config import MIXES_DIR

class MixerService:
    @classmethod
    def mix(
        cls,
        background_wav: str,
        vocals_residual_wav: str,
        dubbed_voice_track_wav: str,
        output_mix_wav: str,
        mix_settings: dict
    ) -> bool:
        """
        Mixes background track, residual vocals, and dubbed voices with sidechain ducking,
        limiter, and loudness normalization, utilizing native FFmpeg filters.
        """
        from processing.services.ffmpeg_service import FFmpegService
        ffmpeg_bin = FFmpegService.get_ffmpeg_binary()
        
        # Parse settings
        bg_gain = mix_settings.get("backgroundGainDb", 0.0)
        vocal_gain = mix_settings.get("vocalStemGainDb", -24.0)
        dub_gain = mix_settings.get("dubbedVoiceGainDb", 0.0)
        
        ducking_enabled = mix_settings.get("duckingEnabled", True)
        duck_amt = mix_settings.get("duckingAmountDb", 4.0)
        attack = mix_settings.get("duckingAttackMs", 80.0)
        release = mix_settings.get("duckingReleaseMs", 250.0)
        
        limiter_enabled = mix_settings.get("limiterEnabled", True)
        target_loudness = mix_settings.get("targetLoudness", "-16 LUFS Web Video")
        
        # Map target loudness option to LUFS value
        lufs_val = -16.0
        if "loud online" in target_loudness.lower() or "-14" in target_loudness:
            lufs_val = -14.0
        elif "broadcast" in target_loudness.lower() or "-23" in target_loudness:
            lufs_val = -23.0
            
        # Convert gains from dB to multipliers
        bg_mult = 10 ** (bg_gain / 20.0)
        vocal_mult = 10 ** (vocal_gain / 20.0)
        dub_mult = 10 ** (dub_gain / 20.0)
        
        # Build filter graph
        # [0:a] is background, [1:a] is vocal residual, [2:a] is dubbed voices
        # 1. Apply separate volume gains
        # 2. If vocal residual is active, mix it into background
        # 3. Apply sidechain compress if ducking is enabled
        # 4. Mix dubbed voices
        # 5. Enforce limiter if enabled
        
        filter_parts = []
        filter_parts.append(f"[0:a]volume={bg_mult}[bg_vol]")
        filter_parts.append(f"[1:a]volume={vocal_mult}[voc_vol]")
        filter_parts.append(f"[2:a]volume={dub_mult}[dub_vol]")
        
        # Mix bg and original vocals first
        filter_parts.append("[bg_vol][voc_vol]amix=inputs=2:weights='1.0 1.0'[bg_total]")
        
        if ducking_enabled:
            # sidechaincompress threshold: mapping ducking gain to threshold
            threshold_db = -12.0 - duck_amt
            filter_parts.append(
                f"[bg_total][dub_vol]sidechaincompress=threshold={threshold_db}dB:ratio=4:attack={attack}:release={release}[ducked_bg]"
            )
            # Mix ducked background and dubbed voices
            filter_parts.append("[ducked_bg][dub_vol]amix=inputs=2:weights='1.0 1.0'[mixed_pre]")
        else:
            filter_parts.append("[bg_total][dub_vol]amix=inputs=2:weights='1.0 1.0'[mixed_pre]")
            
        if limiter_enabled:
            # Enforce hard limiter at -1.5dB ceiling
            filter_parts.append("[mixed_pre]alimiter=level_in=1.0:level_out=1.0:limit=0.84:attack=5:release=50[mixed_final]")
        else:
            filter_parts.append("[mixed_pre]copy[mixed_final]")
            
        filter_str = ";".join(filter_parts)
        
        output_root, _ = os.path.splitext(output_mix_wav)
        temp_mix_path = f"{output_root}_raw.wav"
        cmd = [
            ffmpeg_bin, "-y",
            "-i", background_wav,
            "-i", vocals_residual_wav,
            "-i", dubbed_voice_track_wav,
            "-filter_complex", filter_str,
            "-map", "[mixed_final]",
            temp_mix_path
        ]
        
        success = FFmpegService.run_cmd(cmd)
        if not success:
            return False
            
        # Apply final loudness normalization to output_mix_wav
        return FFmpegService.loudness_normalize(temp_mix_path, output_mix_wav, target_lufs=lufs_val)

    @classmethod
    def assemble_dubbed_voice_canvas(cls, segments: list, duration: float, output_path: str) -> bool:
        """
        Creates a single unified audio track by positioning generated TTS clips
        at their exact starting timestamps on a silent background canvas.
        """
        from processing.services.ffmpeg_service import FFmpegService
        ffmpeg_bin = FFmpegService.get_ffmpeg_binary()
        
        # If no segments, generate silence
        if not segments:
            cmd = [
                ffmpeg_bin, "-y",
                "-f", "lavfi",
                "-i", f"anullsrc=r=48000:cl=stereo",
                "-t", str(max(1.0, duration)),
                output_path
            ]
            return FFmpegService.run_cmd(cmd)
            
        # We will use FFmpeg's adelay filter to position each clip, then mix them together.
        # Format: [0:a]adelay=DELAY|DELAY[a0]; [1:a]adelay=DELAY|DELAY[a1]; ... [a0][a1]amix=inputs=N
        inputs = []
        filter_parts = []
        mix_inputs = []
        
        # Create a silent base stem to ensure the track lasts the full duration
        inputs.extend([
            "-f", "lavfi",
            "-i", f"anullsrc=r=48000:cl=stereo"
        ])
        # delay=0, trim=duration
        filter_parts.append(f"[0:a]atrim=end={duration},asetpts=PTS-STARTPTS[a_base]")
        mix_inputs.append("[a_base]")
        
        valid_idx = 1
        for seg in segments:
            wav_path = seg.get("generatedAudioPath")
            if wav_path and os.path.exists(wav_path):
                inputs.extend(["-i", wav_path])
                # adelay expects delay in milliseconds: delay_ms = start_sec * 1000
                delay_ms = int(seg["start"] * 1000)
                # adelay requires values for both left and right channels: DELAY|DELAY
                filter_parts.append(f"[{valid_idx}:a]adelay={delay_ms}|{delay_ms}[a{valid_idx}]")
                mix_inputs.append(f"[a{valid_idx}]")
                valid_idx += 1
                
        if len(mix_inputs) > 1:
            mix_str = "".join(mix_inputs)
            filter_parts.append(f"{mix_str}amix=inputs={len(mix_inputs)}[out]")
        else:
            filter_parts.append("[a_base]copy[out]")
            
        filter_str = ";".join(filter_parts)
        
        cmd = [ffmpeg_bin, "-y"]
        cmd.extend(inputs)
        cmd.extend([
            "-filter_complex", filter_str,
            "-map", "[out]",
            output_path
        ])
        
        return FFmpegService.run_cmd(cmd)
