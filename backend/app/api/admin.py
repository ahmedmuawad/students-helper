"""مسارات لوحة التحكم (واجهة ويب للأدمن)."""

from __future__ import annotations

from fastapi import APIRouter, Depends, File, Form, Request, UploadFile
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload

from app.core import admin_auth, media
from app.core.plans import PLAN_LIMITS, PLAN_PRICES
from app.core.config import get_settings
from app.core.database import get_db
from app.models import (
    Account,
    AccountRole,
    Book,
    BookKind,
    Curriculum,
    EducationStage,
    Grade,
    GuardianLink,
    Lesson,
    LinkStatus,
    PlanTier,
    Subject,
    Subscription,
    Unit,
)
from app.models.settings_store import (
    SETTING_DEFINITIONS,
    IntegrationSetting,
    definitions_by_group,
)

router = APIRouter(prefix="/admin", tags=["admin"])
settings = get_settings()
templates = Jinja2Templates(directory="app/templates")


# --------------------------------------------------------------------------
# مساعدات العرض
# --------------------------------------------------------------------------

KIND_LABELS = {
    BookKind.textbook: "كتاب الوزارة",
    BookKind.workbook: "كتاب الأنشطة",
    BookKind.booklet: "ملزمة",
    BookKind.revision: "مراجعة نهائية",
    BookKind.exam: "نماذج امتحانات",
    BookKind.teacher_guide: "دليل المعلم",
    BookKind.other: "أخرى",
}

ROLE_LABELS = {
    AccountRole.student: "طالب",
    AccountRole.guardian: "ولي أمر",
    AccountRole.teacher: "مدرس",
    AccountRole.admin: "أدمن",
}

TIER_LABELS = {"free": "مجاني", "plus": "بلس", "pro": "برو"}

LANGUAGE_LABELS = {"arabic": "عربي", "languages": "لغات", "international": "دولية"}

RELATION_LABELS = {
    "father": "الأب",
    "mother": "الأم",
    "brother": "أخ",
    "sister": "أخت",
    "other": "أخرى",
}

STATUS_LABELS = {
    LinkStatus.pending: "معلّق",
    LinkStatus.accepted: "مفعّل",
    LinkStatus.rejected: "مرفوض",
    LinkStatus.revoked: "ملغي",
}


def size_label(size_bytes: int) -> str:
    """حجم الملف بصيغة مقروءة."""
    if not size_bytes:
        return "—"
    megabytes = size_bytes / (1024 * 1024)
    if megabytes < 1:
        return f"{size_bytes / 1024:.0f} كيلو"
    return f"{megabytes:.1f} ميجا"


def _base_context(request: Request, active: str, **extra) -> dict:
    context = {
        "request": request,
        "active": active,
        "kind_label": lambda k: KIND_LABELS.get(k, str(k)),
        "role_label": lambda r: ROLE_LABELS.get(r, str(r)),
        "tier_label": lambda t: TIER_LABELS.get(t, t),
        "language_label": lambda code: LANGUAGE_LABELS.get(code, code),
        "relation_label": lambda r: RELATION_LABELS.get(r, r),
        "status_label": lambda s: STATUS_LABELS.get(s, str(s)),
        "size_label": size_label,
        "flash": request.query_params.get("msg"),
        "flash_kind": request.query_params.get("kind", "ok"),
    }
    context.update(extra)
    return context


def _guard(request: Request):
    """يرجّع إعادة توجيه لصفحة الدخول لو المستخدم مش مسجّل."""
    if not admin_auth.is_logged_in(request):
        return admin_auth.login_redirect()
    return None


def _redirect(path: str, message: str, kind: str = "ok") -> RedirectResponse:
    from urllib.parse import quote

    return RedirectResponse(
        url=f"{path}?msg={quote(message)}&kind={kind}", status_code=303
    )


# --------------------------------------------------------------------------
# الدخول والخروج
# --------------------------------------------------------------------------


@router.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    if admin_auth.is_logged_in(request):
        return RedirectResponse(url="/admin", status_code=303)
    return templates.TemplateResponse(
        "login.html", {"request": request, "hide_nav": True, "error": None}
    )


@router.post("/login", response_class=HTMLResponse)
async def login_submit(
    request: Request,
    email: str = Form(...),
    password: str = Form(...),
):
    if not admin_auth.check_admin_credentials(email, password):
        return templates.TemplateResponse(
            "login.html",
            {
                "request": request,
                "hide_nav": True,
                "error": "البريد أو كلمة المرور غير صحيحة",
            },
            status_code=401,
        )
    request.session[admin_auth.SESSION_KEY] = email
    return RedirectResponse(url="/admin", status_code=303)


