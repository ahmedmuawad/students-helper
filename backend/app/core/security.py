"""التحقق من هوية المستخدم عبر توكن Firebase.

Firebase مسؤول عن تسجيل الدخول فقط. السيرفر بيتحقق من التوكن بنفسه
باستخدام مفاتيح جوجل العامة، فمحدش يقدر ينتحل هوية مستخدم تاني.
"""

from __future__ import annotations

import time
from datetime import datetime, timezone

import httpx
from fastapi import Depends, Header, HTTPException, status
from jose import jwt
from jose.exceptions import JWTError
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.database import get_db
from app.models import Account, AccountRole

settings = get_settings()

_GOOGLE_CERTS_URL = (
    "https://www.googleapis.com/robot/v1/metadata/x509/"
    "securetoken@system.gserviceaccount.com"
)

# كاش للمفاتيح العامة — جوجل بتغيّرها كل فترة، فبنعيد تحميلها كل ساعة.
_certs_cache: dict[str, str] = {}
_certs_fetched_at: float = 0.0
_CERTS_TTL_SECONDS = 3600


async def _google_public_keys() -> dict[str, str]:
    global _certs_cache, _certs_fetched_at

    if _certs_cache and (time.time() - _certs_fetched_at) < _CERTS_TTL_SECONDS:
        return _certs_cache

    async with httpx.AsyncClient(timeout=10) as client:
        response = await client.get(_GOOGLE_CERTS_URL)
        response.raise_for_status()
        _certs_cache = response.json()
        _certs_fetched_at = time.time()

    return _certs_cache


async def verify_firebase_token(token: str) -> dict:
    """يفك التوكن ويتأكد من توقيعه ومُصدِره وصلاحيته."""

    if not settings.firebase_project_id:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="firebase_project_id غير مضبوط على السيرفر",
        )

    try:
        header = jwt.get_unverified_header(token)
    except JWTError as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="توكن غير صالح",
        ) from error

    key_id = header.get("kid")
    certs = await _google_public_keys()
    certificate = certs.get(key_id)
    if certificate is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="مفتاح التوقيع غير معروف",
        )

    project = settings.firebase_project_id
    try:
        claims = jwt.decode(
            token,
            certificate,
            algorithms=["RS256"],
            audience=project,
            issuer=f"https://securetoken.google.com/{project}",
        )
    except JWTError as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="التوكن منتهي أو غير صالح",
        ) from error

    if not claims.get("sub"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="التوكن بدون معرّف مستخدم",
        )

    return claims


async def current_account(
    authorization: str = Header(default=""),
    db: Session = Depends(get_db),
) -> Account:
    """يرجّع حساب المستخدم الحالي، وينشئه أول مرة يدخل فيها."""

    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="مطلوب تسجيل دخول",
        )

    token = authorization.removeprefix("Bearer ").strip()

    # في التطوير المحلي فقط: توكن مبسّط عشان نجرّب من غير Firebase.
    if settings.allow_dev_tokens and token.startswith("dev:"):
        uid = token.removeprefix("dev:").strip()
        claims = {"sub": uid, "name": uid, "email": f"{uid}@dev.local"}
    else:
        claims = await verify_firebase_token(token)

    uid = claims["sub"]
    account = db.query(Account).filter(Account.firebase_uid == uid).one_or_none()

    if account is None:
        account = Account(
            firebase_uid=uid,
            display_name=claims.get("name", ""),
            email=claims.get("email", ""),
            phone=claims.get("phone_number", ""),
            role=AccountRole.student,
        )
        db.add(account)

    account.last_seen_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(account)
    return account


def require_role(*roles: AccountRole):
    """حارس يمنع الوصول لو دور المستخدم مش ضمن الأدوار المسموحة."""

    async def guard(account: Account = Depends(current_account)) -> Account:
        if account.role not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="ليس لديك صلاحية لهذا الإجراء",
            )
        return account

    return guard
