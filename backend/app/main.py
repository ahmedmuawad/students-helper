"""نقطة تشغيل السيرفر."""

from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from starlette.middleware.sessions import SessionMiddleware

from app.api import admin, mobile, sync
from app.core.config import get_settings
from app.core.database import Base, engine
from app.core.schema_sync import sync_schema

# استيراد الموديلات مهم عشان SQLAlchemy يعرف الجداول قبل create_all
from app.models import settings_store  # noqa: F401
import app.models  # noqa: F401

settings = get_settings()

app = FastAPI(
    title=settings.app_name,
    version="1.0.0",
    docs_url="/api/docs",
    openapi_url="/api/openapi.json",
)

app.add_middleware(
    SessionMiddleware,
    secret_key=settings.admin_session_secret,
    same_site="lax",
    https_only=settings.environment == "production",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(admin.router)
app.include_router(mobile.router)
app.include_router(sync.router)

# ملفات الكتب — في الإنتاج nginx بيخدمها مباشرة وأسرع.
media_path = Path(settings.media_root)
media_path.mkdir(parents=True, exist_ok=True)
app.mount(
    settings.media_url_prefix,
    StaticFiles(directory=str(media_path)),
    name="media",
)


@app.on_event("startup")
def on_startup() -> None:
    """ينشئ الجداول لو مش موجودة ويظبّط القديمة على الموديلات."""
    Base.metadata.create_all(bind=engine)
    for change in sync_schema(engine):
        print(f"[schema] {change}", flush=True)


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "app": settings.app_name}


@app.get("/")
async def root() -> RedirectResponse:
    return RedirectResponse(url="/admin")
