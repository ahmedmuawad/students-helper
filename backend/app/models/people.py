"""جداول الحسابات وربط ولي الأمر بالطالب."""

from __future__ import annotations

import enum
from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class AccountRole(str, enum.Enum):
    student = "student"
    guardian = "guardian"
    teacher = "teacher"
    admin = "admin"


class LinkStatus(str, enum.Enum):
    pending = "pending"
    accepted = "accepted"
    rejected = "rejected"
    revoked = "revoked"


class Account(Base):
    """حساب مستخدم — الهوية جاية من Firebase والسيرفر بيخزّن الملف الشخصي."""

    __tablename__ = "accounts"

    id: Mapped[int] = mapped_column(primary_key=True)
    firebase_uid: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    role: Mapped[AccountRole] = mapped_column(
        Enum(AccountRole), default=AccountRole.student
    )

    display_name: Mapped[str] = mapped_column(String(160), default="")
    email: Mapped[str] = mapped_column(String(200), default="")
    phone: Mapped[str] = mapped_column(String(40), default="")

    # بيانات الطالب (فاضية لولي الأمر)
    country_code: Mapped[str] = mapped_column(String(2), default="EG")
    school_name: Mapped[str] = mapped_column(String(200), default="")
    grade_level: Mapped[int | None] = mapped_column(Integer, nullable=True)
    system_id: Mapped[str] = mapped_column(String(40), default="")
    school_language: Mapped[str] = mapped_column(String(20), default="arabic")
    track_id: Mapped[str] = mapped_column(String(40), default="")
    birth_date: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    last_seen_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # الروابط اللي الحساب ده طرف فيها
    guardian_links: Mapped[list["GuardianLink"]] = relationship(
        back_populates="guardian",
        foreign_keys="GuardianLink.guardian_id",
        cascade="all, delete-orphan",
    )
    student_links: Mapped[list["GuardianLink"]] = relationship(
        back_populates="student",
        foreign_keys="GuardianLink.student_id",
        cascade="all, delete-orphan",
    )


class LinkCode(Base):
    """كود مؤقت الطالب بيولّده ويدّيه لولي أمره عشان يطلب الربط.

    الكود قصير (٦ خانات) وبينتهي بعد وقت قصير، وبيتستخدم مرة واحدة —
    كده محدش يقدر يخمّنه أو يربط نفسه بطالب من غير علمه.
    """

    __tablename__ = "link_codes"

    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(String(12), unique=True, index=True)
    student_id: Mapped[int] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), index=True
    )

    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    student: Mapped[Account] = relationship()

    @property
    def is_usable(self) -> bool:
        if self.used_at is not None:
            return False
        expires = self.expires_at
        now = datetime.now(tz=expires.tzinfo) if expires.tzinfo else datetime.now()
        return expires > now


class GuardianLink(Base):
    """ربط بين ولي أمر وطالب، بصلاحيات الطالب هو اللي بيتحكم فيها."""

    __tablename__ = "guardian_links"
    __table_args__ = (
        UniqueConstraint("guardian_id", "student_id", name="uq_guardian_student"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    guardian_id: Mapped[int] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), index=True
    )
    student_id: Mapped[int] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), index=True
    )

    relation: Mapped[str] = mapped_column(String(20), default="other")
    status: Mapped[LinkStatus] = mapped_column(
        Enum(LinkStatus), default=LinkStatus.pending
    )

    # الصلاحيات مخزّنة كـ JSON نصي عشان تتوسّع من غير هجرة قاعدة بيانات
    permissions: Mapped[str] = mapped_column(Text, default="{}")

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    responded_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    guardian: Mapped[Account] = relationship(
        back_populates="guardian_links", foreign_keys=[guardian_id]
    )
    student: Mapped[Account] = relationship(
        back_populates="student_links", foreign_keys=[student_id]
    )
