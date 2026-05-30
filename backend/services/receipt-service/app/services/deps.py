from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from app.config import settings

# auto_error=False — не бросаем 403 если токена нет; возвращаем anonymous
bearer = HTTPBearer(auto_error=False)


def get_current_user_id(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
) -> str:
    if credentials is None:
        return "00000000-0000-0000-0000-000000000000"
    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.secret_key,
            algorithms=[settings.jwt_algorithm],
        )
        if payload.get("type") != "access":
            raise HTTPException(status_code=401, detail="Недействительный токен")
        return payload["sub"]
    except (JWTError, KeyError):
        raise HTTPException(status_code=401, detail="Недействительный токен")
