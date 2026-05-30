"""
AIESA API клиент.
Аутентификация: HMAC-SHA256 подпись через заголовки X-Public-Key, X-Timestamp, X-Signature.
Подпись: HMAC-SHA256(f"{public_key}\n{timestamp}", secret_key) в hex.
"""

import hashlib
import hmac
import time
import json
from typing import AsyncGenerator

import httpx

from app.config import settings


def _make_signature(timestamp: int) -> str:
    message = f"{settings.aiesa_public_key}\n{timestamp}".encode()
    return hmac.new(
        settings.aiesa_secret_key.encode(),
        message,
        hashlib.sha256,
    ).hexdigest()


def _auth_headers() -> dict:
    ts = int(time.time())
    return {
        "X-Public-Key": settings.aiesa_public_key,
        "X-Timestamp": str(ts),
        "X-Signature": _make_signature(ts),
        "Content-Type": "application/json",
    }


async def chat_complete(
    messages: list[dict],
    model: str | None = None,
    temperature: float = 0.7,
    max_tokens: int = 2048,
) -> str:
    """Отправляет запрос и возвращает полный ответ (собирает SSE-поток)."""
    payload = {
        "model": model or settings.aiesa_model,
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
    }

    async with httpx.AsyncClient(timeout=settings.aiesa_timeout) as client:
        async with client.stream(
            "POST",
            f"{settings.aiesa_base_url}/chat/completions",
            headers=_auth_headers(),
            json=payload,
        ) as resp:
            resp.raise_for_status()
            result_parts = []
            async for line in resp.aiter_lines():
                if not line.startswith("data: "):
                    continue
                data = line[6:]
                if data.strip() == "[DONE]":
                    break
                try:
                    chunk = json.loads(data)
                    delta = chunk["choices"][0]["delta"].get("content", "")
                    if delta:
                        result_parts.append(delta)
                except (json.JSONDecodeError, KeyError, IndexError):
                    continue

    return "".join(result_parts).strip()


async def chat_complete_stream(
    messages: list[dict],
    model: str | None = None,
    temperature: float = 0.7,
    max_tokens: int = 2048,
) -> AsyncGenerator[str, None]:
    """Возвращает генератор токенов для стриминга на фронт."""
    payload = {
        "model": model or settings.aiesa_model,
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
    }

    async with httpx.AsyncClient(timeout=settings.aiesa_timeout) as client:
        async with client.stream(
            "POST",
            f"{settings.aiesa_base_url}/chat/completions",
            headers=_auth_headers(),
            json=payload,
        ) as resp:
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                if not line.startswith("data: "):
                    continue
                data = line[6:]
                if data.strip() == "[DONE]":
                    return
                try:
                    chunk = json.loads(data)
                    delta = chunk["choices"][0]["delta"].get("content", "")
                    if delta:
                        yield delta
                except (json.JSONDecodeError, KeyError, IndexError):
                    continue
