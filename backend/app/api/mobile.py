"""واجهة الـ API اللي التطبيق بيتكلم معاها."""

from __future__ import annotations

import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload

from app.core.config import get_settings
from app.core.database import get_db
from app.core.plans import (
    AI_CREDIT_COSTS,
    PLAN_PRICES,
    ad_personalization_allowed,
    limits_for,
)
from app.core.security import current_account, optional_account
from app.models import (
    Account,
    AccountRole,
    AiUsage,
    Book,
    Curriculum,
    Grade,
    GuardianLink,
    LinkCode,
    LinkStatus,
    PlanTier,
    Subject,
    Subscription,
)
from app.models.settings_store import PUBLIC_KEYS, IntegrationSetting

router = APIRouter(prefix="/api/v1", tags=["mobile"])
settings = get_settings()

LINK_CODE_TTL_MINUTES = 15


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _account_age(account: Account) -> int | None:
    birth = account.birth_date
    if birth is None:
        return None
    today = _now()
    years = today.year - birth.year
    if (today.month, today.day) < (birth.month, birth.day):
        years -= 1
    return years if years >= 0 else None


def _active_tier(db: Session, account_id: int) -> PlanTier:
    """أعلى باقة سارية للحساب."""
    subscriptions = (
        db.query(Subscription).filter(Subscription.account_id == account_id).all()
    )
    tier = PlanTier.free
    for subscription in subscriptions:
        if not subscription.is_valid:
            continue
        if subscription.tier == PlanTier.pro:
            return PlanTier.pro
        if subscription.tier == PlanTier.plus:
            tier = PlanTier.plus
    return tier


def _ai_credits_used_this_month(db: Session, account_id: int) -> int:
    start = _now().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    total = (
        db.query(func.coalesce(func.sum(AiUsage.credits), 0))
        .filter(AiUsage.account_id == account_id, AiUsage.created_at >= start)
        .scalar()
    )
    return int(total or 0)


# --------------------------------------------------------------------------
# النماذج
# --------------------------------------------------------------------------


class ProfileOut(BaseModel):
    id: int
    firebase_uid: str
    role: str
    display_name: str
    email: str
    grade_level: int | None
    system_id: str
    school_language: str
    school_name: str
    track_id: str


class ProfileIn(BaseModel):
    role: str | None = None
    display_name: str | None = None
    grade_level: int | None = None
    system_id: str | None = None
    school_language: str | None = None
    school_name: str | None = None
    track_id: str | None = None
    country_code: str | None = None
    birth_date: datetime | None = None


class EntitlementsOut(BaseModel):
    """كل اللي التطبيق محتاج يعرفه عن صلاحيات المستخدم وحدوده."""

    tier: str
    show_ads: bool
    personalized_ads: bool
    limits: dict
    ai_credits_total: int
    ai_credits_used: int
    ai_credit_costs: dict
    prices: dict


class LinkCodeOut(BaseModel):
    code: str
    expires_at: datetime
    ttl_minutes: int


class RedeemIn(BaseModel):
    code: str = Field(min_length=4, max_length=12)
    relation: str = "other"


class LinkOut(BaseModel):
    id: int
    status: str
    relation: str
    guardian_name: str
    student_name: str
    created_at: datetime


# --------------------------------------------------------------------------
# الملف الشخصي والصلاحيات
# --------------------------------------------------------------------------


@router.get("/me", response_model=ProfileOut)
async def read_me(account: Account = Depends(current_account)):
    return ProfileOut(
        id=account.id,
        firebase_uid=account.firebase_uid,
        role=account.role.value,
        display_name=account.display_name,
        email=account.email,
        grade_level=account.grade_level,
        system_id=account.system_id,
        school_language=account.school_language,
        school_name=account.school_name,
        track_id=account.track_id,
    )


@router.patch("/me", response_model=ProfileOut)
async def update_me(
    payload: ProfileIn,
    account: Account = Depends(current_account),
    db: Session = Depends(get_db),
):
    if payload.role is not None:
        try:
            new_role = AccountRole(payload.role)
        except ValueError as error:
            raise HTTPException(status_code=400, detail="دور غير معروف") from error
        # الأدمن مبيتحطش من التطبيق
        if new_role == AccountRole.admin:
            raise HTTPException(status_code=403, detail="غير مسموح")
        account.role = new_role

    for field in (
        "display_name",
        "grade_level",
        "system_id",
        "school_language",
        "school_name",
        "track_id",
        "country_code",
        "birth_date",
    ):
        value = getattr(payload, field)
        if value is not None:
            setattr(account, field, value)

    db.commit()
    db.refresh(account)
    return await read_me(account)


