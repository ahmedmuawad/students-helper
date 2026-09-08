"""إعدادات التكامل اللي بتتدخّل من لوحة التحكم.

المفاتيح الحسّاسة (AdMob، Google Play، Claude API) مش متكتوبة في الكود ولا
في التطبيق — بتتخزّن هنا وبتتقرأ وقت التشغيل، فتقدر تغيّرها من غير نشر
نسخة جديدة على المتجر.
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, DateTime, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class IntegrationSetting(Base):
    """إعداد واحد (مفتاح/قيمة) مع وصف عربي."""

    __tablename__ = "integration_settings"

    key: Mapped[str] = mapped_column(String(80), primary_key=True)
    value: Mapped[str] = mapped_column(Text, default="")

    # الإعدادات السرّية متتبعتش للتطبيق أبدًا — بتستخدم على السيرفر بس.
    is_secret: Mapped[bool] = mapped_column(Boolean, default=False)

    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


# تعريف كل إعداد: المفتاح، الاسم بالعربي، الشرح، سرّي؟، المجموعة
SETTING_DEFINITIONS: list[dict] = [
    # ----- AdMob -----
    {
        "key": "admob_enabled",
        "group": "AdMob",
        "label": "تفعيل الإعلانات",
        "hint": "لو مقفول، مفيش إعلانات هتظهر في التطبيق نهائيًا",
        "kind": "bool",
        "secret": False,
    },
    {
        "key": "admob_app_id_android",
        "group": "AdMob",
        "label": "App ID (أندرويد)",
        "hint": "ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY",
        "kind": "text",
        "secret": False,
    },
    {
        "key": "admob_app_id_ios",
        "group": "AdMob",
        "label": "App ID (iOS)",
        "hint": "ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY",
        "kind": "text",
        "secret": False,
    },
    {
        "key": "admob_banner_unit_android",
        "group": "AdMob",
        "label": "وحدة البانر (أندرويد)",
        "hint": "بتظهر أسفل قوايم الجدول والمهام",
        "kind": "text",
        "secret": False,
    },
    {
        "key": "admob_banner_unit_ios",
        "group": "AdMob",
        "label": "وحدة البانر (iOS)",
        "hint": "",
        "kind": "text",
        "secret": False,
    },
    {
        "key": "admob_interstitial_unit_android",
        "group": "AdMob",
        "label": "وحدة الإعلان البيني (أندرويد)",
        "hint": "بيظهر بعد إضافة عدة عناصر — مش أثناء المذاكرة",
        "kind": "text",
        "secret": False,
    },
    {
        "key": "admob_rewarded_unit_android",
        "group": "AdMob",
        "label": "وحدة إعلان المكافأة (أندرويد)",
        "hint": "شوف إعلان وحمّل ملزمة إضافية",
        "kind": "text",
        "secret": False,
    },
    # ----- Google Play Billing -----
    {
        "key": "play_package_name",
        "group": "Google Play",
        "label": "اسم الحزمة",
        "hint": "com.studentshelper.students_helper",
        "kind": "text",
        "secret": False,
    },
    {
        "key": "play_product_plus_monthly",
        "group": "Google Play",
        "label": "معرّف منتج: بلس شهري",
        "hint": "plus_monthly",
        "kind": "text",
        "secret": False,
    },
    {
        "key": "play_product_plus_annual",
        "group": "Google Play",
        "label": "معرّف منتج: بلس سنوي",
        "hint": "plus_annual",
        "kind": "text",
        "secret": False,
    },
    {
        "key": "play_product_pro_monthly",
        "group": "Google Play",
        "label": "معرّف منتج: برو شهري",
        "hint": "pro_monthly",
        "kind": "text",
        "secret": False,
    },
    {
        "key": "play_product_pro_annual",
        "group": "Google Play",
        "label": "معرّف منتج: برو سنوي",
        "hint": "pro_annual",
        "kind": "text",
        "secret": False,
    },
    {
        "key": "play_service_account_json",
        "group": "Google Play",
        "label": "مفتاح حساب الخدمة (JSON)",
        "hint": "بيتستخدم للتحقق من صحة الاشتراكات — سرّي، مبيوصلش للتطبيق",
        "kind": "secret_text",
        "secret": True,
    },
    # ----- Firebase -----
    {
        "key": "firebase_project_id",
        "group": "Firebase",
        "label": "معرّف المشروع",
        "hint": "بيتستخدم للتحقق من توكن تسجيل الدخول",
        "kind": "text",
        "secret": False,
    },
    # ----- الذكاء الاصطناعي -----
    {
        "key": "ai_enabled",
        "group": "الذكاء الاصطناعي",
        "label": "تفعيل مميزات الـ AI",
        "hint": "لو مقفول، باقة برو هتشتغل من غير مميزات الـ AI",
        "kind": "bool",
        "secret": False,
    },
    {
        "key": "anthropic_api_key",
        "group": "الذكاء الاصطناعي",
        "label": "مفتاح Claude API",
        "hint": "سرّي — بيتستخدم على السيرفر بس ومبيوصلش للتطبيق أبدًا",
        "kind": "secret",
        "secret": True,
    },
    {
        "key": "ai_model",
        "group": "الذكاء الاصطناعي",
        "label": "النموذج",
        "hint": "claude-haiku-4-5-20251001 أرخص · claude-sonnet-5 أدق",
        "kind": "text",
        "secret": False,
    },
]


def definitions_by_group() -> dict[str, list[dict]]:
    """يجمّع تعريفات الإعدادات حسب المجموعة للعرض في اللوحة."""
    grouped: dict[str, list[dict]] = {}
    for definition in SETTING_DEFINITIONS:
        grouped.setdefault(definition["group"], []).append(definition)
    return grouped


# المفاتيح اللي التطبيق مسموح له يقراها (الباقي سرّي)
PUBLIC_KEYS = {
    definition["key"]
    for definition in SETTING_DEFINITIONS
    if not definition["secret"]
}
