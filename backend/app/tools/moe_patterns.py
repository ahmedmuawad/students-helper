"""التعرّف على الصف والترم والمادة من النصوص العربية.

الأنماط دي بتغطي الصيغ اللي بتستخدمها المواقع التعليمية المصرية، وسهل
تزوّد عليها لو ظهرت صيغة جديدة.
"""

from __future__ import annotations

import re
import unicodedata

# ---------------------------------------------------------------- التطبيع

_ARABIC_DIACRITICS = re.compile(r"[ً-ْـ]")


def normalize(text: str) -> str:
    """يوحّد شكل النص العربي عشان المطابقة تنجح مع اختلاف الكتابة."""
    if not text:
        return ""
    text = unicodedata.normalize("NFKC", text)
    text = _ARABIC_DIACRITICS.sub("", text)          # تشكيل وتطويل
    text = text.replace("أ", "ا").replace("إ", "ا").replace("آ", "ا")
    text = text.replace("ى", "ي").replace("ة", "ه")
    text = re.sub(r"\s+", " ", text)
    return text.strip()


# ---------------------------------------------------------------- المطابقة

# العربية بتلزق البادئات بالكلمة ("للثالث"، "بالرياضيات")، فالمطابقة
# النصية المباشرة بتفشل. بنسمح بالبادئات المعروفة قبل الكلمة، وفي نفس
# الوقت نمنع المطابقة في وسط كلمة تانية (زي "دين" جوه "المدينة").
# البادئات المحتملة: و + حرف جر + أداة تعريف.
# لاحظ "لل" (زي "للثالث") — ألف "ال" بتتحذف بعد لام الجر، فلازم نسمح
# بـ"ل" مفردة كأداة تعريف كمان.
# العناوين بتفصل الأجزاء بشرطة من غير مسافة ("...أجنبية أولى-كراسة
# التدريبات")، فلازم نقبل الشرطة وعلامات الفصل كبداية كلمة زي المسافة.
_PREFIX = r"(?:^|[\s\-–—/,،(])(?:و)?(?:ب|ك|ف|ل)?(?:ال|ل)?"
_SUFFIX = r"(?=\s|$|[^\u0621-\u064A])"

_matcher_cache: dict[str, re.Pattern] = {}


def _matcher(needle: str) -> re.Pattern:
    """يبني تعبيرًا نمطيًا للكلمة مع السماح بالبادئات العربية."""
    if needle in _matcher_cache:
        return _matcher_cache[needle]

    core = normalize(needle)
    # نشيل "ال" من أول الكلمة عشان البادئة تتولى المطابقة
    if core.startswith("ال") and len(core) > 3:
        core = core[2:]

    pattern = re.compile(_PREFIX + re.escape(core) + _SUFFIX, re.IGNORECASE)
    _matcher_cache[needle] = pattern
    return pattern


def contains(text: str, needle: str) -> bool:
    """هل النص بيحتوي الكلمة (مع مراعاة البادئات العربية)؟"""
    return _matcher(needle).search(normalize(text).lower()) is not None


def strip_language_suffix(text: str) -> str:
    """يشيل لاحقة لغة التدريس من عنوان الكتاب.

    الوزارة بتسمّي الكتب "الرياضيات باللغة العربية" و"العلوم باللغة
    الفرنسية". من غير ما نشيل اللاحقة دي، المطابقة بتلقى "اللغة العربية"
    وتحسبها هي المادة — لأنها أطول من "الرياضيات". اللاحقة بتتشال قبل
    تحديد المادة بس؛ لغة النسخة نفسها بتتحدد منها في مكان تاني.
    """
    return re.sub(
        r"\s*ب\s*ال?لغ[هة]\s+\S+",
        " ",
        normalize(text),
    ).strip()


# ---------------------------------------------------------------- الصفوف