@router.get("/entitlements", response_model=EntitlementsOut)
async def entitlements(
    account: Account = Depends(current_account),
    db: Session = Depends(get_db),
):
    """التطبيق بينادي دي عشان يعرف يعرض إعلانات ولا لأ، وإيه المتاح له."""
    tier = _active_tier(db, account.id)
    limits = limits_for(tier)
    credits_total = limits.get("ai_credits_per_month") or 0

    return EntitlementsOut(
        tier=tier.value,
        show_ads=bool(limits.get("ads")),
        # تحت 13 سنة: إعلانات غير مخصّصة إجباريًا (COPPA وسياسة العائلات)
        personalized_ads=ad_personalization_allowed(_account_age(account)),
        limits=limits,
        ai_credits_total=credits_total,
        ai_credits_used=_ai_credits_used_this_month(db, account.id),
        ai_credit_costs=AI_CREDIT_COSTS,
        prices={tier.value: price for tier, price in PLAN_PRICES.items()},
    )


@router.get("/config")
async def public_config(db: Session = Depends(get_db)):
    """الإعدادات العامة (معرّفات AdMob ومنتجات Play) — بدون أي مفتاح سرّي."""
    rows = db.query(IntegrationSetting).all()
    return {
        row.key: row.value
        for row in rows
        if row.key in PUBLIC_KEYS and not row.is_secret
    }


# --------------------------------------------------------------------------
# المناهج والكتب
# --------------------------------------------------------------------------


@router.get("/curricula")
async def list_curricula(db: Session = Depends(get_db)):
    rows = (
        db.query(Curriculum)
        .filter(Curriculum.is_published.is_(True))
        .order_by(Curriculum.country_code, Curriculum.system_id)
        .all()
    )
    return [
        {
            "id": c.id,
            "country_code": c.country_code,
            "system_id": c.system_id,
            "language": c.language,
            "academic_year": c.academic_year,
            "name_ar": c.name_ar,
            "name_en": c.name_en,
        }
        for c in rows
    ]


@router.get("/library")
async def library(
    grade_level: int | None = None,
    system_id: str | None = None,
    language: str | None = None,
    term: int | None = None,
    account: Account | None = Depends(optional_account),
    db: Session = Depends(get_db),
):
    """مكتبة الطالب: الكتب والملازم المتاحة لصفه ونظامه.

    مفتوحة من غير تسجيل دخول — دي كتب الوزارة المنشورة مجانًا، والتطبيق
    شغّال من غير حساب. لو المستخدم مسجّل، بياناته بتبقى الافتراضي.
    """

    if account is not None:
        grade_level = grade_level or account.grade_level
        system_id = system_id or account.system_id
        language = language or account.school_language

    query = (
        db.query(Book)
        .join(Book.subject)
        .join(Subject.grade)
        .join(Grade.curriculum)
        .options(joinedload(Book.subject).joinedload(Subject.grade))
        .filter(Book.is_published.is_(True), Curriculum.is_published.is_(True))
    )

    if grade_level is not None:
        query = query.filter(Grade.level == grade_level)
    if system_id:
        query = query.filter(Curriculum.system_id == system_id)
    if language:
        query = query.filter(Curriculum.language == language)
    if term:
        query = query.filter(Book.term == term)

    books = query.order_by(Subject.sort_order, Book.sort_order).all()

    return [
        {
            "id": b.id,
            "title_ar": b.title_ar,
            "title_en": b.title_en,
            "kind": b.kind.value,
            "term": b.term,
            "publisher": b.publisher,
            "subject_id": b.subject.slug,
            "subject_name_ar": b.subject.name_ar,
            "subject_color": b.subject.color,
            "page_count": b.page_count,
            "file_size": b.file_size,
            "file_url": f"{settings.media_url_prefix}/{b.file_path}",
            "source_url": b.source_url,
            "license_note": b.license_note,
        }
        for b in books
    ]


# --------------------------------------------------------------------------
# ربط ولي الأمر بالطالب
# --------------------------------------------------------------------------


@router.post("/link-codes", response_model=LinkCodeOut)
async def create_link_code(
    account: Account = Depends(current_account),
    db: Session = Depends(get_db),
):
    """الطالب بيولّد كود قصير يدّيه لولي أمره."""

    if account.role != AccountRole.student:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="الطالب بس هو اللي يقدر يولّد كود ربط",
        )

    # نلغي الأكواد القديمة اللي لسه صالحة عشان يفضل كود واحد نشط.
    db.query(LinkCode).filter(
        LinkCode.student_id == account.id, LinkCode.used_at.is_(None)
    ).delete()

    # 6 خانات رقمية سهلة القراءة والنطق
    code = f"{secrets.randbelow(1_000_000):06d}"
    expires_at = _now() + timedelta(minutes=LINK_CODE_TTL_MINUTES)

    db.add(LinkCode(code=code, student_id=account.id, expires_at=expires_at))
    db.commit()

    return LinkCodeOut(
        code=code, expires_at=expires_at, ttl_minutes=LINK_CODE_TTL_MINUTES
    )