@router.get("/logout")
async def logout(request: Request):
    request.session.clear()
    return RedirectResponse(url="/admin/login", status_code=303)


# --------------------------------------------------------------------------
# الرئيسية
# --------------------------------------------------------------------------


@router.get("", response_class=HTMLResponse)
async def dashboard(request: Request, db: Session = Depends(get_db)):
    if (redirect := _guard(request)) is not None:
        return redirect

    stats = {
        "curricula": db.query(func.count(Curriculum.id)).scalar() or 0,
        "subjects": db.query(func.count(Subject.id)).scalar() or 0,
        "lessons": db.query(func.count(Lesson.id)).scalar() or 0,
        "books_published": db.query(func.count(Book.id))
        .filter(Book.is_published.is_(True))
        .scalar()
        or 0,
        "books_draft": db.query(func.count(Book.id))
        .filter(Book.is_published.is_(False))
        .scalar()
        or 0,
        "students": db.query(func.count(Account.id))
        .filter(Account.role == AccountRole.student)
        .scalar()
        or 0,
        "guardians": db.query(func.count(Account.id))
        .filter(Account.role == AccountRole.guardian)
        .scalar()
        or 0,
        "pending_links": db.query(func.count(GuardianLink.id))
        .filter(GuardianLink.status == LinkStatus.pending)
        .scalar()
        or 0,
    }

    recent_books = (
        db.query(Book)
        .options(joinedload(Book.subject).joinedload(Subject.grade))
        .order_by(Book.created_at.desc())
        .limit(8)
        .all()
    )

    return templates.TemplateResponse(
        "dashboard.html",
        _base_context(request, "dashboard", stats=stats, recent_books=recent_books),
    )


# --------------------------------------------------------------------------
# المناهج
# --------------------------------------------------------------------------


@router.get("/curricula", response_class=HTMLResponse)
async def curricula_page(request: Request, db: Session = Depends(get_db)):
    if (redirect := _guard(request)) is not None:
        return redirect

    curricula = (
        db.query(Curriculum)
        .options(joinedload(Curriculum.grades))
        .order_by(Curriculum.id.desc())
        .all()
    )
    return templates.TemplateResponse(
        "curricula.html", _base_context(request, "curricula", curricula=curricula)
    )


@router.post("/curricula")
async def create_curriculum(
    request: Request,
    country_code: str = Form(...),
    system_id: str = Form(...),
    language: str = Form("arabic"),
    academic_year: str = Form("2025/2026"),
    name_ar: str = Form(...),
    name_en: str = Form(""),
    db: Session = Depends(get_db),
):
    if (redirect := _guard(request)) is not None:
        return redirect

    exists = (
        db.query(Curriculum)
        .filter(
            Curriculum.country_code == country_code,
            Curriculum.system_id == system_id,
            Curriculum.language == language,
            Curriculum.academic_year == academic_year,
        )
        .first()
    )
    if exists:
        return _redirect("/admin/curricula", "المنهج ده مسجّل قبل كده", "err")

    curriculum = Curriculum(
        country_code=country_code,
        system_id=system_id,
        language=language,
        academic_year=academic_year,
        name_ar=name_ar,
        name_en=name_en,
    )
    db.add(curriculum)
    db.commit()
    return _redirect("/admin/curricula", "تم إضافة المنهج")


@router.get("/curricula/{curriculum_id}", response_class=HTMLResponse)
async def curriculum_detail(
    request: Request, curriculum_id: int, db: Session = Depends(get_db)
):
    if (redirect := _guard(request)) is not None:
        return redirect

    curriculum = (
        db.query(Curriculum)
        .options(joinedload(Curriculum.grades).joinedload(Grade.subjects))
        .filter(Curriculum.id == curriculum_id)
        .first()
    )
    if curriculum is None:
        return _redirect("/admin/curricula", "المنهج غير موجود", "err")

    return templates.TemplateResponse(
        "curriculum_detail.html",
        _base_context(request, "curricula", curriculum=curriculum),
    )