# ترتيب مهم: الصيغ الأطول الأول عشان "الاول الثانوي" ما تتطابقش كـ"الاول"
_GRADE_PATTERNS: list[tuple[int, str, list[str]]] = [
    # رياض الأطفال قبل الابتدائي — بنرقّمها 0 و -1 عشان الابتدائي يفضل من 1
    # الموقع بيسمّيها "مستوى أول" و"مستوى ثان" — من غير كلمة "الصف"
    (0,  "kindergarten", ["مستوي ثان", "مستوي ثاني", "المستوي الثاني",
                          "الثاني كي جي", "كي جي 2", "رياض الاطفال الثاني",
                          "kg2"]),
    (-1, "kindergarten", ["مستوي اول", "المستوي الاول",
                          "الاول كي جي", "كي جي 1", "رياض الاطفال الاول",
                          "kg1"]),
    (1,  "primary",     ["الاول الابتدائي", "اولي ابتدائي", "الصف الاول الابتدائي", "grade 1", "primary 1"]),
    (2,  "primary",     ["الثاني الابتدائي", "تانيه ابتدائي", "grade 2", "primary 2"]),
    (3,  "primary",     ["الثالث الابتدائي", "تالته ابتدائي", "grade 3", "primary 3"]),
    (4,  "primary",     ["الرابع الابتدائي", "رابعه ابتدائي", "grade 4", "primary 4"]),
    (5,  "primary",     ["الخامس الابتدائي", "خامسه ابتدائي", "grade 5", "primary 5"]),
    (6,  "primary",     ["السادس الابتدائي", "سادسه ابتدائي", "grade 6", "primary 6"]),
    (7,  "preparatory", ["الاول الاعدادي", "اولي اعدادي", "grade 7", "prep 1"]),
    (8,  "preparatory", ["الثاني الاعدادي", "تانيه اعدادي", "grade 8", "prep 2"]),
    (9,  "preparatory", ["الثالث الاعدادي", "تالته اعدادي", "grade 9", "prep 3"]),
    (10, "secondary",   ["الاول الثانوي", "اولي ثانوي", "grade 10", "secondary 1"]),
    (11, "secondary",   ["الثاني الثانوي", "تانيه ثانوي", "grade 11", "secondary 2"]),
    (12, "secondary",   ["الثالث الثانوي", "تالته ثانوي", "grade 12", "secondary 3"]),
]

GRADE_NAMES_AR = {
    -1: "المستوى الأول (رياض أطفال)", 0: "المستوى الثاني (رياض أطفال)",
    1: "الأول الابتدائي", 2: "الثاني الابتدائي", 3: "الثالث الابتدائي",
    4: "الرابع الابتدائي", 5: "الخامس الابتدائي", 6: "السادس الابتدائي",
    7: "الأول الإعدادي", 8: "الثاني الإعدادي", 9: "الثالث الإعدادي",
    10: "الأول الثانوي", 11: "الثاني الثانوي", 12: "الثالث الثانوي",
}


def detect_grade(text: str) -> tuple[int, str] | None:
    """يرجّع (رقم الصف، المرحلة) أو None."""
    for level, stage, needles in _GRADE_PATTERNS:
        for needle in needles:
            if contains(text, needle):
                return level, stage
    return None


# ---------------------------------------------------------------- الترم

def detect_term(text: str) -> int | None:
    first = ["الترم الاول", "ترم اول", "الفصل الدراسي الاول", "term 1", "first term"]
    second = ["الترم الثاني", "ترم تاني", "ترم ثاني", "الفصل الدراسي الثاني",
              "term 2", "second term"]
    # الترم الثاني الأول عشان "الفصل الدراسي الثاني" ما تتطابقش كـ"الأول"
    for needle in second:
        if contains(text, needle):
            return 2
    for needle in first:
        if contains(text, needle):
            return 1
    return None


# ---------------------------------------------------------------- المواد

