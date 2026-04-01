from __future__ import annotations

import base64
import io
import logging
import wave
from typing import Any, Literal

from openai import OpenAI

from backend.config import Settings

logger = logging.getLogger(__name__)


class VoiceService:
    """DashScope voice service for ASR, Omni, and TTS flows."""

    _OMNI_AUDIO_VOICE_CANDIDATES = ("Chelsie", "Ethan")

    def __init__(self, settings: Settings, device_service: Any | None = None) -> None:
        self._settings = settings
        self._device_service = device_service

    @property
    def _api_key(self) -> str:
        return self._settings.dashscope_api_key.strip()

    @property
    def _configured(self) -> bool:
        return bool(self._api_key)

    @property
    def _compatible_base_url(self) -> str:
        return self._settings.qwen_api_base.strip() or "https://dashscope.aliyuncs.com/compatible-mode/v1"

    def _build_compatible_client(self) -> OpenAI:
        return OpenAI(
            api_key=self._api_key,
            base_url=self._compatible_base_url,
        )

    @staticmethod
    def _normalize_audio_format(fmt: str) -> str:
        normalized = (fmt or "wav").strip().lower()
        if normalized in {"wav", "wave"}:
            return "wav"
        if normalized in {"mp3", "mpeg"}:
            return "mp3"
        if normalized in {"m4a", "aac", "mp4"}:
            return "aac"
        if normalized in {"amr", "3gp", "3gpp"}:
            return normalized
        return "wav"

    @staticmethod
    def _extract_text_delta(content: Any) -> str:
        if content is None:
            return ""
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            parts: list[str] = []
            for item in content:
                if isinstance(item, str):
                    parts.append(item)
                    continue
                if not isinstance(item, dict):
                    continue
                text_value = item.get("text")
                if isinstance(text_value, str):
                    parts.append(text_value)
                    continue
                nested_text = item.get("content")
                if isinstance(nested_text, str):
                    parts.append(nested_text)
            return "".join(parts)
        return str(content)

    @staticmethod
    def _extract_audio_delta(audio: Any) -> str:
        if audio is None:
            return ""
        if isinstance(audio, dict):
            return str(audio.get("data") or "")
        data = getattr(audio, "data", None)
        if isinstance(data, str):
            return data
        if hasattr(audio, "get"):
            try:
                return str(audio.get("data") or "")
            except Exception:
                return ""
        return ""

    @staticmethod
    def _pcm_b64_to_wav_b64(audio_b64: str, *, sample_rate: int = 24000) -> str:
        if not audio_b64:
            return ""

        pcm_bytes = base64.b64decode(audio_b64)
        buffer = io.BytesIO()
        with wave.open(buffer, "wb") as wav_file:
            wav_file.setnchannels(1)
            wav_file.setsampwidth(2)
            wav_file.setframerate(sample_rate)
            wav_file.writeframes(pcm_bytes)
        return base64.b64encode(buffer.getvalue()).decode("ascii")

    def _build_health_context(self, device_mac: str | None) -> str:
        if not device_mac or self._device_service is None:
            return ""

        try:
            from backend.dependencies import get_display_latest_sample

            normalized_mac = device_mac.strip().upper()
            device = None
            if hasattr(self._device_service, "get_device"):
                device = self._device_service.get_device(normalized_mac)
            ingest_mode = getattr(device, "ingest_mode", None)
            sample = get_display_latest_sample(normalized_mac, ingest_mode)
            if sample is None:
                return ""

            blood_pressure = sample.blood_pressure or "--"
            steps = sample.steps if sample.steps is not None else "--"
            score = sample.health_score if sample.health_score is not None else "--"
            return (
                "\n当前可用的健康监测数据："
                f"心率 {sample.heart_rate} 次/分，"
                f"血氧 {sample.blood_oxygen}%，"
                f"体温 {sample.temperature:.1f} 摄氏度，"
                f"血压 {blood_pressure}，"
                f"步数 {steps}，"
                f"健康分 {score}。"
            )
        except Exception as exc:
            logger.debug("Failed to build health context for omni chat: %s", exc)
            return ""

    @staticmethod
    def _build_elder_voice_style_prompt(*, has_health_context: bool) -> str:
        prompt = (
            "You are the elder-side health companion assistant in a mobile health app. "
            "First understand the user's speech accurately, then answer based only on the provided monitoring data. "
            "Reply in Simplified Chinese. "
            "Sound warm, gentle, natural, and reassuring, like a patient family health assistant. "
            "Do not sound blunt or like you are reading a report. "
            "Start with a short overall impression, then explain the most important point in plain language, "
            "and end with one simple next-step suggestion. "
            "When the user asks about today's condition, prefer realistic high-level descriptions such as "
            "'overall stable', 'a small fluctuation', or 'worth watching a bit more closely'. "
            "You may use natural phrases like '目前看起来', '整体来说', or '从这会儿的监测看'. "
            "Never invent measurements, symptoms, diagnoses, examinations, events, or abnormalities that were not provided. "
        )
        if has_health_context:
            prompt += (
                "If monitoring data is available, weave it into a natural spoken explanation instead of listing raw numbers mechanically. "
            )
        else:
            prompt += (
                "If monitoring data is missing or limited, clearly say the current monitoring data is limited, "
                "and only give cautious, non-diagnostic suggestions. "
            )
        prompt += "Keep the answer to 2 to 4 sentences so it is suitable for direct voice playback."
        return prompt

    def transcribe(self, audio_bytes: bytes, *, fmt: str = "wav") -> dict[str, object]:
        """Call DashScope Paraformer ASR to transcribe audio bytes."""
        if not self._configured:
            return {"ok": False, "text": "", "error": "DASHSCOPE_API_KEY not configured"}

        model_id = self._settings.qwen_asr_model_id.strip().lower()
        try:
            import dashscope
            import os
            import tempfile

            dashscope.api_key = self._api_key

            tmp = tempfile.NamedTemporaryFile(delete=False, suffix=f".{fmt}")
            try:
                tmp.write(audio_bytes)
                tmp.close()
                from dashscope.audio.asr import Recognition, RecognitionCallback

                recognizer = Recognition(
                    model=model_id,
                    callback=RecognitionCallback(),
                    format=fmt,
                    sample_rate=16000,
                )
                result = recognizer.call(tmp.name)
                if getattr(result, "status_code", None) == 200:
                    sentences = result.get_sentence()
                    text = " ".join(
                        sentence.get("text", "")
                        for sentence in (sentences or [])
                        if isinstance(sentence, dict)
                    ).strip()
                    return {"ok": True, "text": text, "provider": f"dashscope/{model_id}"}
                return {"ok": False, "text": "", "error": getattr(result, "message", "ASR failed")}
            finally:
                if os.path.exists(tmp.name):
                    os.unlink(tmp.name)
        except Exception as exc:
            logger.warning("ASR failed: %s", exc)
            return {"ok": False, "text": "", "error": str(exc)}

    def omni_chat(
        self,
        audio_bytes: bytes,
        *,
        prompt: str = "请先理解我的语音，再结合已有的健康监测数据，用自然、温和、好懂的话给出简短回答。",
        fmt: str = "wav",
        device_mac: str | None = None,
        role: str = "elder",
    ) -> dict[str, object]:
        """Call the configured DashScope omni model through the OpenAI-compatible API."""
        if not self._configured:
            return {"ok": False, "text": "", "error": "DASHSCOPE_API_KEY not configured"}

        model_id = self._settings.qwen_omni_model_id
        input_format = self._normalize_audio_format(fmt)
        normalized_role = (role or "elder").strip().lower()
        health_context = self._build_health_context(device_mac)
        prompt_text = (prompt or "").strip() or "请先理解我的语音，再结合已有的健康监测数据，用自然、温和、好懂的话给出简短回答。"
        system_prompt = (
            self._build_elder_voice_style_prompt(has_health_context=bool(health_context))
            if normalized_role == "elder"
            else (
                "You are a health monitoring assistant. "
                "Reply in Simplified Chinese. "
                "Base your answer only on the provided data and context. "
                "Be clear, concise, and easy to understand. "
                "Do not invent unavailable facts."
            )
        )
        if health_context:
            system_prompt += health_context

        audio_input_b64 = base64.b64encode(audio_bytes).decode("ascii")
        messages = [
            {"role": "system", "content": system_prompt},
            {
                "role": "user",
                "content": [
                    {
                        "type": "input_audio",
                        "input_audio": {
                            "data": f"data:;base64,{audio_input_b64}",
                            "format": input_format,
                        },
                    },
                    {"type": "text", "text": prompt_text},
                ],
            },
        ]

        try:
            client = self._build_compatible_client()
            request_kwargs: dict[str, object] = {
                "model": model_id,
                "messages": messages,
                "modalities": ["text", "audio"] if normalized_role == "elder" else ["text"],
                "stream": True,
                "stream_options": {"include_usage": True},
            }
            selected_voice: str | None = None
            if normalized_role == "elder":
                completion = None
                last_voice_error: Exception | None = None
                for voice_name in self._OMNI_AUDIO_VOICE_CANDIDATES:
                    try:
                        request_kwargs["audio"] = {
                            "voice": voice_name,
                            "format": "wav",
                        }
                        completion = client.chat.completions.create(**request_kwargs)
                        selected_voice = voice_name
                        break
                    except Exception as exc:
                        message = str(exc).lower()
                        if "parameters.audio.voice" not in message:
                            raise
                        last_voice_error = exc
                if completion is None:
                    if last_voice_error is not None:
                        raise last_voice_error
                    raise RuntimeError("Failed to select a supported omni audio voice")
            else:
                completion = client.chat.completions.create(**request_kwargs)

            text_parts: list[str] = []
            audio_pcm_parts: list[str] = []

            for chunk in completion:
                choices = getattr(chunk, "choices", None) or []
                if not choices:
                    continue

                delta = getattr(choices[0], "delta", None)
                if delta is None:
                    continue

                text_delta = self._extract_text_delta(getattr(delta, "content", None))
                if text_delta:
                    text_parts.append(text_delta)

                audio_delta = self._extract_audio_delta(getattr(delta, "audio", None))
                if audio_delta:
                    audio_pcm_parts.append(audio_delta)

            answer_text = "".join(text_parts).strip()
            audio_pcm_b64 = "".join(audio_pcm_parts)
            audio_wav_b64 = self._pcm_b64_to_wav_b64(audio_pcm_b64) if audio_pcm_b64 else ""

            return {
                "ok": True,
                "text": answer_text,
                "answer": answer_text,
                "audio_b64": audio_wav_b64,
                "audio_pcm_b64": audio_pcm_b64,
                "audio_url": f"data:audio/wav;base64,{audio_wav_b64}" if audio_wav_b64 else "",
                "audio_sample_rate": 24000 if audio_wav_b64 else None,
                "fmt": "wav" if audio_wav_b64 else None,
                "voice": selected_voice if audio_wav_b64 else None,
                "provider": f"dashscope-compatible/{model_id}",
                "model": model_id,
            }
        except Exception as exc:
            logger.error("Omni chat failed: %s", exc)
            message = str(exc)
            lower_message = message.lower()
            if "access_denied" in lower_message or "access denied" in lower_message:
                message = f"当前 DashScope 账号尚未开通 {model_id} 调用权限，请先在阿里云百炼控制台开通模型后再试。"
            return {"ok": False, "text": "", "error": message}

    def synthesize(
        self,
        text: str,
        *,
        voice: str = "longxiaochun",
        speed: float = 1.0,
        fmt: Literal["mp3", "wav", "pcm"] = "mp3",
        workspace: str | None = None,
    ) -> dict[str, object]:
        """Call DashScope TTS and return audio data."""
        if not self._configured:
            return {"ok": False, "audio_b64": "", "error": "DASHSCOPE_API_KEY not configured"}

        if not text.strip():
            return {"ok": False, "audio_b64": "", "error": "empty text"}

        model_id = self._settings.qwen_tts_model_id.strip().lower()
        try:
            import dashscope

            dashscope.api_key = self._api_key

            if "qwen-tts" in model_id or "qwen3-tts" in model_id:
                voice_map = {
                    "longxiaochun": "Cherry",
                    "longwan": "Cherry",
                    "longcheng": "Genny",
                    "longhua": "Genny",
                    "longyingtian": "Genny",
                }
                target_voice = voice_map.get(voice.lower(), "Cherry")

                response = dashscope.MultiModalConversation.call(
                    model=model_id,
                    text=text,
                    voice=target_voice,
                    language_type="Chinese",
                    parameters={
                        "format": fmt,
                        "sample_rate": 16000,
                    },
                    stream=False,
                )

                if response.status_code == 200:
                    output = getattr(response, "output", None)
                    if output and hasattr(output, "audio") and hasattr(output.audio, "data"):
                        audio_b64 = output.audio.data
                        if not audio_b64:
                            return {
                                "ok": False,
                                "audio_b64": "",
                                "error": "Model returned empty audio data",
                            }
                        return {
                            "ok": True,
                            "audio_b64": audio_b64,
                            "fmt": fmt,
                            "provider": f"dashscope/{model_id}",
                            "voice": target_voice,
                        }
                    return {
                        "ok": False,
                        "audio_b64": "",
                        "error": "Invalid response structure from Qwen-TTS",
                    }

                return {"ok": False, "audio_b64": "", "error": response.message}

            if model_id.startswith("cosyvoice"):
                from dashscope.audio.tts_v2 import AudioFormat, ResultCallback, SpeechSynthesizer

                voice_id = (voice or "").strip() or "longwan"
                if voice_id not in ["longwan", "longxiaochun", "longcheng", "longhua", "longyingtian"]:
                    voice_id = "longwan"

                if fmt == "mp3":
                    audio_format = AudioFormat.MP3_24000HZ_MONO_256KBPS
                elif fmt == "wav":
                    audio_format = AudioFormat.WAV_24000HZ_MONO_16BIT
                else:
                    audio_format = AudioFormat.PCM_16000HZ_MONO_16BIT

                class _Callback(ResultCallback):
                    def __init__(self) -> None:
                        self.err = ""

                    def on_error(self, message) -> None:
                        self.err = str(message)

                callback = _Callback()
                synthesizer = SpeechSynthesizer(
                    model=model_id,
                    voice=voice_id,
                    format=audio_format,
                    speech_rate=speed,
                    callback=callback,
                )
                audio_bytes = synthesizer.call(text)
                if not audio_bytes:
                    return {"ok": False, "audio_b64": "", "error": callback.err or "CosyVoice empty audio"}

                audio_b64 = base64.b64encode(audio_bytes).decode("ascii")
                return {
                    "ok": True,
                    "audio_b64": audio_b64,
                    "fmt": fmt,
                    "provider": f"dashscope/{model_id}",
                    "voice": voice_id,
                }

            response = dashscope.SpeechSynthesizer.call(
                model=model_id,
                text=text,
                voice=voice,
                format=fmt,
                sample_rate=16000,
            )
            if response.get_audio_data():
                audio_b64 = base64.b64encode(response.get_audio_data()).decode("ascii")
                return {"ok": True, "audio_b64": audio_b64, "fmt": fmt, "provider": f"dashscope/{model_id}"}

            return {"ok": False, "audio_b64": "", "error": "TTS failed to generate audio"}
        except Exception as exc:
            logger.error("TTS failed: %s", exc)
            return {"ok": False, "audio_b64": "", "error": str(exc)}
