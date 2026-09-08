"""اختبارات استخراج بيانات كتب الوزارة.

الملف المرجعي fixtures/moe_primary_t1.json مأخوذ من صفحة المكتبة الحقيقية
(الابتدائي، الترم الأول) — بأسماء ملفاتها الفوضوية وأخطائها الإملائية.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.tools.moe_crawl import parse_cards
from app.tools.moe_patterns import (
    contains,
    detect_grade,
    detect_kind,
    detect_subject,
    detect_term,
    strip_language_suffix,
)
from app.tools.moe_urls import parse_url

FIXTURES = Path(__file__).parent / "fixtures"

# الناتج المتوقع لكل عنوان في بطاقات الموقع
EXPECTED: dict[str, tuple[str, str]] = {
    "اللغة العربية": ("اللغة العربية", "both"),
    "اللغة الإنجليزية-لغة أجنبية أولى": ("اللغة الإنجليزية", "both"),
    "الرياضيات باللغة العربية": ("الرياضيات", "arabic"),
    "الرياضيات باللغة الإنجليزية": ("الرياضيات", "languages"),
    "الرياضيات باللغة الفرنسية": ("الرياضيات", "languages"),
    "التربية الدينية الإسلامية": ("التربية الدينية الإسلامية", "both"),
    "التربية الدينية المسيحية": ("التربية الدينية المسيحية", "both"),
    "العلوم باللغة العربية": ("العلوم", "arabic"),
    "العلوم باللغة الإنجليزية": ("العلوم", "languages"),
    "العلوم باللغة الفرنسية": ("العلوم", "languages"),
    "الدراسات الاجتماعية": ("الدراسات الاجتماعية", "both"),
    "تكنولوجيا المعلومات والاتصالات باللغة العربية": (
        "تكنولوجيا المعلومات والاتصالات",
        "arabic",
    ),
}


def load_books() -> list[dict]:
    return json.loads((FIXTURES / "moe_primary_t1.json").read_text(encoding="utf-8"))


def card_title(book: dict) -> str:
    return f"{book['subject']} - {book['grade']} - {book['term']} - {book['kind']}"


@pytest.mark.parametrize("book", load_books(), ids=lambda b: b["url"].split("/")[-1])
def test_every_real_book_parses(book: dict) -> None:
    """كل كتاب في الصفحة الحقيقية بيتحلّل صح."""
    ref = parse_url(book["url"], card_title(book))
    assert ref is not None, "لم يُتعرّف على الكتاب"

    expected_subject, expected_language = EXPECTED[book["subject"]]
    assert ref.grade_level == book["expect_grade"]
    assert ref.term == 1
    assert ref.kind == "textbook"
    assert ref.subject_name_ar == expected_subject
    assert ref.language == expected_language
    assert ref.academic_year == "2026/2027"


def test_subject_beats_language_suffix() -> None:
    """اسم المادة أهم من لاحقة لغة التدريس.

    "الرياضيات باللغة العربية" مادتها الرياضيات — من غير معالجة اللاحقة
    كانت بتتقرا "اللغة العربية" لأنها أطول.
    """
    assert strip_language_suffix("الرياضيات باللغة العربية") == "الرياضيات"
    assert detect_subject("الرياضيات باللغة العربية")[1] == "الرياضيات"
    assert detect_subject("العلوم باللغة الفرنسية")[1] == "العلوم"
    # المادة اللي اسمها لغة فعلاً بتفضل زي ما هي
    assert detect_subject("اللغة العربية")[1] == "اللغة العربية"


def test_arabic_prefixes_are_matched() -> None:
    """البادئات الملزوقة بالكلمة (لل، بال) لازم تتطابق."""
    assert detect_grade("للثالث الثانوى")[0] == 12
    assert detect_subject("بالرياضيات")[1] == "الرياضيات"
    # ومن غير مطابقة جوه كلمة تانية
    assert not contains("المدينة المنورة", "دين")


def test_religion_variants_are_separate() -> None:
    """الدين الإسلامي والمسيحي مادتين مختلفتين."""
    assert detect_subject("التربية الدينية الإسلامية")[0] == "religion_islamic"
    assert detect_subject("التربية الدينية المسيحية")[0] == "religion_christian"


def test_term_and_kind_detection() -> None:
    assert detect_term("الفصل الدراسى الأول") == 1
    assert detect_term("الفصل الدراسى الثاني") == 2
    assert detect_kind("دليل المعلم") == "teacher_guide"
    assert detect_kind("المراجعة النهائية") == "revision"
    assert detect_kind("كتاب الطالب") == "textbook"


def test_parse_cards_reads_the_real_markup() -> None:
    """قراءة بطاقة الكتاب بشكلها الحقيقي على الموقع."""
    html = """
    <article class="book-card"><div class="book-card-content">
      <h3>العلوم باللغة الفرنسية</h3>
      <p>الصف الخامس الإبتدائى</p>
      <p>الفصل الدراسى الأول</p>
      <p>كتاب الطالب</p>
      <a class="book-link" href="https://example.com/Science_FR_prim5_TR1.pdf">فتح الكتاب</a>
    </div></article>
    """
    cards = parse_cards(html)
    assert len(cards) == 1
    url, title = cards[0]
    assert url.endswith("Science_FR_prim5_TR1.pdf")
    # العنوان بيجمع المادة والصف والترم والنوع
    assert "العلوم باللغة الفرنسية" in title
    assert "الصف الخامس الإبتدائى" in title


# --------------------------------------------------------------------------
# عيّنات من المراحل الأربعة (رياض أطفال · ابتدائي · إعدادي · ثانوي)
# --------------------------------------------------------------------------


def load_all_stages() -> list[dict]:
    return json.loads(
        (FIXTURES / "moe_all_stages.json").read_text(encoding="utf-8")
    )


@pytest.mark.parametrize(
    "book", load_all_stages(), ids=lambda b: b["url"].split("/")[-1]
)
def test_all_stages_parse(book: dict) -> None:
    """عيّنات حقيقية من كل مرحلة، بمساراتها وأسمائها زي ما هي."""
    ref = parse_url(book["url"], book["title"])
    assert ref is not None, "لم يُتعرّف على الكتاب"
    assert ref.grade_level == book["grade"]
    assert ref.subject_name_ar == book["subject"]
    assert ref.language == book["language"]
    assert ref.kind == book["kind"]


def test_misspelled_stage_paths() -> None:
    """الموقع كاتب أسماء المراحل غلط في المسار — لازم نتعرّف عليها."""
    base = "https://x/2026_2027"
    title = "اللغة العربية - الفصل الدراسى الأول"

    # Prepratory بدل Preparatory
    prep = parse_url(f"{base}/Prepratory/Prepratory1/Term1/SB/Arabic_p.pdf", title)
    assert prep is not None and prep.grade_level == 7

    # Secondry بدل Secondary
    sec = parse_url(f"{base}/Secondry/Secondry2/Term1/SB/Arabic_s.pdf", title)
    assert sec is not None and sec.grade_level == 11


def test_kindergarten_levels() -> None:
    """رياض الأطفال بتترقّم -1 و 0 عشان الابتدائي يفضل من 1."""
    assert detect_grade("مستوى أول")[0] == -1
    assert detect_grade("مستوى ثان")[0] == 0
    assert detect_grade("الصف الأول الإبتدائى")[0] == 1


def test_workbook_kind() -> None:
    assert detect_kind("كراسة التدريبات") == "workbook"