# (المعرّف، الاسم بالعربي، الاسم بالإنجليزي، اللون، صيغ البحث)
SUBJECTS: list[tuple[str, str, str, str, list[str]]] = [
    ("arabic", "اللغة العربية", "Arabic", "#1E88E5",
     ["اللغه العربيه", "لغه عربيه", "عربي", "arabic"]),
    ("math", "الرياضيات", "Mathematics", "#E53935",
     ["الرياضيات", "رياضيات", "math", "mathematics"]),
    ("science", "العلوم", "Science", "#8E24AA",
     ["العلوم", "علوم", "science"]),
    ("integrated_science", "العلوم المتكاملة", "Integrated Science", "#8E24AA",
     ["العلوم المتكامله", "science integrated"]),
    ("english", "اللغة الإنجليزية", "English", "#43A047",
     ["اللغه الانجليزيه", "انجليزي", "english"]),
    ("social", "الدراسات الاجتماعية", "Social Studies", "#F4511E",
     ["الدراسات الاجتماعيه", "دراسات", "social studies"]),
    ("egyptian_history", "التاريخ المصري", "Egyptian History", "#F4511E",
     ["التاريخ المصري", "تاريخ مصر"]),
    ("philosophy", "الفلسفة والمنطق", "Philosophy & Logic", "#6D4C41",
     ["الفلسفه والمنطق", "فلسفه", "منطق"]),
    # الدين الإسلامي والمسيحي كتابين مختلفين — الطالب بيختار بتاعه.
    # الصيغ الأطول بتتطابق الأول، فدول بيسبقوا "التربية الدينية" العامة.
    # أسماء الملفات إنجليزي وفيها أخطاء إملائية من الموقع نفسه
    # (Cristian, reliogion) — بنسجّلها زي ما هي عشان الرابط لوحده يكفي.
    ("religion_islamic", "التربية الدينية الإسلامية", "Islamic Education",
     "#00897B", ["التربيه الدينيه الاسلاميه", "التربيه الاسلاميه",
                 "الدين الاسلامي", "تربيه اسلاميه",
                 "islamic", "eslamic"]),
    ("religion_christian", "التربية الدينية المسيحية", "Christian Education",
     "#00897B", ["التربيه الدينيه المسيحيه", "التربيه المسيحيه",
                 "الدين المسيحي", "تربيه مسيحيه",
                 "christian", "cristian"]),
    ("religion", "التربية الدينية", "Religious Education", "#00897B",
     ["التربيه الدينيه", "دين"]),
    # الموقع بيسمّيها "تكنولوجيا المعلومات والاتصالات" في الابتدائي والثانوي
    # و"الكمبيوتر و..." في الإعدادي — بنوحّدها على الاسم الأقصر.
    ("ict", "تكنولوجيا المعلومات والاتصالات", "ICT", "#546E7A",
     ["الكمبيوتر وتكنولوجيا المعلومات والاتصالات",
      "تكنولوجيا المعلومات والاتصالات", "تكنولوجيا المعلومات", "ict"]),
    # مواد الأنشطة في المرحلة الإعدادية
    ("theatre", "التربية المسرحية", "Drama", "#D81B60",
     ["التربيه المسرحيه", "المسرح"]),
    ("library", "المكتبات ومهارات البحث", "Library & Research Skills",
     "#00838F", ["المكتبات ومهارات البحث", "المكتبات"]),
    ("media", "الإعلام التربوي", "Educational Media", "#5E35B1",
     ["الاعلام التربوي"]),
    ("industry", "مهارات الصناعة وريادة الأعمال",
     "Industry & Entrepreneurship", "#8D6E63",
     ["مهارات الصناعه وريادة الاعمال", "مهارات الصناعه"]),
    ("agriculture", "مهارات الزراعة وريادة الأعمال",
     "Agriculture & Entrepreneurship", "#689F38",
     ["مهارات الزراعه وريادة الاعمال", "مهارات الزراعه"]),
    ("computer", "الحاسب الآلي", "Computer", "#546E7A",
     ["الحاسب الالي", "الكمبيوتر", "computer"]),
    # ----- مواد المرحلة الثانوية -----
    # الأطول بيتطابق الأول، فـ"الرياضيات البحتة" بتسبق "الرياضيات"
    ("pure_math", "الرياضيات البحتة", "Pure Mathematics", "#E53935",
     ["الرياضيات البحته"]),
    ("applied_math", "الرياضيات التطبيقية", "Applied Mathematics", "#EF6C00",
     ["الرياضيات التطبيقيه"]),
    ("math_applications", "تطبيقات الرياضيات", "Mathematics Applications",
     "#EF6C00", ["تطبيقات الرياضيات"]),
    ("general_math", "الرياضيات العامة", "General Mathematics", "#E53935",
     ["الرياضيات العامه"]),
    ("statistics", "الإحصاء", "Statistics", "#00838F", ["الاحصاء"]),
    ("ai_programming", "البرمجة والذكاء الاصطناعي",
     "Programming & AI", "#3949AB",
     ["البرمجه والذكاء الاصطناعي", "الذكاء الاصطناعي"]),
    ("dev_geography", "جغرافيا التنمية", "Development Geography", "#FB8C00",
     ["جغرافيا التنميه"]),
    ("political_geography", "الجغرافيا السياسية", "Political Geography",
     "#FB8C00", ["الجغرافيا السياسيه"]),
    ("psychology", "علم النفس والاجتماع", "Psychology & Sociology", "#7E57C2",
     ["علم النفس والاجتماع", "علم النفس"]),
    ("citizenship", "المواطنة وحقوق الإنسان", "Citizenship & Human Rights",
     "#0277BD", ["المواطنه وحقوق الانسان", "المواطنه"]),
    ("national_education", "التربية الوطنية", "National Education", "#0277BD",
     ["التربيه الوطنيه"]),
    ("spanish", "اللغة الإسبانية", "Spanish", "#3949AB",
     ["الاسبانيه", "espanol"]),
    ("physics", "الفيزياء", "Physics", "#00ACC1",
     ["الفيزياء", "physics"]),
    ("chemistry", "الكيمياء", "Chemistry", "#8E24AA",
     ["الكيمياء", "chemistry"]),
    ("biology", "الأحياء", "Biology", "#7CB342",
     ["الاحياء", "biology"]),
    ("geology", "الجيولوجيا", "Geology", "#795548",
     ["الجيولوجيا", "علوم البيئه"]),
    ("history", "التاريخ", "History", "#F4511E", ["التاريخ", "history"]),
    ("geography", "الجغرافيا", "Geography", "#FB8C00", ["الجغرافيا", "geography"]),
    ("french", "اللغة الفرنسية", "French", "#3949AB", ["الفرنسيه", "french"]),
    ("german", "اللغة الألمانية", "German", "#3949AB", ["الالمانيه", "german"]),
    ("italian", "اللغة الإيطالية", "Italian", "#3949AB", ["الايطاليه", "italian"]),
    ("art", "التربية الفنية", "Art", "#EC407A", ["التربيه الفنيه", "رسم"]),
    ("music", "التربية الموسيقية", "Music", "#AB47BC", ["التربيه الموسيقيه"]),
    ("skills", "المهارات المهنية", "Life Skills", "#546E7A",
     ["المهارات المهنيه", "مهارات"]),
]


