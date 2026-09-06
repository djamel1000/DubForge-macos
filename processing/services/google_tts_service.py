import os
import io
import json
import math
import struct
import subprocess
import wave
import requests
from processing.config import API_SETTINGS, TTS_SEGMENTS_DIR


class GoogleTTSService:
    """
    Google Cloud Text-to-Speech REST API integration.
    Supports Standard, WaveNet, Neural2, Studio, and Journey voices.
    Falls back to a synthetic WAV if the API is unavailable.
    Docs: https://cloud.google.com/text-to-speech/docs/reference/rest
    """

    ENDPOINT = "https://texttospeech.googleapis.com/v1/text:synthesize"

    @staticmethod
    def _get_access_token() -> str:
        configured = (
            API_SETTINGS.get("googleTtsAccessToken", "")
            or os.environ.get("GOOGLE_OAUTH_ACCESS_TOKEN", "")
        ).strip()
        if configured:
            return configured

        for cmd in (
            ["gcloud", "auth", "application-default", "print-access-token"],
            ["gcloud", "auth", "print-access-token"],
        ):
            try:
                result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=8)
                token = result.stdout.strip()
                if result.returncode == 0 and token:
                    return token
            except Exception:
                continue
        return ""

    @classmethod
    def _auth_request(cls, method: str, url: str, api_key: str = "", **kwargs):
        token = cls._get_access_token()
        headers = dict(kwargs.pop("headers", {}) or {})
        params = dict(kwargs.pop("params", {}) or {})
        if token:
            headers["Authorization"] = f"Bearer {token}"
        elif api_key:
            params["key"] = api_key
        else:
            raise RuntimeError("Google Cloud TTS credentials are missing. Configure OAuth/ADC credentials or a supported Cloud credential.")
        return requests.request(method, url, headers=headers, params=params, **kwargs)

    @staticmethod
    def list_voices(api_key: str, language_code: str = "") -> list:
        """
        Returns available Google TTS voices, optionally filtered by language code.
        """
        url = "https://texttospeech.googleapis.com/v1/voices"
        params = {}
        if language_code:
            params["languageCode"] = language_code
        try:
            resp = GoogleTTSService._auth_request("GET", url, api_key=api_key, params=params, timeout=8)
            if resp.status_code == 200:
                return resp.json().get("voices", [])
            err = resp.json().get("error", {}).get("message", resp.text[:200])
            print(f"Google TTS voice list error {resp.status_code}: {err}")
        except Exception as e:
            print(f"Google TTS voice list failed: {e}")
        return []

    @staticmethod
    def generate_mock_wav(output_path: str, duration: float, sample_rate: int = 24000) -> str:
        num_samples = int(duration * sample_rate)
        frequency = 300.0
        with wave.open(output_path, 'wb') as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(sample_rate)
            for i in range(num_samples):
                envelope = 1.0
                if i < 480:
                    envelope = i / 480.0
                elif i > num_samples - 1200:
                    envelope = (num_samples - i) / 1200.0
                val = math.sin(2.0 * math.pi * frequency * (i / sample_rate))
                w.writeframesraw(struct.pack('<h', int(val * 16384 * envelope)))
        return output_path

    @classmethod
    def generate(
        cls,
        text: str,
        voice_name: str,
        language_code: str,
        speaking_rate: float = 1.0,
        pitch: float = 0.0,
        target_duration: float = 3.0,
        segment_id: int = 1,
        project_id: str = "unassigned",
    ) -> str:
        """
        Synthesizes speech via Google Cloud TTS REST API.
        Returns the path to the output WAV file.
        """
        api_key = API_SETTINGS.get("googleTtsApiKey", "").strip()
        output_dir = os.path.join(str(TTS_SEGMENTS_DIR), project_id, "google")
        os.makedirs(output_dir, exist_ok=True)
        output_filename = f"segment_{segment_id:04d}_gtts.wav"
        output_path = os.path.join(output_dir, output_filename)

        if not api_key and not cls._get_access_token():
            if API_SETTINGS.get("allowMockTTS", False):
                print("Google TTS: no credentials configured, generating mock WAV because allowMockTTS is enabled.")
                return cls.generate_mock_wav(output_path, duration=target_duration)
            raise RuntimeError("Google Cloud TTS credentials are missing. Run `gcloud auth application-default login` or configure a valid Google Cloud credential.")

        # Choose audio encoding — LINEAR16 gives us a WAV directly
        payload = {
            "input": {"text": text},
            "voice": {
                "languageCode": language_code or "en-US",
                "name": voice_name or "",
            },
            "audioConfig": {
                "audioEncoding": "LINEAR16",
                "speakingRate": max(0.25, min(4.0, speaking_rate)),
                "pitch": max(-20.0, min(20.0, pitch)),
                "sampleRateHertz": 24000,
            },
        }

        try:
            resp = cls._auth_request("POST", cls.ENDPOINT, api_key=api_key, json=payload, timeout=15)
            if resp.status_code == 200:
                audio_b64 = resp.json().get("audioContent", "")
                if audio_b64:
                    import base64
                    audio_bytes = base64.b64decode(audio_b64)
                    # Google LINEAR16 gives raw PCM, wrap in WAV
                    sample_rate = 24000
                    with wave.open(output_path, 'wb') as wf:
                        wf.setnchannels(1)
                        wf.setsampwidth(2)
                        wf.setframerate(sample_rate)
                        wf.writeframes(audio_bytes)
                    print(f"Google TTS: segment {segment_id} synthesized OK.")
                    return output_path
                else:
                    print(f"Google TTS: empty audio content in response.")
            else:
                err = resp.json().get("error", {}).get("message", resp.text[:200])
                raise RuntimeError(f"Google TTS API error {resp.status_code}: {err}")
        except Exception as e:
            if API_SETTINGS.get("allowMockTTS", False):
                print(f"Google TTS request failed, generating mock WAV because allowMockTTS is enabled: {e}")
                return cls.generate_mock_wav(output_path, duration=target_duration)
            raise

        if API_SETTINGS.get("allowMockTTS", False):
            return cls.generate_mock_wav(output_path, duration=target_duration)
        raise RuntimeError("Google TTS returned no audio content.")
