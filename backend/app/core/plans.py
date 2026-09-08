"""تعريف الباقات وحدود كل باقة — مصدر الحقيقة الوحيد للتسعير.

التطبيق بيقرأ الحدود دي من السيرفر، فتقدر تغيّر الأسعار والحدود من غير
ما تنزّل نسخة جديدة على المتجر.
"""

from __future__ import annotations

from app.models.billing import PlanTier

# الأسعار بالجنيه المصري
PLAN_PRICES = {
    PlanTier.free: {"monthly": 0, "annual": 0},
    PlanTier.plus: {"monthly": 49, "annual": 399},
    PlanTier.pro: {"monthly": 149, "annual": 1299},
}

# حدود الاستخدام لكل باقة. القيمة None تعني بلا حدود.
PLAN_LIMITS = {
    PlanTier.free: {
        "ads": True,
        "offline_books": 1,
        "extra_materials_per_month": 3,   # ملازم ومراجعات
        "linked_children": 1,
        "themes": False,
        "widgets": False,
        "cloud_backup": False,
        "ai_credits_per_month": 0,
    },
    PlanTier.plus: {
        "ads": False,
        "offline_books": None,
        "extra_materials_per_month": None,
        "linked_children": None,
        "themes": True,
        "widgets": True,
        "cloud_backup": True,
        "ai_credits_per_month": 0,
    },
    PlanTier.pro: {
        "ads": False,
        "offline_books": None,
        "extra_materials_per_month": None,
        "linked_children": None,
        "themes": True,
        "widgets": True,
        "cloud_backup": True,
        "ai_credits_per_month": 300,
    },
}

# تكلفة كل عملية ذكاء اصطناعي بالرصيد.
# الأرقام مبنية على التكلفة الفعلية للنموذج: العمليات اللي بتقرأ صورة
# أغلى بكتير من اللي بتقرأ نص.
AI_CREDIT_COSTS = {
    "timetable_scan": 10,   # تصوير الجدول وتحويله لبيانات
    "explain": 2,           # اشرحلي السؤال ده
    "flashcards": 3,        # توليد بطاقات مراجعة من درس
    "exam": 5,              # توليد امتحان تجريبي
    "plan": 3,              # تحسين خطة المذاكرة
    "summarize": 4,         # تلخيص فصل من كتاب
}

# سن الحماية: تحت السن ده الإعلانات لازم تكون غير مخصّصة (COPPA
# وسياسة Google Play للعائلات). التطبيق بيسجّل تاريخ الميلاد أصلاً.
CHILD_AGE_THRESHOLD = 13


def limits_for(tier: PlanTier) -> dict:
    return PLAN_LIMITS.get(tier, PLAN_LIMITS[PlanTier.free])


def allows(tier: PlanTier, feature: str) -> bool:
    """هل الباقة دي بتسمح بالميزة؟ (للمميزات المنطقية فقط)"""
    value = limits_for(tier).get(feature)
    return bool(value) if isinstance(value, bool) else value is None


def quota(tier: PlanTier, feature: str) -> int | None:
    """السقف العددي للميزة، أو None لو بلا حدود."""
    return limits_for(tier).get(feature)


def ad_personalization_allowed(age: int | None) -> bool:
    """الإعلانات المخصّصة مسموحة فقط فوق سن الحماية.

    لو السن غير معروف بنفترض الأسوأ ونمنع التخصيص — أأمن قانونيًا.
    """
    if age is None:
        return False
    return age >= CHILD_AGE_THRESHOLD
