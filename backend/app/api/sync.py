"""مزامنة بيانات الطالب بين أجهزته والسيرفر.

البروتوكول تفاضلي وبسيط:

    GET  /api/v1/sync?since=<رقم>      ← هات اللي اتغيّر بعد الرقم ده
    POST /api/v1/sync {since, records} ← خد تعديلاتي وهات تعديلات غيري

كل حساب عنده عدّاد `sync_revision`. كل كتابة بتزوّده واحد وبتختم بيه
السجل، فالعميل بيحتفظ بآخر رقم شافه وبيطلب اللي بعده بس.

**حسم التعارض:** لو نفس السجل اتعدّل على جهازين، الأحدث بـ `updated_at`
(ساعة الجهاز) بيكسب. لو اللي على السيرفر أحدث، بنرفض تعديل العميل
وبنرجّعله نسخة السيرفر في نفس الرد عشان يصحّح نفسه فورًا.

**الحذف ناعم:** السجل المحذوف بيفضل بعلامة `deleted` عشان الجهاز التاني
يعرف إنه اتمسح، مش يفتكره سجل جديد ويرجّعه.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import current_account
from app.models import Account, RecordKind, StudentRecord

router = APIRouter(prefix="/api/v1", tags=["sync"])

# سقف عدد السجلات في الطلب الواحد — يحمي السيرفر من دفعة ضخمة
MAX_RECORDS_PER_PUSH = 500
MAX_RECORDS_PER_PULL = 1000

# سقف حجم المستند الواحد (٦٤ كيلو) — أي سجل أكبر من كده غلط في العميل
MAX_PAYLOAD_BYTES = 64 * 1024


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _aware(moment: datetime) -> datetime:
    """MySQL بيرجّع التواريخ بدون منطقة زمنية — بنعتبرها UTC."""
    return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)


# --------------------------------------------------------------------------
# النماذج
# --------------------------------------------------------------------------


class RecordIn(BaseModel):
    kind: RecordKind
    id: str = Field(min_length=1, max_length=64)
    payload: dict = Field(default_factory=dict)
    updated_at: datetime
    deleted: bool = False

    @field_validator("payload")
    @classmethod
    def _payload_fits(cls, value: dict) -> dict:
        encoded = json.dumps(value, ensure_ascii=False)
        if len(encoded.encode("utf-8")) > MAX_PAYLOAD_BYTES:
            raise ValueError("السجل أكبر من الحد المسموح")
        return value


class RecordOut(BaseModel):
    kind: RecordKind
    id: str
    payload: dict
    updated_at: datetime
    deleted: bool
    revision: int


class PushIn(BaseModel):
    since: int = 0
    records: list[RecordIn] = Field(default_factory=list, max_length=MAX_RECORDS_PER_PUSH)


class SyncOut(BaseModel):
    revision: int
    records: list[RecordOut]
    # فيه كمان بعد الدفعة دي؟ العميل يعيد الطلب برقم أحدث
    has_more: bool = False
    # السجلات اللي السيرفر رفض تعديلها لأن عنده نسخة أحدث
    rejected: list[str] = Field(default_factory=list)
    server_time: datetime


# --------------------------------------------------------------------------
# المساعدات
# --------------------------------------------------------------------------


def _to_out(record: StudentRecord) -> RecordOut:
    try:
        payload = json.loads(record.payload) if record.payload else {}
    except json.JSONDecodeError:
        payload = {}
    return RecordOut(
        kind=record.kind,
        id=record.record_id,
        payload=payload if isinstance(payload, dict) else {},
        updated_at=_aware(record.updated_at),
        deleted=record.is_deleted,
        revision=record.revision,
    )


def _changes_since(
    db: Session, account_id: int, since: int, limit: int = MAX_RECORDS_PER_PULL
) -> tuple[list[StudentRecord], bool]:
    rows = (
        db.query(StudentRecord)
        .filter(
            StudentRecord.account_id == account_id,
            StudentRecord.revision > since,
        )
        .order_by(StudentRecord.revision)
        .limit(limit + 1)
        .all()
    )
    has_more = len(rows) > limit
    return rows[:limit], has_more


def _next_revision(db: Session, account: Account) -> int:
    """يحجز الرقم اللي بعده ويقفل صف الحساب لحد ما المعاملة تخلص.

    القفل ده هو اللي بيمنع جهازين بيزامنوا في نفس اللحظة من إنهم ياخدوا
    نفس الرقم — ووقتها واحد منهم كان هيختفي من نتيجة المزامنة.
    """
    locked = (
        db.query(Account)
        .filter(Account.id == account.id)
        .with_for_update()
        .one()
    )
    locked.sync_revision = (locked.sync_revision or 0) + 1
    return locked.sync_revision


def _current_revision(db: Session, account_id: int) -> int:
    value = (
        db.query(func.coalesce(Account.sync_revision, 0))
        .filter(Account.id == account_id)
        .scalar()
    )
    return int(value or 0)


# --------------------------------------------------------------------------
# نقاط النهاية
# --------------------------------------------------------------------------


@router.get("/sync", response_model=SyncOut)
def pull(
    since: int = Query(0, ge=0),
    account: Account = Depends(current_account),
    db: Session = Depends(get_db),
) -> SyncOut:
    """اللي اتغيّر في حساب المستخدم بعد الرقم `since`."""
    rows, has_more = _changes_since(db, account.id, since)
    revision = rows[-1].revision if rows else _current_revision(db, account.id)
    return SyncOut(
        revision=revision,
        records=[_to_out(row) for row in rows],
        has_more=has_more,
        server_time=_now(),
    )


@router.post("/sync", response_model=SyncOut)
def push(
    body: PushIn,
    account: Account = Depends(current_account),
    db: Session = Depends(get_db),
) -> SyncOut:
    """يستقبل تعديلات الجهاز ويرجّع تعديلات الأجهزة التانية."""

    if len(body.records) > MAX_RECORDS_PER_PUSH:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"أقصى عدد سجلات في الطلب {MAX_RECORDS_PER_PUSH}",
        )

    rejected: list[str] = []
    touched = False

    for incoming in body.records:
        existing = (
            db.query(StudentRecord)
            .filter(
                StudentRecord.account_id == account.id,
                StudentRecord.kind == incoming.kind,
                StudentRecord.record_id == incoming.id,
            )
            .one_or_none()
        )

        incoming_at = _aware(incoming.updated_at)

        if existing is not None and _aware(existing.updated_at) > incoming_at:
            # السيرفر عنده أحدث — بنرفض وبنسيب العميل يصحّح نفسه من الرد
            rejected.append(f"{incoming.kind.value}:{incoming.id}")
            continue

        revision = _next_revision(db, account)
        touched = True

        if existing is None:
            existing = StudentRecord(
                account_id=account.id,
                kind=incoming.kind,
                record_id=incoming.id,
            )
            db.add(existing)

        existing.payload = json.dumps(incoming.payload, ensure_ascii=False)
        existing.updated_at = incoming_at
        existing.is_deleted = incoming.deleted
        existing.revision = revision

    if touched:
        db.commit()

    # بنرجّع اللي اتغيّر من وجهة نظر العميل — بما فيه اللي رفضناه، عشان
    # يستبدل نسخته بنسخة السيرفر من غير طلب تاني.
    rows, has_more = _changes_since(db, account.id, body.since)
    revision = rows[-1].revision if rows else _current_revision(db, account.id)

    return SyncOut(
        revision=revision,
        records=[_to_out(row) for row in rows],
        has_more=has_more,
        rejected=rejected,
        server_time=_now(),
    )


class WipeOut(BaseModel):
    revision: int


@router.delete("/sync", response_model=WipeOut)
def wipe(
    account: Account = Depends(current_account),
    db: Session = Depends(get_db),
) -> WipeOut:
    """يمسح كل بيانات الحساب من السيرفر (حق المستخدم في حذف بياناته).

    الحذف هنا نهائي مش ناعم — ده طلب صريح من صاحب البيانات، مش مزامنة.
    """
    db.query(StudentRecord).filter(
        StudentRecord.account_id == account.id
    ).delete(synchronize_session=False)
    locked = db.query(Account).filter(Account.id == account.id).with_for_update().one()
    locked.sync_revision = (locked.sync_revision or 0) + 1
    revision = locked.sync_revision
    db.commit()
    return WipeOut(revision=revision)


# --------------------------------------------------------------------------
# قراءة ولي الأمر لبيانات ابنه
# --------------------------------------------------------------------------
#
# ولي الأمر **بيقرا بس**، والطالب هو اللي بيحدّد يشوف إيه لما وافق على
# الربط. عشان كده كل نوع بيتفلتر بصلاحيته، ومصاريف الدروس بتتشال من
# السجل نفسه لو الصلاحية مقفولة — مش بنعتمد على إن التطبيق هيخبّيها.


PERMISSION_FOR_KIND = {
    RecordKind.period: "viewTimetable",
    RecordKind.lesson: "viewLessons",
    RecordKind.task: "viewTasks",
    # المدرسين والمواد بيتبعوا الدروس — من غيرهم الجدول مش مفهوم
    RecordKind.instructor: "viewLessons",
    RecordKind.subject: "viewTimetable",
}

# حقول المصاريف — بتتشال لو الطالب مقفل الصلاحية دي
COST_FIELDS = {"cost", "sessionCost", "monthlyCost", "price"}


class ChildOut(BaseModel):
    student_id: int
    name: str
    grade_level: int | None
    permissions: dict
    revision: int


class ChildDataOut(BaseModel):
    student_id: int
    revision: int
    records: list[RecordOut]
    server_time: datetime


def _permissions_of(link: "GuardianLink") -> dict:  # noqa: F821
    try:
        loaded = json.loads(link.permissions or "{}")
    except json.JSONDecodeError:
        loaded = {}
    return loaded if isinstance(loaded, dict) else {}


def _linked_child(db: Session, guardian: Account, student_id: int) -> "GuardianLink":  # noqa: F821
    from app.models import GuardianLink, LinkStatus

    link = (
        db.query(GuardianLink)
        .filter(
            GuardianLink.guardian_id == guardian.id,
            GuardianLink.student_id == student_id,
            GuardianLink.status == LinkStatus.accepted,
        )
        .one_or_none()
    )
    if link is None:
        # مش بنفرّق بين "مش موجود" و"مش مربوط" — الاتنين مش من حقه يعرفهم
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="مفيش ابن مربوط بالحساب ده",
        )
    return link


def _visible_to_guardian(record: StudentRecord, permissions: dict) -> RecordOut | None:
    """يرجّع السجل بالشكل اللي ولي الأمر مسموح يشوفه، أو None لو ممنوع."""
    needed = PERMISSION_FOR_KIND.get(record.kind)
    if needed is None:
        return None                       # الملف الشخصي وأي نوع جديد: مقفول
    if not permissions.get(needed, False):
        return None

    out = _to_out(record)
    if not permissions.get("viewLessonCosts", False):
        out.payload = {
            key: value for key, value in out.payload.items()
            if key not in COST_FIELDS
        }
    return out


@router.get("/children", response_model=list[ChildOut])
def children(
    account: Account = Depends(current_account),
    db: Session = Depends(get_db),
) -> list[ChildOut]:
    """الأبناء المربوطين بولي الأمر ده."""
    from app.models import GuardianLink, LinkStatus

    links = (
        db.query(GuardianLink)
        .filter(
            GuardianLink.guardian_id == account.id,
            GuardianLink.status == LinkStatus.accepted,
        )
        .all()
    )
    return [
        ChildOut(
            student_id=link.student_id,
            name=link.student.display_name or "",
            grade_level=link.student.grade_level,
            permissions=_permissions_of(link),
            revision=link.student.sync_revision or 0,
        )
        for link in links
    ]


@router.get("/children/{student_id}/records", response_model=ChildDataOut)
def child_records(
    student_id: int,
    since: int = Query(0, ge=0),
    account: Account = Depends(current_account),
    db: Session = Depends(get_db),
) -> ChildDataOut:
    """بيانات الابن اللي الطالب سمح لولي أمره يشوفها."""
    link = _linked_child(db, account, student_id)
    permissions = _permissions_of(link)

    rows, _ = _changes_since(db, student_id, since)
    visible = [
        item for item in (_visible_to_guardian(row, permissions) for row in rows)
        if item is not None
    ]

    return ChildDataOut(
        student_id=student_id,
        revision=_current_revision(db, student_id),
        records=visible,
        server_time=_now(),
    )
