"""مصادقة لوحة التحكم — جلسة مستقلة عن حسابات التطبيق.

بنستخدم مكتبة bcrypt مباشرة بدل passlib: passlib بقت غير مصانة وبتنكسر
مع إصدارات bcrypt الحديثة (4.x).
"""

from __future__ import annotations

import hmac

import bcrypt
from fastapi import Request
from fastapi.responses import RedirectResponse

from app.core.config import get_settings

settings = get_settings()

SESSION_KEY = "admin_email"

# bcrypt بيتعامل مع أول 72 بايت بس — بنقصّها صراحة بدل ما المكتبة ترمي خطأ.
_MAX_PASSWORD_BYTES = 72


def _prepare(password: str) -> bytes:
    return password.encode("utf-8")[:_MAX_PASSWORD_BYTES]


def hash_password(password: str) -> str:
    return bcrypt.hashpw(_prepare(password), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, hashed: str) -> bool:
    if not hashed:
        return False
    try:
        return bcrypt.checkpw(_prepare(password), hashed.encode("utf-8"))
    except (ValueError, TypeError):
        return False


def check_admin_credentials(email: str, password: str) -> bool:
    """مقارنة البريد بوقت ثابت لتفادي تسريب المعلومات عبر توقيت الرد."""
    expected_email = settings.admin_email.strip().lower()
    given_email = email.strip().lower()

    email_ok = hmac.compare_digest(given_email, expected_email)
    password_ok = verify_password(password, settings.admin_password_hash)

    # بننفّذ التحققين دايمًا عشان الوقت ما يفرقش حسب اللي غلط.
    return email_ok and password_ok


def is_logged_in(request: Request) -> bool:
    return bool(request.session.get(SESSION_KEY))


def login_redirect() -> RedirectResponse:
    return RedirectResponse(url="/admin/login", status_code=303)