@router.post("/curricula/{curriculum_id}/grades")
async def add_grade(
    request: Request,
    curriculum_id: int,
    level: int = Form(...),
    name_ar: str = Form(...),
    name_en: str = Form(""),
    track_id: str = Form(""),
    db: Session = Depends(get_db),
):
    if (redirect := _guard(request)) is not None:
        return redirect

    stage = (
        EducationStage.primary
        if level <= 6
        else EducationStage.preparatory
        if level <= 9
        else EducationStage.secondary
    )

    exists = (
        db.query(Grade)
        .filter(Grade.curriculum_id == curriculum_id, Grade.level == level)
        .first()
    )
    if exists:
        return _redirect(
            f"/admin/curricula/{curriculum_id}", "الصف ده مضاف قبل كده", "err"
        )

    db.add(
        Grade(
            curriculum_id=curriculum_id,
            level=level,
            stage=stage,
            name_ar=name_ar,
            name_en=name_en,
            track_id=track_id,
        )
    )
    db.commit()
    return _redirect(f"/admin/curricula/{curriculum_id}", "تم إضافة الصف")


@router.post("/grades/{grade_id}/subjects")
async def add_subject(
    request: Request,
    grade_id: int,
    slug: str = Form(...),
    name_ar: str = Form(...),
    name_en: str = Form(""),
    color: str = Form("#2E7D91"),
    counts_toward_total: str = Form(""),
    db: Session = Depends(get_db),
):
    if (redirect := _guard(request)) is not None:
        return redirect

    grade = db.get(Grade, grade_id)
    if grade is None:
        return _redirect("/admin/curricula", "الصف غير موجود", "err")

    order = (
        db.query(func.count(Subject.id)).filter(Subject.grade_id == grade_id).scalar()
        or 0
    )
    db.add(
        Subject(
            grade_id=grade_id,
            slug=slug,
            name_ar=name_ar,
            name_en=name_en,
            color=color,
            counts_toward_total=bool(counts_toward_total),
            sort_order=order,
        )
    )
    db.commit()
    return _redirect(f"/admin/curricula/{grade.curriculum_id}", "تم إضافة المادة")


# --------------------------------------------------------------------------
# الكتب والملازم
# --------------------------------------------------------------------------


def _subject_options(db: Session) -> list[dict]:
    """قائمة المواد بصيغة: المنهج ← الصف ← المادة."""
    rows = (
        db.query(Subject)
        .options(joinedload(Subject.grade).joinedload(Grade.curriculum))
        .order_by(Subject.grade_id, Subject.sort_order)
        .all()
    )
    return [
        {
            "id": subject.id,
            "label": (
                f"{subject.grade.curriculum.name_ar} · "
                f"{subject.grade.name_ar} · {subject.name_ar}"
            ),
        }
        for subject in rows
    ]


@router.get("/books", response_class=HTMLResponse)
async def books_page(
    request: Request,
    subject_id: int | None = None,
    db: Session = Depends(get_db),
):
    if (redirect := _guard(request)) is not None:
        return redirect

    query = db.query(Book).options(
        joinedload(Book.subject).joinedload(Subject.grade)
    )
    if subject_id:
        query = query.filter(Book.subject_id == subject_id)

    books = query.order_by(Book.created_at.desc()).all()

    return templates.TemplateResponse(
        "books.html",
        _base_context(
            request,
            "books",
            books=books,
            subject_options=_subject_options(db),
            selected_subject=subject_id,
            max_mb=settings.max_upload_mb,
        ),
    )


