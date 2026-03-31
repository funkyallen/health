from __future__ import annotations

import base64
import logging
from typing import Literal

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse

from backend.config import get_settings
from backend.services.voice_service import VoiceService

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/omni", tags=["omni"])

_settings = get_settings()
_voice_service = VoiceService(_settings)

@router.post("/analyze")
async def omni_analyze_voice(
    file: UploadFile = File(...),
    prompt: str = Form("请结合老人的身体状况回答。"),
    role: str = Form("elder"),
    device_mac: str | None = Form(None),
) -> dict:
    """Accept audio file and optional prompt, return Qwen-Omni multimodal answer."""
    content_type = (file.content_type or "").split(";")[0].strip()
    allowed = {"audio/wav", "audio/wave", "audio/webm", "audio/ogg", "audio/mpeg", "audio/mp3", "application/octet-stream"}
    
    if content_type not in allowed and not (file.filename or "").lower().endswith((".wav", ".mp3", ".m4a", ".webm")):
         raise HTTPException(status_code=400, detail=f"Unsupported audio format: {content_type}")

    audio_bytes = await file.read()
    if len(audio_bytes) < 100:
        raise HTTPException(status_code=400, detail="Audio file too small")

    fmt = "wav"
    name = (file.filename or "").lower()
    if "mp3" in name or "mpeg" in content_type:
        fmt = "mp3"
    elif "webm" in name:
        fmt = "webm"

    # Call VoiceService omni_chat
    # Note: In a full implementation, we might want to inject device context (samples) 
    # into the prompt before sending it to Omni.
    result = _voice_service.omni_chat(audio_bytes, prompt=prompt, fmt=fmt)
    
    if not result.get("ok"):
        raise HTTPException(status_code=500, detail=result.get("error") or "Omni analysis failed")
    
    return result

@router.get("/status")
async def omni_status() -> dict:
    return {
        "configured": bool(_settings.dashscope_api_key.strip() and _settings.qwen_omni_model_id),
        "model": _settings.qwen_omni_model_id,
        "supported_modalities": ["audio", "text"]
    }
