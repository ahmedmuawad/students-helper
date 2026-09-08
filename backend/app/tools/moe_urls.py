"""استخراج بيانات الكتاب من رابط مكتبة الوزارة.

الروابط منتظمة، والمسار نفسه بيحمل السنة والمرحلة والصف والترم ونوع
الكتاب — وده أدق بكتير من تخمينها من العنوان العربي:

    .../2026_2027/Primary/Primary1/Term1/StudentBook/Arabic_language_prim1_t1.pdf
         السنة    المرحلة  الصف    الترم    النوع        اسم الملف
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from urllib.parse import unquote, urlparse

from app.tools import moe_patterns

# ---------------------------------------------------------------- المراحل

# اسم المرحلة في الرابط ← (أول صف فيها، عدد صفوفها)
_STAGES: dict[str, tuple[int, int]] = {
    "primary": (1, 6),
    "prim": (1, 6),
    "preparatory": (7, 3),
    "prep": (7, 3),
    "middle": (7, 3),
    "secondary": (10, 3),
    "sec": (10, 3),
}

# ---------------------------------------------------------------- الأنواع

_KINDS: dict[str, str] = {
    "studentbook": "textbook",
    "student_book": "textbook",
    "book": "textbook",
    "activitybook": "workbook",
    "workbook": "workbook",
    "teacherguide": "teacher_guide",
    "teacher_guide": "teacher_guide",
    "teachersguide": "teacher_guide",
    "revision": "revision",
    "exams": "exam",
}

# ---------------------------------------------------------------- المواد

# رموز أسماء الملفات ← معرّف المادة عندنا.
# الترتيب مهم: الأطول الأول عشان "english_language" ما تتطابقش كـ"english".
_FILE_SUBJECTS: list[tuple[str, str]] = [
    ("integrated_science", "integrated_science"),
    ("social_studies", "social"),
    ("islamic_religion", "religion_islamic"),
    ("christian_religion", "religion_christian"),
    ("cristian_religion", "religion_christian"),   # الخطأ الإملائي موجود فعلاً
    ("arabic_language", "arabic"),
    ("english_language", "english"),
    ("french_language", "french"),
    ("german_language", "german"),
    ("italian_language", "italian"),
    ("egyptian_history", "egyptian_history"),
    ("philosophy", "philosophy"),
    ("multi_disciplinary", "multidisciplinary"),
    ("professional", "skills"),
    ("vocational", "skills"),
    ("computer", "computer"),
    ("chemistry", "chemistry"),
    ("geography", "geography"),
    ("geology", "geology"),
    ("biology", "biology"),
    ("physics", "physics"),
    ("history", "history"),
    ("science", "science"),
    ("arabic", "arabic"),
    ("english", "english"),
    ("math", "math"),
    ("art", "art"),
    ("music", "music"),
]

# أسماء المواد اللي مش موجودة في moe_patterns
_EXTRA_SUBJECT_NAMES: dict[str, tuple[str, str, str]] = {
    "religion_islamic": ("التربية الدينية الإسلامية", "Islamic Education", "#00897B"),
    "religion_christian": ("التربية الدينية المسيحية", "Christian Education", "#00897B"),
    "multidisciplinary": ("متعدد التخصصات", "Multidisciplinary", "#5C6BC0"),
}


@dataclass
class BookRef:
    """كتاب متعرّف عليه من رابطه."""

    url: str
    academic_year: str          # 2026/2027
    grade_level: int            # 1..12
    stage: str                  # primary / preparatory / secondary
    term: int                   # 1 أو 2
    kind: str                   # textbook / workbook / teacher_guide ...
    subject_slug: str
    subject_name_ar: str
    subject_name_en: str
    subject_color: str

    # نسخة المدرسة: arabic أو languages أو both
    language: str
    title_ar: str

    @property
    def is_shared(self) -> bool:
        """المواد اللي بتتدرّس بالعربي في المدرستين (عربي، دين، دراسات)."""
        return self.language == "both"


def _clean_year(raw: str) -> str:
    """2026_2027 ← 2026/2027"""
    match = re.match(r"(\d{4})[_\-/](\d{4})", raw)
    return f"{match.group(1)}/{match.group(2)}" if match else raw


def _subject_from_filename(filename: str) -> str | None:
    lowered = filename.lower()
    for token, slug in _FILE_SUBJECTS:
        if token in lowered:
            return slug
    return None


def _language_from(filename: str, title: str, subject_slug: str) -> str:
    """
    نسخة المدرسة اللي الكتاب ده بتاعها.

    العربي والدين والدراسات الاجتماعية بتتدرّس بالعربية في مدارس العربي
    ومدارس اللغات على السواء، فبنعلّمها "both". أما الرياضيات والعلوم
    فليها نسختين، وبنميّزهم من اسم الملف (Math_Ar / Math_EN).
    """
    shared = {
        "arabic", "religion_islamic", "religion_christian", "social",
        "egyptian_history", "philosophy", "history", "geography",
        "french", "german", "italian", "skills", "art", "music",
    }
    if subject_slug in shared:
        return "both"

    lowered = filename.lower()
    if re.search(r"[_\-](en|eng|english)[_\-.]", lowered):
        return "languages"
    if re.search(r"[_\-](ar|arabic)[_\-.]", lowered):
        return "arabic"

    if moe_patterns.contains(title, "باللغه الانجليزيه"):
        return "languages"
    if moe_patterns.contains(title, "باللغه العربيه"):
        return "arabic"

    # الإنجليزي نفسه مادة مشتركة
    if subject_slug == "english":
        return "both"

    return "both"


def parse_url(url: str, title: str = "") -> BookRef | None:
    """يستخرج بيانات الكتاب من رابطه، أو None لو الشكل مش متعرّف عليه."""

    path = unquote(urlparse(url).path)
    if not path.lower().endswith(".pdf"):
        return None

    parts = [segment for segment in path.split("/") if segment]
    filename = parts[-1]
    lowered = [segment.lower() for segment in parts]

    # ---- السنة الدراسية ----
    academic_year = ""
    for segment in parts:
        if re.match(r"^\d{4}[_\-]\d{4}$", segment):
            academic_year = _clean_year(segment)
            break

    # ---- المرحلة والصف ----
    grade_level = 0
    stage = ""
    for segment in lowered:
        match = re.match(r"^([a-z]+?)\s*(\d{1,2})$", segment)
        if not match:
            continue
        name, number = match.group(1), int(match.group(2))
        if name in _STAGES:
            first, count = _STAGES[name]
            if 1 <= number <= count:
                grade_level = first + number - 1
                stage = (
                    "primary" if grade_level <= 6
                    else "preparatory" if grade_level <= 9
                    else "secondary"
                )
                break

    # لو المسار ما وضّحش الصف، نجرّب العنوان العربي
    if grade_level == 0 and title:
        detected = moe_patterns.detect_grade(title)
        if detected:
            grade_level, stage = detected

    if grade_level == 0:
        return None

    # ---- الترم ----
    term = 0
    for segment in lowered:
        match = re.match(r"^term\s*(\d)$", segment)
        if match:
            term = int(match.group(1))
            break
    if term == 0:
        match = re.search(r"[_\-]t(\d)[_\-.]", filename.lower())
        if match:
            term = int(match.group(1))
    if term == 0 and title:
        term = moe_patterns.detect_term(title) or 0
    if term == 0:
        term = 1

    # ---- النوع ----
    kind = "textbook"
    for segment in lowered:
        candidate = _KINDS.get(segment.replace(" ", ""))
        if candidate:
            kind = candidate
            break
    else:
        if title:
            kind = moe_patterns.detect_kind(title)

    # ---- المادة ----
    subject_slug = _subject_from_filename(filename)
    name_ar = name_en = ""
    color = "#2E7D91"

    if subject_slug and subject_slug in _EXTRA_SUBJECT_NAMES:
        name_ar, name_en, color = _EXTRA_SUBJECT_NAMES[subject_slug]
    elif subject_slug:
        for slug, ar, en, subject_color, _ in moe_patterns.SUBJECTS:
            if slug == subject_slug:
                name_ar, name_en, color = ar, en, subject_color
                break

    # لو اسم الملف ما وضّحش المادة، نجرّب العنوان العربي
    if not subject_slug and title:
        detected = moe_patterns.detect_subject(title)
        if detected:
            subject_slug, name_ar, name_en, color = detected

    if not subject_slug:
        return None

    if not name_ar:
        name_ar = subject_slug

    return BookRef(
        url=url,
        academic_year=academic_year,
        grade_level=grade_level,
        stage=stage,
        term=term,
        kind=kind,
        subject_slug=subject_slug,
        subject_name_ar=name_ar,
        subject_name_en=name_en,
        subject_color=color,
        language=_language_from(filename, title, subject_slug),
        title_ar=title.strip(),
    )
