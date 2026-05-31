from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

from app.config import settings

bearer = HTTPBearer(auto_error=False)

ANONYMOUS_USER_ID = "00000000-0000-0000-0000-000000000000"


def get_current_user_id(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)) -> str:
    if credentials is None or not credentials.credentials or credentials.credentials.lower() in ("null", "undefined"):
        return ANONYMOUS_USER_ID
    try:
        payload = jwt.decode(credentials.credentials, settings.secret_key, algorithms=[settings.jwt_algorithm])
        if payload.get("type") != "access":
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Недействительный токен")
        return payload["sub"]
    except (JWTError, KeyError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Недействительный токен")
