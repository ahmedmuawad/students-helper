"""بناء هيكل المناهج والصفوف والمواد.

الاستيراد من موقع الوزارة بينشئ الصفوف والمواد اللي ليها كتب بس. لكن
الطالب محتاج مواده كلها عشان يبني جدوله — حتى المواد اللي الوزارة
منشرتش كتبها لسه. الملف ده بيضمن إن كل صف موجود بمواده الكاملة.
"""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.models import Curriculum, EducationStage, Grade, Subject
from app.tools.moe_patterns import GRADE_NAMES_AR

# (المعرّف، عربي، إنجليزي، اللون، تُضاف للمجموع؟)
Sub = tuple[str, str, str, str, bool]

_ARABIC = ("arabic", "اللغة العربية", "Arabic", "#1E88E5", True)
_ENGLISH = ("english", "اللغة الإنجليزية", "English", "#43A047", True)
_MATH = ("math", "الرياضيات", "Mathematics", "#E53935", True)
_SCIENCE = ("science", "العلوم", "Science", "#8E24AA", True)
_SOCIAL = ("social", "الدراسات الاجتماعية", "Social Studies", "#F4511E", True)
_ICT = ("ict", "تكنولوجيا المعلومات والاتصالات", "ICT", "#546E7A", False)
_RELIGION_I = ("religion_islamic", "التربية الدينية الإسلامية",
               "Islamic Education", "#00897B", False)
_RELIGION_C = ("religion_christian", "التربية الدينية المسيحية",
               "Christian Education", "#00897B", False)
_SKILLS = ("skills", "المهارات المهنية", "Life Skills", "#546E7A", False)
_ART = ("art", "التربية الفنية", "Art", "#EC407A", False)
_MUSIC = ("music", "التربية الموسيقية", "Music", "#AB47BC", False)
_SECOND_LANG = ("second_language", "اللغة الثانية", "Second Language",
                "#3949AB", False)

# مواد كل مرحلة حسب الخطة الدراسية المصرية
_KINDERGARTEN: list[Sub] = [
    ("readiness", "الاستعداد للقراءة والكتابة", "Reading Readiness", "#1E88E5", False),
    ("numbers", "المفاهيم الرياضية", "Numeracy", "#E53935", False),
    ("discovery", "الاكتشاف", "Discovery", "#8E24AA", False),
    _ART, _MUSIC,
]

_PRIMARY_LOWER: list[Sub] = [   # الصفوف 1-3
    _ARABIC, _MATH, _ENGLISH, _RELIGION_I, _RELIGION_C, _SKILLS, _ART, _MUSIC,
]

_PRIMARY_UPPER: list[Sub] = [   # الصفوف 4-6
    _ARABIC, _MATH, _SCIENCE, _ENGLISH, _SOCIAL,
    _RELIGION_I, _RELIGION_C, _ICT, _ART, _MUSIC,
]

_PREPARATORY: list[Sub] = [     # الصفوف 7-9
    _ARABIC, _MATH, _SCIENCE, _ENGLISH, _SOCIAL,
    _RELIGION_I, _RELIGION_C, _ICT, _SECOND_LANG, _ART,
]

# الصف الأول الثانوي 2025/2026 حسب القرار الوزاري 234 لسنة 2025
_SECONDARY_10: list[Sub] = [
    _ARABIC, _ENGLISH,
    ("integrated_science", "العلوم المتكاملة", "Integrated Science", "#8E24AA", True),
    ("egyptian_history", "التاريخ المصري", "Egyptian History", "#F4511E", True),
    ("philosophy", "الفلسفة والمنطق", "Philosophy & Logic", "#6D4C41", True),
    _MATH,
    _RELIGION_I, _RELIGION_C, _SECOND_LANG,
    ("computer", "البرمجة وعلوم الحاسب", "Computer Science", "#546E7A", False),
]