@router.post("/books")
async def upload_book(
    request: Request,
    subject_id: int = Form(...),
    kind: str = Form("textbook"),
    term: int = Form(1),
    title_ar: str = Form(...),
    publisher: str = Form(""),
    source_url: str = Form(""),
    license_note: str = Form(""),
    is_published: str = Form(""),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    if (redirect := _guard(request)) is not None:
        return redirect

    subject = (
        db.query(Subject)
        .options(joinedload(Subject.grade))
        .filter(Subject.id == subject_id)
        .first()
    )
    if subject is None:
        return _redirect("/admin/books", "المادة غير موجودة", "err")

    content = await file.read()
    try:
        saved = media.save_book_file(
            content=content,
            original_name=file.filename or "book.pdf",
            curriculum_id=subject.grade.curriculum_id,
            grade_level=subject.grade.level,
            subject_slug=subject.slug,
        )
    except ValueError as error:
        return _redirect("/admin/books", str(error), "err")

    book = Book(
        subject_id=subject_id,
        kind=BookKind(kind),
        term=term,
        title_ar=title_ar,
        publisher=publisher,
        source_url=source_url,
        license_note=license_note,
        is_published=bool(is_published),
        **saved,
    )
    db.add(book)
    db.commit()

    pages = saved["page_count"]
    detail = f" ({pages} صفحة)" if pages else ""
    return _redirect("/admin/books", f"تم رفع الملف{detail}")


@router.post("/books/{book_id}/toggle")
async def toggle_book(
    request: Request, book_id: int, db: Session = Depends(get_db)
):
    if (redirect := _guard(request)) is not None:
        return redirect

    book = db.get(Book, book_id)
    if book is None:
        return _redirect("/admin/books", "الملف غير موجود", "err")

    book.is_published = not book.is_published
    db.commit()
    return _redirect(
        "/admin/books", "تم نشر الملف" if book.is_published else "تم إخفاء الملف"
    )


@router.post("/books/{book_id}/delete")
async def delete_book(
    request: Request, book_id: int, db: Session = Depends(get_db)
):
    if (redirect := _guard(request)) is not None:
        return redirect

    book = db.get(Book, book_id)
    if book is None:
        return _redirect("/admin/books", "الملف غير موجود", "err")

    media.delete_book_file(book.file_path)
    db.delete(book)
    db.commit()
    return _redirect("/admin/books", "تم حذف الملف")


# --------------------------------------------------------------------------
# الحسابات والروابط
# --------------------------------------------------------------------------


@router.get("/accounts", response_class=HTMLResponse)
async def accounts_page(request: Request, db: Session = Depends(get_db)):
    if (redirect := _guard(request)) is not None:
        return redirect

    accounts = db.query(Account).order_by(Account.created_at.desc()).limit(200).all()

    # باقة كل حساب من أحدث اشتراك ساري
    tiers: dict[int, str] = {}
    for subscription in db.query(Subscription).all():
        if subscription.is_valid and subscription.tier != PlanTier.free:
            tiers[subscription.account_id] = subscription.tier.value

    counts = {
        "total": db.query(func.count(Account.id)).scalar() or 0,
        "students": db.query(func.count(Account.id))
        .filter(Account.role == AccountRole.student)
        .scalar()
        or 0,
        "guardians": db.query(func.count(Account.id))
        .filter(Account.role == AccountRole.guardian)
        .scalar()
        or 0,
        "subscribed": len(tiers),
    }

    return templates.TemplateResponse(
        "accounts.html",
        _base_context(
            request,
            "accounts",
            accounts=accounts,
            counts=counts,
            tier_of=lambda a: tiers.get(a.id, "free"),
        ),
    )


@router.get("/links", response_class=HTMLResponse)
async def links_page(request: Request, db: Session = Depends(get_db)):
    if (redirect := _guard(request)) is not None:
        return redirect

    links = (
        db.query(GuardianLink)
        .options(
            joinedload(GuardianLink.guardian), joinedload(GuardianLink.student)
        )
        .order_by(GuardianLink.created_at.desc())
        .all()
    )
    return templates.TemplateResponse(
        "links.html", _base_context(request, "links", links=links)
    )


# --------------------------------------------------------------------------
# إعدادات التكامل (AdMob / Google Play / Firebase / AI)
# --------------------------------------------------------------------------


@router.get("/settings", response_class=HTMLResponse)
async def settings_page(request: Request, db: Session = Depends(get_db)):
    if (redirect := _guard(request)) is not None:
        return redirect

    stored = {row.key: row.value for row in db.query(IntegrationSetting).all()}

    # القيم السرّية مبتترجعش للصفحة — بنعرض إنها محفوظة بس.
    display: dict[str, str] = {}
    for definition in SETTING_DEFINITIONS:
        key = definition["key"]
        value = stored.get(key, "")
        display[key] = "saved" if (definition["secret"] and value) else value

    return templates.TemplateResponse(
        "settings.html",
        _base_context(
            request,
            "settings",
            groups=definitions_by_group(),
            values=display,
            prices=PLAN_PRICES,
            limits=PLAN_LIMITS,
        ),
    )


@router.post("/settings")
async def save_settings(request: Request, db: Session = Depends(get_db)):
    if (redirect := _guard(request)) is not None:
        return redirect

    form = await request.form()

    for definition in SETTING_DEFINITIONS:
        key = definition["key"]
        submitted = form.get(key)

        if definition["kind"] == "bool":
            value = "1" if submitted else "0"
        else:
            value = (submitted or "").strip()
            # حقل سرّي فاضي = المستخدم مغيّرش القيمة، فبنسيبها زي ما هي.
            if definition["secret"] and not value:
                continue

        row = db.get(IntegrationSetting, key)
        if row is None:
            row = IntegrationSetting(
                key=key, value=value, is_secret=definition["secret"]
            )
            db.add(row)
        else:
            row.value = value

    db.commit()
    return _redirect("/admin/settings", "تم حفظ الإعدادات")
