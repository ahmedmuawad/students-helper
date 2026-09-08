"""تخزين بيانات الطالب على السيرفر للمزامنة بين الأجهزة.

التطبيق أوفلاين أولًا: كل شاشة بتشتغل من التخزين المحلي، والمزامنة
بتحصل في الخلفية. عشان كده بنخزّن كل سجل كـ **مستند JSON** زي ما
التطبيق كتبه بالظبط، مش أعمدة متفرّقة:

* التطبيق يقدر يضيف حقل جديد من غير هجرة قاعدة بيانات.
* المزامنة بتبقى نسخ حرفي — مفيش تحويل ممكن يضيّع بيانات.
* اللي محتاج يقرا (شاشة ولي الأمر) بيفك الـJSON في بايثون، والبيانات
  دي عشرات السجلات لطالب واحد مش ملايين، فمفيش داعي لاستعلامات SQL جواها.

كل حساب عنده عدّاد `sync_revision` بيزيد مع كل كتابة. العميل بيحتفظ بآخر
رقم شافه، وبيطلب اللي بعده بس — فالمزامنة تفاضلية مش تحميل كامل.
"""

from __future__ import annotations

import enum
from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class RecordKind(str, enum.Enum):
    """أنواع السجلات اللي بتتزامن."""

    profile = "profile"          # الملف الشخصي (سجل واحد بس)
    subject = "subject"          # مادة أضافها الطالب
    period = "period"            # حصة في الجدول المدرسي
    lesson = "lesson"            # درس خصوصي
    instructor = "instructor"    # مدرس أو سنتر
    task = "task"                # مهمة


class StudentRecord(Base):
    """سجل واحد من بيانات الطالب، متخزّن زي ما التطبيق كتبه."""

    __tablename__ = "student_records"
    __table_args__ = (
        UniqueConstraint("account_id", "kind", "record_id", name="uq_record_identity"),
        # المزامنة بتسأل دايمًا: "إيه اللي اتغيّر لحسابي بعد الرقم ده؟"
        Index("ix_record_account_revision", "account_id", "revision"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    account_id: Mapped[int] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), index=True
    )
    kind: Mapped[RecordKind] = mapped_column(Enum(RecordKind))

    # المعرّف اللي التطبيق مولّده — بيفضل هو هو على كل الأجهزة
    record_id: Mapped[str] = mapped_column(String(64))

    payload: Mapped[str] = mapped_column(Text, default="{}")

    # وقت آخر تعديل **من ساعة الجهاز** — ده اللي بنحسم بيه التعارض
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))

    # الحذف ناعم: الجهاز التاني لازم يعرف إن السجل اتمسح
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)

    # رقم النسخة على السيرفر — بيزيد مع كل كتابة
    revision: Mapped[int] = mapped_column(BigInteger, index=True)

    server_updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    account: Mapped["Account"] = relationship()  # noqa: F821
