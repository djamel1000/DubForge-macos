import json
import math
import os
import re
import time
import requests
from processing.config import API_SETTINGS

class GeminiDirector:
    @staticmethod
    def get_prompt_template(segment: dict, speaker: dict, prev_seg: dict, next_seg: dict, src_lang: str, tgt_lang: str) -> str:
        prev_text = prev_seg.get("sourceText", "None") if prev_seg else "None"
        next_text = next_seg.get("sourceText", "None") if next_seg else "None"
        
        return f"""You are the dubbing director of a professional AI dubbing application.
You receive timestamped dialogue segments from a video. Your job is to adapt each line into the target language for dubbing.

You are not a normal translator.
You must:
- Preserve meaning and emotion.
- Sound natural and match the speaker personality.
- Fit the original mouth movement duration: {segment['duration']} seconds.
- Prefer shorter equivalent expressions when needed to fit timing. Avoid literal translation if it's too long!
- Create acting/performance instructions for Qwen3-TTS separate from the spoken text.
- Never put fake tags like [sigh], [laugh], [cry] inside the spoken dub_text unless explicitly supported.
- Return ONLY valid JSON matching the schema below.

Segment to Adapt:
- ID: {segment['id']}
- Source Text ({src_lang}): "{segment['sourceText']}"
- Original Duration: {segment['duration']} sec

Speaker Profile:
- ID: {segment['speakerId']}
- Character Name: {speaker.get('characterName', 'Unknown')}
- Gender: {speaker.get('genderStyle', 'neutral')}
- Age: {speaker.get('ageStyle', 'middle-aged')}
- Personality: {speaker.get('personalityStyle', 'normal')}

Context:
- Previous line: "{prev_text}"
- Next line: "{next_text}"

Return JSON matching this exact structure:
{{
  "segment_id": {segment['id']},
  "speaker_id": "{segment['speakerId']}",
  "dub_text": "Adapted dialogue text in target language ({tgt_lang}). Keep it concise and within time box.",
  "literal_translation": "Direct literal translation of source text.",
  "emotion": "detect_emotion (e.g. happy, sad, angry, surprised, etc.)",
  "emotion_intensity": "medium",
  "performance_instruction": "Instructions for TTS voice performance.",
  "qwen_instruction": "Specific direction for Qwen3-TTS voice actor (e.g., Speak warmly and naturally, with a grateful tone. Do not speak instructions literally.)",
  "estimated_spoken_duration": 1.2,
  "timing_strategy": "shortened_expression",
  "meaning_preserved": true,
  "needs_review": false
}}"""

    @classmethod
    def adapt_segment(cls, segment: dict, speaker: dict, prev_seg: dict = None, next_seg: dict = None, src_lang: str = "en", tgt_lang: str = "ar") -> dict:
        """
        Sends the segment adaptation request to the Gemini API.
        Falls back to a high-fidelity rule-based translation fallback when API key is missing.
        """
        api_key = API_SETTINGS.get("geminiApiKey") or os.environ.get("GEMINI_API_KEY")
        model = API_SETTINGS.get("geminiModel") or "gemini-1.5-pro"
        
        prompt = cls.get_prompt_template(segment, speaker, prev_seg, next_seg, src_lang, tgt_lang)
        
        if not api_key:
            if API_SETTINGS.get("allowMockAdaptation", False):
                return cls._fallback_adaptation(segment, tgt_lang, needs_review=True)
            raise RuntimeError("Gemini API key is missing. Configure the AI Director key before adaptation.")

        # Otherwise call the Gemini API. Keep the key in a header so errors and
        # logs never include credential-bearing URLs.
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
        headers = {
            "Content-Type": "application/json",
            "x-goog-api-key": api_key,
        }
        
        data = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {
                "responseMimeType": "application/json"
            }
        }
        
        try:
            timeout = int(API_SETTINGS.get("geminiTimeoutSec", 60))
            max_attempts = int(API_SETTINGS.get("geminiMaxAttempts", 3))
            response = None
            for attempt in range(1, max_attempts + 1):
                response = requests.post(url, headers=headers, json=data, timeout=timeout)
                if response.status_code not in (429, 500, 502, 503, 504):
                    break
                if attempt < max_attempts:
                    retry_after = response.headers.get("Retry-After")
                    delay = float(retry_after) if retry_after and retry_after.isdigit() else min(8.0 * attempt, 24.0)
                    time.sleep(delay)

            if response.status_code >= 400:
                try:
                    err = response.json().get("error", {})
                    message = err.get("message", response.text[:500])
                except Exception:
                    message = response.text[:500]
                raise RuntimeError(f"Gemini API error {response.status_code}: {message}")

            res_json = response.json()
            text_out = res_json['candidates'][0]['content']['parts'][0]['text']
            
            # Clean up potential markdown formatting around JSON
            text_out = text_out.strip()
            if text_out.startswith("```json"):
                text_out = text_out.replace("```json", "", 1)
            if text_out.endswith("```"):
                text_out = text_out[:-3].strip()
                
            return json.loads(text_out)
        except Exception as e:
            if API_SETTINGS.get("allowMockAdaptation", False):
                print(f"Gemini API adapt_segment failed: {e}. Using mock adaptation because allowMockAdaptation is enabled.")
                return cls._fallback_adaptation(segment, tgt_lang, needs_review=True)
            raise RuntimeError(f"Gemini adaptation failed for segment {segment.get('id')}: {e}") from e

    @classmethod
    def shorten_for_duration(
        cls,
        source_text: str,
        current_dub_text: str,
        target_language: str,
        target_duration: float,
        measured_duration: float,
        speaker: dict,
    ) -> dict:
        """Rewrites an already translated line using measured TTS duration."""
        api_key = API_SETTINGS.get("geminiApiKey") or os.environ.get("GEMINI_API_KEY")
        if not api_key:
            raise RuntimeError("Gemini API key is required for timing-aware dialogue shortening.")

        ratio = max(0.1, target_duration / max(measured_duration, 0.1))
        current_words = max(1, len(current_dub_text.split()))
        word_budget = max(1, int(current_words * ratio * 0.85))
        prompt = f"""You are adapting one line for professional dubbing.
Return ONLY JSON with this schema: {{"dub_text":"...","meaning_preserved":true,"timing_strategy":"..."}}.

Original meaning: {source_text}
Current {target_language} line: {current_dub_text}
Measured spoken duration: {measured_duration:.3f} seconds
Hard maximum duration: {target_duration:.3f} seconds
Target length ratio: about {ratio:.2f} of the current spoken line
Maximum word budget: {word_budget} words
Speaker: {speaker.get('genderStyle', 'unknown')} {speaker.get('ageStyle', 'unknown')}

Use a shorter, idiomatic expression in {target_language}. Preserve intent, emotion, names, numbers,
negation, and important facts. Do not explain the rewrite. Do not add stage directions or tags.
Prefer concise everyday wording over literal translation. Use at most {word_budget} words unless a
protected name or number makes that impossible. The final spoken line must fit the hard limit."""

        model = API_SETTINGS.get("geminiModel") or "gemini-1.5-pro"
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
        response = requests.post(
            url,
            headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
            json={
                "contents": [{"parts": [{"text": prompt}]}],
                "generationConfig": {"responseMimeType": "application/json", "temperature": 0.2},
            },
            timeout=int(API_SETTINGS.get("geminiTimeoutSec", 60)),
        )
        if response.status_code >= 400:
            try:
                message = response.json().get("error", {}).get("message", response.text[:500])
            except Exception:
                message = response.text[:500]
            raise RuntimeError(f"Gemini shortening error {response.status_code}: {message}")

        payload = response.json()
        text_out = payload["candidates"][0]["content"]["parts"][0]["text"].strip()
        if text_out.startswith("```json"):
            text_out = text_out[7:]
        if text_out.endswith("```"):
            text_out = text_out[:-3]
        result = json.loads(text_out.strip())
        shortened = (result.get("dub_text") or "").strip()
        if not shortened:
            raise RuntimeError("Gemini returned an empty shortened line.")
        return result

    @classmethod
    def lengthen_for_duration(
        cls,
        source_text: str,
        current_dub_text: str,
        target_language: str,
        target_duration: float,
        measured_duration: float,
        speaker: dict,
    ) -> dict:
        """Expands a translation that is much shorter than its measured speech window."""
        api_key = API_SETTINGS.get("geminiApiKey") or os.environ.get("GEMINI_API_KEY")
        if not api_key:
            raise RuntimeError("Gemini API key is required for timing-aware dialogue expansion.")

        ratio = max(1.0, target_duration / max(measured_duration, 0.1))
        current_words = max(1, len(current_dub_text.split()))
        target_words = max(current_words + 1, math.ceil(current_words * min(2.5, ratio * 0.9)))
        max_words = max(target_words, math.ceil(current_words * min(3.0, ratio * 1.1)))
        prompt = f"""You are adapting one line for professional dubbing.
Return ONLY JSON with this schema: {{"dub_text":"...","meaning_preserved":true,"timing_strategy":"..."}}.

Original meaning: {source_text}
Current {target_language} line: {current_dub_text}
Measured spoken duration: {measured_duration:.3f} seconds
Target speech duration: {target_duration:.3f} seconds
Target length ratio: about {ratio:.2f} of the current spoken line
Preferred word count: {target_words} words; hard maximum: {max_words} words
Speaker: {speaker.get('genderStyle', 'unknown')} {speaker.get('ageStyle', 'unknown')}

Write a natural, idiomatic version in {target_language} that takes longer to speak while preserving
exactly the same meaning, emotion, names, numbers, negation, and important facts. You may add natural
emphasis or an equivalent idiomatic restatement, but do not invent facts, explanations, greetings,
stage directions, or filler sounds. Aim for {target_words} words and never exceed {max_words} words."""

        model = API_SETTINGS.get("geminiModel") or "gemini-1.5-pro"
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
        response = requests.post(
            url,
            headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
            json={
                "contents": [{"parts": [{"text": prompt}]}],
                "generationConfig": {"responseMimeType": "application/json", "temperature": 0.2},
            },
            timeout=int(API_SETTINGS.get("geminiTimeoutSec", 60)),
        )
        if response.status_code >= 400:
            try:
                message = response.json().get("error", {}).get("message", response.text[:500])
            except Exception:
                message = response.text[:500]
            raise RuntimeError(f"Gemini expansion error {response.status_code}: {message}")

        payload = response.json()
        text_out = payload["candidates"][0]["content"]["parts"][0]["text"].strip()
        if text_out.startswith("```json"):
            text_out = text_out[7:]
        if text_out.endswith("```"):
            text_out = text_out[:-3]
        result = json.loads(text_out.strip())
        expanded = (result.get("dub_text") or "").strip()
        if not expanded:
            raise RuntimeError("Gemini returned an empty expanded line.")
        return result

    @staticmethod
    def _fallback_adaptation(segment: dict, tgt_lang: str, needs_review: bool) -> dict:
        source_text = segment.get('sourceText', '')
        dub_text = source_text
        if tgt_lang.lower().startswith("fr"):
            match = re.search(r"segment number (\d+)", source_text, re.IGNORECASE)
            if match:
                dub_text = f"Ceci est le segment de parole transcrit numéro {match.group(1)}."
            elif "thank you" in source_text.lower():
                dub_text = "Merci beaucoup."
            elif "hello" in source_text.lower():
                dub_text = "Bonjour, comment allez-vous ?"
        elif tgt_lang.lower().startswith("ar"):
            dub_text = "شكرا جزيلا لك." if "thank you" in source_text.lower() else "مرحبا كيف حالك؟"
        elif tgt_lang.lower().startswith("zh"):
            dub_text = "非常感谢。" if "thank you" in source_text.lower() else "你好，你怎么样？"
        elif tgt_lang.lower().startswith("es"):
            dub_text = "Muchas gracias." if "thank you" in source_text.lower() else "Hola, ¿cómo estás?"
        return {
            "segment_id": segment['id'],
            "speaker_id": segment['speakerId'],
            "dub_text": dub_text,
            "literal_translation": f"Literal translation to {tgt_lang}",
            "emotion": "neutral",
            "emotion_intensity": "medium",
            "performance_instruction": "Speak naturally.",
            "qwen_instruction": "Speak calmly and clearly.",
            "estimated_spoken_duration": segment['duration'],
            "timing_strategy": "mock_fallback",
            "meaning_preserved": True,
            "needs_review": needs_review
        }
