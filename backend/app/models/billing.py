"""جداول الاشتراكات والفوترة."""

from __future__ import annotations

import enum
from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class PlanTier(str, enum.Enum):
    """باقات الاشتراك."""

    free = "free"    # مجاني بإعلانات
    plus = "plus"    # بدون إعلانات + مميزات إضافية
    pro = "pro"      # كل حاجة + مميزات الذكاء الاصطناعي


class SubscriptionStatus(str, enum.Enum):
    trialing = "trialing"
    active = "active"
    grace = "grace"          # فشل الدفع لكن لسه في مهلة
    expired = "expired"
    cancelled = "cancelled"


class PaymentProvider(str, enum.Enum):
    google_play = "google_play"
    app_store = "app_store"
    # الدفع من الويب للسوق المصري: فوري / محافظ / إنستاباي
    fawry = "fawry"
    wallet = "wallet"
    instapay = "instapay"
    manual = "manual"


class Subscription(Base):
    """اشتراك حساب في باقة.

    ولي الأمر يقدر يدفع لابنه — عشان كده فيه payer_id منفصل عن account_id.
    ده مهم في السوق المصري لأن الطالب غالبًا معندوش وسيلة دفع.
    """

    __tablename__ = "subscriptions"

    id: Mapped[int] = mapped_column(primary_key=True)

    # صاحب المميزات (الطالب)
    account_id: Mapped[int] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), index=True
    )
    # اللي دفع فعليًا (ممكن يكون ولي الأمر)
    payer_id: Mapped[int | None] = mapped_column(
        ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True
    )

    tier: Mapped[PlanTier] = mapped_column(Enum(PlanTier), default=PlanTier.free)
    status: Mapped[SubscriptionStatus] = mapped_column(
        Enum(SubscriptionStatus), default=SubscriptionStatus.active
    )
    provider: Mapped[PaymentProvider] = mapped_column(
        Enum(PaymentProvider), default=PaymentProvider.manual
    )

    # معرّف الاشتراك عند مزوّد الدفع (للتحقق من الويب هوك)
    provider_ref: Mapped[str] = mapped_column(String(200), default="")

    is_annual: Mapped[bool] = mapped_column(Boolean, default=False)
    price_egp: Mapped[float] = mapped_column(Numeric(10, 2), default=0)

    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    trial_ends_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    cancelled_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    account = relationship("Account", foreign_keys=[account_id])
    payer = relationship("Account", foreign_keys=[payer_id])

    @property
    def is_valid(self) -> bool:
        """هل الاشتراك ساري دلوقتي؟"""
        if self.status in (SubscriptionStatus.expired, SubscriptionStatus.cancelled):
            return False
        expires = self.expires_at
        if expires is None:
            return True
        now = datetime.now(tz=expires.tzinfo) if expires.tzinfo else datetime.now()
        return expires > now


class AiUsage(Base):
    """استهلاك رصيد الذكاء الاصطناعي.

    كل عملية AI ليها تكلفة حقيقية، فبنعدّها ونحدّد سقف شهري لكل باقة
    بدل ما تبقى مفتوحة وتاكل الأرباح.
    """

    __tablename__ = "ai_usage"

    id: Mapped[int] = mapped_column(primary_key=True)
    account_id: Mapped[int] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), index=True
    )

    # نوع العملية: timetable_scan, explain, flashcards, plan, summarize
    operation: Mapped[str] = mapped_column(String(40), index=True)
    credits: Mapped[int] = mapped_column(Integer, default=1)

    input_tokens: Mapped[int] = mapped_column(Integer, default=0)
    output_tokens: Mapped[int] = mapped_column(Integer, default=0)
    notes: Mapped[str] = mapped_column(Text, default="")

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )
