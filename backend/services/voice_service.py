from __future__ import annotations
import base64
import logging
from typing import Literal, Any
import httpx
from backend.config import Settings

logger = logging.getLogger(__name__)

class VoiceService:
    """Qwen/DashScope ASR + TTS voice service."""

    def __init__(self, settings: Settings, device_service: Any | None = None) -> None:
        self._settings = settings
        self._device_service = device_service

    @property
    def _api_key(self) -> str:
        return self._settings.dashscope_api_key.strip()

    @property
    def _configured(self) -> bool:
        return bool(self._api_key)

    def transcribe(self, audio_bytes: bytes, *, fmt: str = "wav") -> dict[str, object]:
        """Call DashScope Paraformer ASR to transcribe audio bytes."""
        if not self._configured:
            return {"ok": False, "text": "", "error": "DASHSCOPE_API_KEY not configured"}

        model_id = self._settings.qwen_asr_model_id.strip().lower()
        try:
            import dashscope
            dashscope.api_key = self._api_key
            
            import tempfile, os
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix=f".{fmt}")
            try:
                tmp.write(audio_bytes)
                tmp.close()
                from dashscope.audio.asr import Recognition, RecognitionCallback
                recognizer = Recognition(model=model_id, callback=RecognitionCallback(), format=fmt, sample_rate=16000)
                result = recognizer.call(tmp.name)
                if getattr(result, "status_code", None) == 200:
                    sentences = result.get_sentence()
                    text = " ".join(s.get("text", "") for s in (sentences or []) if isinstance(s, dict)).strip()
                    return {"ok": True, "text": text, "provider": f"dashscope/{model_id}"}
                return {"ok": False, "text": "", "error": getattr(result, "message", "ASR failed")}
            finally:
                if os.path.exists(tmp.name):
                    os.unlink(tmp.name)
        except Exception as exc:
            logger.warning("ASR failed: %s", exc)
            return {"ok": False, "text": "", "error": str(exc)}

    def omni_chat(self, audio_bytes: bytes, *, prompt: str = "请理解这段语音并回答。", fmt: str = "wav", device_mac: str | None = None) -> dict[str, object]:
        """Call Qwen-Omni to understand audio and generate text."""
        if not self._configured:
            return {"ok": False, "text": "", "error": "DASHSCOPE_API_KEY not configured"}

        model_id = self._settings.qwen_omni_model_id
        vitals_context = ""
        if device_mac and self._device_service:
            try:
                from backend.dependencies import get_display_latest_sample
                sample = get_display_latest_sample(device_mac, "mock") # Default to mock for safety
                if sample:
                    vitals_context = f"\n用户当前健康数据：心率 {sample.heart_rate}bpm, 血氧 {sample.blood_oxygen}%, 体温 {sample.temperature}℃, 步数 {sample.steps}。"
            except Exception:
                pass

        try:
            import dashscope
            dashscope.api_key = self._api_key
            
            import base64
            audio_b64 = base64.b64encode(audio_bytes).decode("utf-8")
            
            messages = [
                {
                    "role": "system",
                    "content": [{"text": f"你是一个专业的健康助手。{vitals_context}\n请理解用户的语音输入并给予简明扼要的回答，字数控制在 50 字以内，适合语音播报。"}]
                },
                {
                    "role": "user",
                     "content": [
                        {"audio": f"data:audio/{fmt};base64,{audio_b64}"},
                        {"text": prompt}
                    ]
                }
            ]
            
            response = dashscope.MultiModalConversation.call(model=model_id, messages=messages, stream=False)
            if response.status_code == 200:
                answer = response.output.choices[0].message.content[0].get("text", "")
                # 强制将 AI 回答放入 text 字段供移动端展示
                return {"ok": True, "text": answer, "answer": answer, "provider": f"dashscope/{model_id}"}
            
            return {"ok": False, "text": "", "error": response.message}
        except Exception as exc:
            logger.error("Omni chat failed: %s", exc)
            return {"ok": False, "text": "", "error": str(exc)}

    def synthesize(self, text: str, *, voice: str = "longxiaochun", speed: float = 1.0, fmt: Literal["mp3", "wav", "pcm"] = "mp3", workspace: str | None = None) -> dict[str, object]:
        """Call DashScope TTS and return audio data."""
        if not self._configured:
            return {"ok": False, "audio_b64": "", "error": "DASHSCOPE_API_KEY not configured"}

        if not text.strip():
            return {"ok": False, "audio_b64": "", "error": "empty text"}

        model_id = self._settings.qwen_tts_model_id.strip().lower()
        try:
            import dashscope
            import base64
            dashscope.api_key = self._api_key
            
            # --- Branch 1: Qwen3-TTS series (qwen3-tts-flash, qwen-tts-flash, etc.) ---
            if "qwen-tts" in model_id or "qwen3-tts" in model_id:
                # Map old Sambert/CosyVoice IDs to Qwen-TTS official voices (Case Intensive)
                voice_map = {
                    "longxiaochun": "Cherry",
                    "longwan": "Cherry",
                    "longcheng": "Genny",
                    "longhua": "Genny",
                    "longyingtian": "Genny"
                }
                target_voice = voice_map.get(voice.lower(), "Cherry")
                
                # According to reference: text, voice, language_type are direct arguments
                response = dashscope.MultiModalConversation.call(
                    model=model_id,
                    text=text,
                    voice=target_voice,
                    language_type="Chinese",
                    parameters={
                        "format": fmt,
                        "sample_rate": 16000
                    },
                    stream=False
                )
                
                if response.status_code == 200:
                    # Based on reference: data is in output.audio.data (Base64 string)
                    output = getattr(response, "output", None)
                    if output and hasattr(output, "audio") and hasattr(output.audio, "data"):
                        audio_b64 = output.audio.data
                        if not audio_b64:
                             return {"ok": False, "audio_b64": "", "error": "Model returned empty audio data"}
                        # Return directly since it's already base64'd according to reference
                        return {"ok": True, "audio_b64": audio_b64, "fmt": fmt, "provider": f"dashscope/{model_id}", "voice": target_voice}
                    else:
                        return {"ok": False, "audio_b64": "", "error": "Invalid response structure from Qwen-TTS"}
                
                return {"ok": False, "audio_b64": "", "error": response.message}

            # --- Branch 2: CosyVoice series ---
            if model_id.startswith("cosyvoice"):
                from dashscope.audio.tts_v2 import SpeechSynthesizer, AudioFormat, ResultCallback
                
                # Normalize voice selection
                voice_id = (voice or "").strip() or "longwan"
                if voice_id not in ["longwan", "longxiaochun", "longcheng", "longhua", "longyingtian"]:
                     voice_id = "longwan"

                if fmt == "mp3": audio_format = AudioFormat.MP3_24000HZ_MONO_256KBPS
                elif fmt == "wav": audio_format = AudioFormat.WAV_24000HZ_MONO_16BIT
                else: audio_format = AudioFormat.PCM_16000HZ_MONO_16BIT

                class _Cb(ResultCallback):
                    def __init__(self) -> None: self.err = ""
                    def on_error(self, message) -> None: self.err = str(message)

                cb = _Cb()
                synthesizer = SpeechSynthesizer(model=model_id, voice=voice_id, format=audio_format, speech_rate=speed, callback=cb)
                audio_bytes = synthesizer.call(text)
                if not audio_bytes:
                    return {"ok": False, "audio_b64": "", "error": cb.err or "CosyVoice empty audio"}
                
                audio_b64 = base64.b64encode(audio_bytes).decode()
                return {"ok": True, "audio_b64": audio_b64, "fmt": fmt, "provider": f"dashscope/{model_id}", "voice": voice_id}

            # --- Branch 3: Legacy Sambert fallback ---
            response = dashscope.SpeechSynthesizer.call(model=model_id, text=text, voice=voice, format=fmt, sample_rate=16000)
            if response.get_audio_data():
                audio_b64 = base64.b64encode(response.get_audio_data()).decode()
                return {"ok": True, "audio_b64": audio_b64, "fmt": fmt, "provider": f"dashscope/{model_id}"}
            
            return {"ok": False, "audio_b64": "", "error": "TTS failed to generate audio"}
        except Exception as exc:
            logger.error("TTS failed: %s", exc)
            return {"ok": False, "audio_b64": "", "error": str(exc)}
