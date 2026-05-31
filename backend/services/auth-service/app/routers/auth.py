from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.models.user import User
import re

from app.schemas.auth import (
    ChangePasswordRequest,
    ForgotPasswordRequest,
    LoginRequest,
    PhoneLoginRequest,
    PhoneRegisterRequest,
    RefreshRequest,
    RegisterRequest,
    ResetPasswordRequest,
    TokenResponse,
)
from app.services.auth_service import (
    consume_reset_token,
    create_access_token,
    create_password_reset_token,
    create_refresh_token,
    get_user_by_email,
    get_user_by_phone,
    hash_password,
    rotate_refresh_token,
    verify_password,
)
from app.services.deps import get_current_user

router = APIRouter(prefix="/auth", tags=["Авторизация"])


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def register(body: RegisterRequest, request: Request, db: AsyncSession = Depends(get_db)):
    existing = await get_user_by_email(db, body.email)
    if existing:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email уже зарегистрирован")

    user = User(
        email=body.email,
        name=body.name,
        password_hash=hash_password(body.password),
    )
    db.add(user)
    await db.flush()

    access = create_access_token(user.id)
    refresh = await create_refresh_token(
        db, user.id,
        request.headers.get("user-agent"),
        request.client.host if request.client else None,
    )
    await db.commit()
    return TokenResponse(access_token=access, refresh_token=refresh)


@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest, request: Request, db: AsyncSession = Depends(get_db)):
    user = await get_user_by_email(db, body.email)
    if not user or not user.password_hash or not verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Неверный email или пароль")

    access = create_access_token(user.id)
    refresh = await create_refresh_token(
        db, user.id,
        request.headers.get("user-agent"),
        request.client.host if request.client else None,
    )
    return TokenResponse(access_token=access, refresh_token=refresh)


@router.post("/refresh", response_model=TokenResponse)
async def refresh_tokens(body: RefreshRequest, request: Request, db: AsyncSession = Depends(get_db)):
    result = await rotate_refresh_token(
        db, body.refresh_token,
        request.headers.get("user-agent"),
        request.client.host if request.client else None,
    )
    if not result:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Токен недействителен или истёк")

    new_refresh, user_id = result
    access = create_access_token(user_id)
    return TokenResponse(access_token=access, refresh_token=new_refresh)


@router.post("/register-phone", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def register_phone(body: PhoneRegisterRequest, request: Request, db: AsyncSession = Depends(get_db)):
    """Регистрация по номеру телефона + пароль."""
    phone = re.sub(r"[^\d+]", "", body.phone)
    existing = await get_user_by_phone(db, phone)
    if existing:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Номер телефона уже зарегистрирован")

    fake_email = f"phone_{phone.lstrip('+').replace(' ', '')}@finpet.local"
    user = User(
        email=fake_email,
        phone=phone,
        name=body.name,
        password_hash=hash_password(body.password),
    )
    db.add(user)
    await db.flush()

    access = create_access_token(user.id)
    refresh = await create_refresh_token(
        db, user.id,
        request.headers.get("user-agent"),
        request.client.host if request.client else None,
    )
    await db.commit()
    return TokenResponse(access_token=access, refresh_token=refresh)


@router.post("/login-phone", response_model=TokenResponse)
async def login_phone(body: PhoneLoginRequest, request: Request, db: AsyncSession = Depends(get_db)):
    """Вход по номеру телефона + пароль."""
    phone = re.sub(r"[^\d+]", "", body.phone)
    user = await get_user_by_phone(db, phone)
    if not user or not user.password_hash or not verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Неверный номер или пароль")

    access = create_access_token(user.id)
    refresh = await create_refresh_token(
        db, user.id,
        request.headers.get("user-agent"),
        request.client.host if request.client else None,
    )
    return TokenResponse(access_token=access, refresh_token=refresh)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(body: RefreshRequest, db: AsyncSession = Depends(get_db)):
    # Инвалидируем refresh-токен; access-токен истечёт сам по TTL
    from app.services.auth_service import hash_token
    from app.models.user import RefreshToken
    from sqlalchemy import update

    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.token_hash == hash_token(body.refresh_token))
        .values(revoked=True)
    )
    await db.commit()


@router.post("/change-password", status_code=status.HTTP_204_NO_CONTENT)
async def change_password(
    body: ChangePasswordRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if not current_user.password_hash or not verify_password(body.old_password, current_user.password_hash):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Неверный текущий пароль")
    current_user.password_hash = hash_password(body.new_password)
    await db.commit()


@router.post("/forgot-password", status_code=status.HTTP_204_NO_CONTENT)
async def forgot_password(body: ForgotPasswordRequest, db: AsyncSession = Depends(get_db)):
    user = await get_user_by_email(db, body.email)
    if user:
        token = await create_password_reset_token(db, user.id)
        # TODO: отправка письма через notification-service
        # await notify_client.send_reset_email(user.email, token)
    # Всегда отвечаем 204 — не раскрываем наличие email в базе


@router.post("/reset-password", status_code=status.HTTP_204_NO_CONTENT)
async def reset_password(body: ResetPasswordRequest, db: AsyncSession = Depends(get_db)):
    user_id = await consume_reset_token(db, body.token)
    if not user_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Токен недействителен или истёк")

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")

    user.password_hash = hash_password(body.new_password)
    await db.commit()


@router.get("/gmail")
async def gmail_oauth_redirect():
    """Редирект на Google OAuth2 для доступа к почте (сканирование подписок)."""
    from urllib.parse import urlencode
    from app.config import settings

    params = {
        "client_id": settings.gmail_client_id,
        "redirect_uri": settings.gmail_redirect_uri,
        "response_type": "code",
        "scope": "https://www.googleapis.com/auth/gmail.readonly",
        "access_type": "offline",
        "prompt": "consent",
    }
    return {"redirect_url": f"https://accounts.google.com/o/oauth2/v2/auth?{urlencode(params)}"}


@router.get("/gmail/callback")
async def gmail_oauth_callback(
    code: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Обрабатывает колбэк от Google, сохраняет токены для сканирования Gmail."""
    import httpx
    from app.config import settings
    from app.models.user import RefreshToken  # переиспользуем структуру — здесь нужна отдельная таблица oauth_accounts

    async with httpx.AsyncClient() as client:
        resp = await client.post("https://oauth2.googleapis.com/token", data={
            "code": code,
            "client_id": settings.gmail_client_id,
            "client_secret": settings.gmail_client_secret,
            "redirect_uri": settings.gmail_redirect_uri,
            "grant_type": "authorization_code",
        })
        tokens = resp.json()

    # Сохраняем в oauth_accounts
    from sqlalchemy.dialects.postgresql import insert as pg_insert
    from datetime import datetime, timezone, timedelta

    await db.execute(
        pg_insert(__import__("sqlalchemy", fromlist=["Table"]).Table(
            "oauth_accounts", __import__("sqlalchemy", fromlist=["MetaData"]).MetaData(), schema="auth", autoload_with=None
        ))
    )
    # TODO: полная реализация через OAuthAccount model
    return {"status": "ok", "scopes": tokens.get("scope", "").split()}