def detect_subject(text: str) -> tuple[str, str, str, str] | None:
    """يرجّع (المعرّف، الاسم عربي، الاسم إنجليزي، اللون) أو None.

    بنختار **أطول كلمة اتطابقت فعلاً**، مش أطول كلمة مسجّلة. الفرق مهم:
    "الرياضيات - الثاني الابتدائي - عربي" فيه "الرياضيات" (٩ حروف) و"عربي"
    (٤ حروف). لو رتّبنا بالطول المسجّل، مادة اللغة العربية بتتفحص الأول
    (لأن عندها "اللغه العربيه" ١٣ حرف) وبتكسب بـ"عربي" — فكتاب الرياضيات
    بيتسجّل لغة عربية. بالمطابقة الفعلية "الرياضيات" هي اللي بتكسب.
    """
    # لاحقة "باللغة كذا" بتشوّش المطابقة، فبنشيلها الأول
    cleaned = strip_language_suffix(text)

    best: tuple[int, tuple[str, str, str, str]] | None = None
    for slug, name_ar, name_en, color, needles in SUBJECTS:
        for needle in needles:
            if not contains(cleaned, needle):
                continue
            score = len(normalize(needle))
            if best is None or score > best[0]:
                best = (score, (slug, name_ar, name_en, color))

    return best[1] if best else None


# ---------------------------------------------------------------- النوع

def detect_kind(text: str) -> str:
    """يخمّن نوع الملف من نصه."""
    if any(contains(text, n) for n in ["دليل المعلم", "دليل معلم", "teacher guide"]):
        return "teacher_guide"
    if any(contains(text, n) for n in ["مراجعه", "مراجعات", "revision"]):
        return "revision"
    if any(contains(text, n) for n in ["امتحان", "امتحانات", "نماذج", "اختبار", "exam"]):
        return "exam"
    if any(contains(text, n) for n in ["ملزمه", "مذكره", "booklet"]):
        return "booklet"
    if any(contains(text, n) for n in
           ["كراسه التدريبات", "كراسه تدريبات", "انشطه", "النشاط", "workbook"]):
        return "workbook"
    # القصة كتاب مستقل جنب كتاب الطالب في العربي والإنجليزي
    if any(contains(text, n) for n in ["القصه", "قصه", "story"]):
        return "story"
    return "textbook"


def detect_language(text: str) -> str:
    """يميّز نسخة اللغات عن النسخة العربية."""
    if any(contains(text, n) for n in ["لغات", "languages", "experimental"]):
        return "languages"
    return "arabic"