@router.post("/links/redeem", response_model=LinkOut)
async def redeem_link_code(
    payload: RedeemIn,
    account: Account = Depends(current_account),
    db: Session = Depends(get_db),
):
    """ولي الأمر بيدخّل الكود عشان يطلب الربط — الطالب لازم يوافق بعدها."""

    entry = db.query(LinkCode).filter(LinkCode.code == payload.code.strip()).first()
    if entry is None or not entry.is_usable:
        raise HTTPException(status_code=400, detail="الكود غير صالح أو منتهي")

    if entry.student_id == account.id:
        raise HTTPException(status_code=400, detail="مينفعش تربط نفسك بنفسك")

    existing = (
        db.query(GuardianLink)
        .filter(
            GuardianLink.guardian_id == account.id,
            GuardianLink.student_id == entry.student_id,
        )
        .first()
    )
    if existing is not None and existing.status == LinkStatus.accepted:
        raise HTTPException(status_code=400, detail="الربط موجود بالفعل")

    link = existing or GuardianLink(
        guardian_id=account.id, student_id=entry.student_id
    )
    link.relation = payload.relation
    link.status = LinkStatus.pending
    link.responded_at = None

    if account.role == AccountRole.student:
        account.role = AccountRole.guardian

    entry.used_at = _now()
    db.add(link)
    db.commit()
    db.refresh(link)

    return LinkOut(
        id=link.id,
        status=link.status.value,
        relation=link.relation,
        guardian_name=account.display_name,
        student_name=link.student.display_name,
        created_at=link.created_at,
    )


@router.get("/links", response_model=list[LinkOut])
async def my_links(
    account: Account = Depends(current_account),
    db: Session = Depends(get_db),
):
    """كل الروابط اللي الحساب طرف فيها (كولي أمر أو كطالب)."""
    links = (
        db.query(GuardianLink)
        .options(
            joinedload(GuardianLink.guardian), joinedload(GuardianLink.student)
        )
        .filter(
            (GuardianLink.guardian_id == account.id)
            | (GuardianLink.student_id == account.id)
        )
        .order_by(GuardianLink.created_at.desc())
        .all()
    )
    return [
        LinkOut(
            id=link.id,
            status=link.status.value,
            relation=link.relation,
            guardian_name=link.guardian.display_name,
            student_name=link.student.display_name,
            created_at=link.created_at,
        )
        for link in links
    ]


class RespondIn(BaseModel):
    accept: bool
    permissions: dict | None = None


@router.post("/links/{link_id}/respond", response_model=LinkOut)
async def respond_to_link(
    link_id: int,
    body: RespondIn,
    account: Account = Depends(current_account),
    db: Session = Depends(get_db),
):
    """الطالب بيوافق أو يرفض طلب الربط ويحدد الصلاحيات."""
    import json

    accept, permissions = body.accept, body.permissions

    link = db.get(GuardianLink, link_id)
    if link is None:
        raise HTTPException(status_code=404, detail="الطلب غير موجود")

    # الطالب بس هو اللي يقرر
    if link.student_id != account.id:
        raise HTTPException(
            status_code=403, detail="الطالب بس هو اللي يقدر يرد على الطلب"
        )

    link.status = LinkStatus.accepted if accept else LinkStatus.rejected
    link.responded_at = _now()
    if permissions is not None:
        link.permissions = json.dumps(permissions, ensure_ascii=False)

    db.commit()
    db.refresh(link)

    return LinkOut(
        id=link.id,
        status=link.status.value,
        relation=link.relation,
        guardian_name=link.guardian.display_name,
        student_name=link.student.display_name,
        created_at=link.created_at,
    )


@router.delete("/links/{link_id}")
async def revoke_link(
    link_id: int,
    account: Account = Depends(current_account),
    db: Session = Depends(get_db),
):
    """أي طرف يقدر يفك الربط في أي وقت."""
    link = db.get(GuardianLink, link_id)
    if link is None:
        raise HTTPException(status_code=404, detail="الربط غير موجود")

    if account.id not in (link.guardian_id, link.student_id):
        raise HTTPException(status_code=403, detail="غير مسموح")

    link.status = LinkStatus.revoked
    link.responded_at = _now()
    db.commit()
    return {"ok": True}
