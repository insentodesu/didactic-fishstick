import hashlib
import re
import secrets
from datetime import datetime, timedelta, timezone
from uuid import UUID

from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.user import PasswordResetToken, RefreshToken, User

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def normalize_phone(phone: str) -> str:
    """Canonical phone form: digits only (handles +7 vs 7 vs 8 variants)."""
    return re.sub(r"\D", "", phone)


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def create_access_token(user_id: UUID) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.jwt_access_token_expire_minutes)
    return jwt.encode(
        {"sub": str(user_id), "exp": expire, "type": "access"},
        settings.secret_key,
        algorithm=settings.jwt_algorithm,
    )


def decode_access_token(token: str) -> UUID | None:
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=[settings.jwt_algorithm])
        if payload.get("type") != "access":
            return None
        return UUID(payload["sub"])
    except (JWTError, KeyError, ValueError):
        return None


async def create_refresh_token(db: AsyncSession, user_id: UUID, user_agent: str | None, ip: str | None) -> str:
    raw_token = secrets.token_urlsafe(48)
    token_hash = hash_token(raw_token)
    expires_at = datetime.now(timezone.utc) + timedelta(days=settings.jwt_refresh_token_expire_days)

    db.add(RefreshToken(
        user_id=user_id,
        token_hash=token_hash,
        expires_at=expires_at,
        user_agent=user_agent,
        ip_address=ip,
    ))
    await db.commit()
    return raw_token


async def rotate_refresh_token(
    db: AsyncSession, raw_token: str, user_agent: str | None, ip: str | None
) -> tuple[str, UUID] | None:
    token_hash = hash_token(raw_token)
    result = await db.execute(
        select(RefreshToken).where(
            RefreshToken.token_hash == token_hash,
            RefreshToken.revoked == False,
            RefreshToken.expires_at > datetime.now(timezone.utc),
        )
    )
    record = result.scalar_one_or_none()
    if not record:
        return None

    # Инвалидируем старый токен и выдаём новый (ротация)
    record.revoked = True
    new_raw = await create_refresh_token(db, record.user_id, user_agent, ip)
    return new_raw, record.user_id


async def get_user_by_email(db: AsyncSession, email: str) -> User | None:
    result = await db.execute(select(User).where(User.email == email, User.is_active == True))
    return result.scalar_one_or_none()


async def get_user_by_phone(db: AsyncSession, phone: str) -> User | None:
    normalized = normalize_phone(phone)
    result = await db.execute(
        select(User).where(
            User.is_active == True,
            func.regexp_replace(User.phone, r"[^0-9]", "", "g") == normalized,
        )
    )
    return result.scalar_one_or_none()


async def get_user_by_id(db: AsyncSession, user_id: UUID) -> User | None:
    result = await db.execute(select(User).where(User.id == user_id, User.is_active == True))
    return result.scalar_one_or_none()


async def create_password_reset_token(db: AsyncSession, user_id: UUID) -> str:
    raw = secrets.token_urlsafe(32)
    expires_at = datetime.now(timezone.utc) + timedelta(hours=2)
    db.add(PasswordResetToken(
        user_id=user_id,
        token_hash=hash_token(raw),
        expires_at=expires_at,
    ))
    await db.commit()
    return raw


async def consume_reset_token(db: AsyncSession, raw_token: str) -> UUID | None:
    token_hash = hash_token(raw_token)
    result = await db.execute(
        select(PasswordResetToken).where(
            PasswordResetToken.token_hash == token_hash,
            PasswordResetToken.used == False,
            PasswordResetToken.expires_at > datetime.now(timezone.utc),
        )
    )
    record = result.scalar_one_or_none()
    if not record:
        return None
    record.used = True
    await db.commit()
    return record.user_id
