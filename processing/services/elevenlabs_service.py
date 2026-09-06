import os
import math
import struct
import wave
import requests
from processing.config import API_SETTINGS, TTS_SEGMENTS_DIR


class ElevenLabsService:
    """
    ElevenLabs Text-to-Speech REST API integration.
    Supports all ElevenLabs multilingual v2, Flash, and Turbo models.
    Docs: https://elevenlabs.io/docs/api-reference/text-to-speech
    """

    BASE_URL = "https://api.elevenlabs.io/v1"

    @staticmethod
    def list_voices(api_key: str) -> list:
        """
        Returns all available ElevenLabs voices for the account.
        Each dict has: voice_id, name, category, labels, preview_url.
        """
        if not api_key:
            return []
        headers = {"xi-api-key": api_key}
        try:
            resp = requests.get(f"{ElevenLabsService.BASE_URL}/voices", headers=headers, timeout=8)
            if resp.status_code == 200:
                return resp.json().get("voices", [])
        except Exception:
            pass
        return []

    @staticmethod
    def list_models(api_key: str) -> list:
        """
        Returns available ElevenLabs TTS models.
        """
        if not api_key:
            return []
        headers = {"xi-api-key": api_key}
        try:
            resp = requests.get(f"{ElevenLabsService.BASE_URL}/models", headers=headers, timeout=8)
            if resp.status_code == 200:
                return resp.json()  # list of model dicts
        except Exception:
            pass
        # Curated fallback
        return [
            {"model_id": "eleven_multilingual_v2",    "name": "Multilingual v2 (best quality)"},
            {"model_id": "eleven_flash_v2_5",         "name": "Flash v2.5 (fast, multilingual)"},
            {"model_id": "eleven_flash_v2",           "name": "Flash v2"},
            {"model_id": "eleven_turbo_v2_5",         "name": "Turbo v2.5 (low latency)"},
            {"model_id": "eleven_turbo_v2",           "name": "Turbo v2"},
            {"model_id": "eleven_monolingual_v1",     "name": "English v1"},
        ]

    @staticmethod
    def generate_mock_wav(output_path: str, duration: float, sample_rate: int = 44100) -> str:
        num_samples = int(duration * sample_rate)
        frequency = 320.0
        with wave.open(output_path, 'wb') as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(sample_rate)
            for i in range(num_samples):
                envelope = 1.0
                if i < 480:
                    envelope = i / 480.0
                elif i > num_samples - 2200:
                    envelope = (num_samples - i) / 2200.0
                val = math.sin(2.0 * math.pi * frequency * (i / sample_rate))
                w.writeframesraw(struct.pack('<h', int(val * 16384 * envelope)))
        return output_path

    @classmethod
    def generate(
        cls,
        text: str,
        voice_id: str,
        model_id: str = "eleven_multilingual_v2",
        stability: float = 0.5,
        similarity_boost: float = 0.75,
        style: float = 0.0,
        speed: float = 1.0,
        target_duration: float = 3.0,
        segment_id: int = 1,
        project_id: str = "unassigned",
    ) -> str:
        """
        Synthesizes speech via ElevenLabs API.
        Returns path to the output MP3 file (ElevenLabs natively returns MP3).
        """
        api_key = API_SETTINGS.get("elevenlabsApiKey", "").strip()
        voice_id = voice_id or API_SETTINGS.get("elevenlabsVoiceId", "").strip()
        model_id = model_id or API_SETTINGS.get("elevenlabsModelId", "eleven_multilingual_v2")

        output_dir = os.path.join(str(TTS_SEGMENTS_DIR), project_id, "elevenlabs")
        os.makedirs(output_dir, exist_ok=True)
        output_filename = f"segment_{segment_id:04d}_el.mp3"
        output_path = os.path.join(output_dir, output_filename)

        if not api_key or not voice_id:
            if API_SETTINGS.get("allowMockTTS", False):
                print("ElevenLabs: missing credentials, generating mock WAV because allowMockTTS is enabled.")
                wav_path = output_path.replace(".mp3", "_mock.wav")
                return cls.generate_mock_wav(wav_path, duration=target_duration)
            raise RuntimeError("ElevenLabs API key and voice ID are required for synthesis.")

        url = f"{cls.BASE_URL}/text-to-speech/{voice_id}"
        headers = {
            "xi-api-key": api_key,
            "Content-Type": "application/json",
            "Accept": "audio/mpeg",
        }
        payload = {
            "text": text,
            "model_id": model_id,
            "voice_settings": {
                "stability": max(0.0, min(1.0, stability)),
                "similarity_boost": max(0.0, min(1.0, similarity_boost)),
                "style": max(0.0, min(1.0, style)),
                "use_speaker_boost": True,
                "speed": max(0.7, min(1.2, speed)),
            },
        }

        try:
            resp = requests.post(url, headers=headers, json=payload, timeout=30, stream=True)
            if resp.status_code == 200:
                with open(output_path, 'wb') as f:
                    for chunk in resp.iter_content(chunk_size=8192):
                        f.write(chunk)
                print(f"ElevenLabs: segment {segment_id} synthesized OK.")
                return output_path
            else:
                err = resp.json().get("detail", {})
                status_msg = err.get("message", str(err)) if isinstance(err, dict) else str(err)
                raise RuntimeError(f"ElevenLabs API error {resp.status_code}: {status_msg}")
        except Exception as e:
            if API_SETTINGS.get("allowMockTTS", False):
                print(f"ElevenLabs request failed, generating mock WAV because allowMockTTS is enabled: {e}")
                wav_path = output_path.replace(".mp3", "_mock.wav")
                return cls.generate_mock_wav(wav_path, duration=target_duration)
            raise

        raise RuntimeError("ElevenLabs returned no audio content.")