# الصفين التاني والتالت الثانوي: المواد بتختلف حسب المسار، فبنحط الأساسي
_SECONDARY_UPPER: list[Sub] = [
    _ARABIC, _ENGLISH, _MATH,
    ("physics", "الفيزياء", "Physics", "#00ACC1", True),
    ("chemistry", "الكيمياء", "Chemistry", "#8E24AA", True),
    ("biology", "الأحياء", "Biology", "#7CB342", True),
    ("geology", "الجيولوجيا", "Geology", "#795548", True),
    ("history", "التاريخ", "History", "#F4511E", True),
    ("geography", "الجغرافيا", "Geography", "#FB8C00", True),
    ("philosophy", "الفلسفة والمنطق", "Philosophy & Logic", "#6D4C41", True),
    ("psychology", "علم النفس والاجتماع", "Psychology & Sociology", "#7E57C2", True),
    _RELIGION_I, _RELIGION_C, _SECOND_LANG,
]


def subjects_for(level: int) -> list[Sub]:
    if level <= 0:
        return _KINDERGARTEN
    if level <= 3:
        return _PRIMARY_LOWER
    if level <= 6:
        return _PRIMARY_UPPER
    if level <= 9:
        return _PREPARATORY
    if level == 10:
        return _SECONDARY_10
    return _SECONDARY_UPPER


def stage_for(level: int) -> EducationStage:
    if level <= 0:
        return EducationStage.kindergarten
    if level <= 6:
        return EducationStage.primary
    if level <= 9:
        return EducationStage.preparatory
    return EducationStage.secondary


# المناهج اللي بنجهّزها
CURRICULA = [
    ("egyptGeneral", "arabic", "المنهج المصري - عربي",
     "Egyptian Curriculum - Arabic"),
    ("egyptGeneral", "languages", "المنهج المصري - لغات",
     "Egyptian Curriculum - Languages"),
    ("egyptBaccalaureate", "arabic", "البكالوريا المصرية - عربي",
     "Egyptian Baccalaureate - Arabic"),
    ("egyptBaccalaureate", "languages", "البكالوريا المصرية - لغات",
     "Egyptian Baccalaureate - Languages"),
]

# البكالوريا للثانوي بس، والتعليم العام لباقي المراحل
_LEVELS_FOR_SYSTEM = {
    "egyptGeneral": list(range(-1, 10)),      # رياض أطفال حتى الإعدادي
    "egyptBaccalaureate": [10, 11, 12],       # الثانوي
}


def build(db: Session, academic_year: str = "2026/2027") -> dict[str, int]:
    """ينشئ المناهج والصفوف والمواد الناقصة. آمن للتشغيل المتكرر."""

    created = {"curricula": 0, "grades": 0, "subjects": 0}

    for system_id, language, name_ar, name_en in CURRICULA:
        curriculum = (
            db.query(Curriculum)
            .filter(
                Curriculum.country_code == "EG",
                Curriculum.system_id == system_id,
                Curriculum.language == language,
                Curriculum.academic_year == academic_year,
            )
            .one_or_none()
        )
        if curriculum is None:
            curriculum = Curriculum(
                country_code="EG",
                system_id=system_id,
                language=language,
                academic_year=academic_year,
                name_ar=name_ar,
                name_en=name_en,
                is_published=True,
            )
            db.add(curriculum)
            db.flush()
            created["curricula"] += 1
        elif not curriculum.is_published:
            curriculum.is_published = True

        for level in _LEVELS_FOR_SYSTEM[system_id]:
            grade = (
                db.query(Grade)
                .filter(Grade.curriculum_id == curriculum.id, Grade.level == level)
                .one_or_none()
            )
            if grade is None:
                grade = Grade(
                    curriculum_id=curriculum.id,
                    level=level,
                    stage=stage_for(level),
                    name_ar=GRADE_NAMES_AR.get(level, f"الصف {level}"),
                    name_en=f"Grade {level}" if level > 0 else "Kindergarten",
                )
                db.add(grade)
                db.flush()
                created["grades"] += 1

            existing = {
                slug
                for (slug,) in db.query(Subject.slug)
                .filter(Subject.grade_id == grade.id)
                .all()
            }

            for order, (slug, ar, en, color, counts) in enumerate(
                subjects_for(level)
            ):
                if slug in existing:
                    continue
                db.add(
                    Subject(
                        grade_id=grade.id,
                        slug=slug,
                        name_ar=ar,
                        name_en=en,
                        color=color,
                        counts_toward_total=counts,
                        sort_order=order,
                    )
                )
                created["subjects"] += 1

    db.commit()
    return created
