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
