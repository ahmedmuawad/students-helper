"""حفظ ملفات الكتب على القرص واستخراج بياناتها."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path

import fitz  # PyMuPDF

from app.core.config import get_settings

settings = get_settings()

# امتدادات مسموح بيها فقط — بنمنع رفع أي حاجة تانية.
ALLOWED_EXTENSIONS = {".pdf"}


def _safe_name(name: str) -> str:
    """يشيل أي مسارات أو رموز خطرة من اسم الملف المرفوع."""
    stem = Path(name).name
    cleaned = re.sub(r"[^A-Za-z0-9._\-]", "_", stem)
    return cleaned[:120] or "file"


def media_root() -> Path:
    root = Path(settings.media_root).resolve()
    root.mkdir(parents=True, exist_ok=True)
    return root


def save_book_file(
    content: bytes,
    original_name: str,
    curriculum_id: int,
    grade_level: int,
    subject_slug: str,
) -> dict:
    """يحفظ ملف الكتاب ويرجّع بياناته (المسار، الحجم، عدد الصفحات، البصمة)."""

    extension = Path(original_name).suffix.lower()
    if extension not in ALLOWED_EXTENSIONS:
        raise ValueError("مسموح برفع ملفات PDF فقط")

    if len(content) > settings.max_upload_bytes:
        raise ValueError(f"الملف أكبر من الحد المسموح ({settings.max_upload_mb} ميجا)")

    checksum = hashlib.sha256(content).hexdigest()

    # مسار منظّم يسهّل النسخ الاحتياطي والصيانة
    relative_dir = Path(
        f"books/c{curriculum_id}/g{grade_level}/{_safe_name(subject_slug)}"
    )
    target_dir = media_root() / relative_dir
    target_dir.mkdir(parents=True, exist_ok=True)

    filename = f"{checksum[:16]}{extension}"
    target = target_dir / filename
    if not target.exists():
        target.write_bytes(content)

    page_count = 0
    try:
        with fitz.open(stream=content, filetype="pdf") as document:
            page_count = document.page_count
    except Exception:
        # ملف تالف أو محمي — بنحفظه بس من غير عدد صفحات.
        page_count = 0

    return {
        "file_path": str(relative_dir / filename),
        "file_size": len(content),
        "page_count": page_count,
        "checksum": checksum,
    }


def extract_table_of_contents(content: bytes) -> list[dict]:
    """يستخرج فهرس المحتويات المدمج في ملف الـ PDF لو موجود.

    ده بيوفّر إدخال أسماء الدروس يدويًا لما الملف يكون متولّد رقميًا
    وفيه فهرس (bookmarks).
    """

    entries: list[dict] = []
    try:
        with fitz.open(stream=content, filetype="pdf") as document:
            for level, title, page in document.get_toc():
                cleaned = title.strip()
                if cleaned:
                    entries.append(
                        {"level": level, "title": cleaned, "page": page}
                    )
    except Exception:
        return []
    return entries


def delete_book_file(relative_path: str) -> None:
    """يحذف ملف من التخزين — بيتجاهل لو مش موجود."""
    if not relative_path:
        return
    target = (media_root() / relative_path).resolve()
    # حماية: لازم الملف يكون جوّه مجلد الميديا
    if not str(target).startswith(str(media_root())):
        return
    target.unlink(missing_ok=True)
