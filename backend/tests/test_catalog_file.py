"""الكتالوج اللي بيتشحن مع الكود لازم يفضل مقروء بالكامل.

الملف ده هو اللي `books.sh import` بيشتغل عليه من غير أي تحضير، فأي
رابط فيه مش بيتفكّ معناه كتاب هيضيع من المكتبة من غير ما حد ياخد باله.
"""

from __future__ import annotations

from collections import Counter
from pathlib import Path

import pytest

from app.tools.import_moe import read_entries
from app.tools.moe_urls import parse_url

CATALOG = Path(__file__).resolve().parents[1] / "catalogs" / "moe-2026-2027-term1.txt"


def read_catalog() -> list[tuple[str, str]]:
    """يرجّع (رابط، عنوان) لكل كتاب — العنوان هو السطر اللي فوق الرابط."""
    entries: list[tuple[str, str]] = []
    title = ""
    for line in CATALOG.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("http"):
            entries.append((stripped, title))
            title = ""
        else:
            title = stripped
    return entries


ENTRIES = read_catalog()


def test_the_catalog_is_not_empty():
    assert len(ENTRIES) >= 100


def test_every_url_is_unique():
    duplicates = [url for url, count in Counter(u for u, _ in ENTRIES).items() if count > 1]
    assert not duplicates, duplicates


@pytest.mark.parametrize("url,title", ENTRIES, ids=[u.rsplit("/", 1)[-1] for u, _ in ENTRIES])
def test_every_entry_resolves(url: str, title: str):
    ref = parse_url(url, title)
    assert ref is not None, "الرابط مش متعرّف عليه"
    assert ref.grade_level is not None, "الصف مش متحدّد"
    assert ref.stage, "المرحلة مش متحدّدة"
    assert ref.subject_slug, "المادة مش متحدّدة"
    assert ref.term in (1, 2), f"ترم غريب: {ref.term}"
    assert ref.language in {"arabic", "languages", "both"}, ref.language


def test_all_four_stages_are_covered():
    stages = {parse_url(u, t).stage for u, t in ENTRIES}
    assert stages == {"kindergarten", "primary", "preparatory", "secondary"}


def test_grades_run_from_kg1_to_secondary3():
    levels = {parse_url(u, t).grade_level for u, t in ENTRIES}
    assert levels == set(range(-1, 13))


# ------------------------------------------------------------------
# حالات اسم الملف اللي وقعت قبل كده
# ------------------------------------------------------------------

BASE = (
    "https://elearnningcontent.blob.core.windows.net/elearnningcontent/"
    "2026_2027/Primary/Primary4/Term1/StudentBook/"
)


@pytest.mark.parametrize(
    "filename,slug",
    [
        # الدين من غير كلمة religion، وبالأخطاء الإملائية اللي في الموقع
        ("Islamic_prim5_tr1.pdf", "religion_islamic"),
        ("Islamic_Education_Primary6_T1.pdf", "religion_islamic"),
        ("Cristian_reliogion_prim5_t1.pdf", "religion_christian"),
        ("Christian_Education_Primary6_T1.pdf", "religion_christian"),
        # ICT_ARABIC كان بيتقرا "لغة عربية" لأن اسم الملف فيه arabic
        ("ICT_ARABIC_Prim4_TR1.pdf", "ict"),
        ("ICT_EN_Prim4_TR1.pdf", "ict"),
        ("Arabic_language_prim4_t1.pdf", "arabic"),
    ],
)
def test_subject_from_a_bare_filename(filename: str, slug: str):
    """من غير عنوان، اسم الملف لوحده لازم يوصّل للمادة الصح."""
    ref = parse_url(BASE + filename, "")
    assert ref is not None
    assert ref.subject_slug == slug


def test_ict_arabic_edition_is_for_arabic_schools():
    assert parse_url(BASE + "ICT_ARABIC_Prim4_TR1.pdf", "").language == "arabic"
    assert parse_url(BASE + "ICT_EN_Prim4_TR1.pdf", "").language == "languages"


# ------------------------------------------------------------------
# القارئ الحقيقي — read_entries هو اللي الاستيراد بيستخدمه
# ------------------------------------------------------------------


def test_read_entries_agrees_with_the_file():
    """الاستيراد لازم يشوف نفس الكتب اللي في الملف، بنفس العناوين."""
    entries = read_entries(str(CATALOG))
    assert len(entries) == len(ENTRIES)
    assert [e.url for e in entries] == [url for url, _ in ENTRIES]
    assert [e.title for e in entries] == [title for _, title in ENTRIES]


def test_no_title_carries_the_file_header():
    """
    التعليقات كانت بتتلزق في عنوان أول كتاب، فـ MySQL بيرفض الصف
    (1406, "Data too long for column 'title_ar'") — وكمان كلام التعليق
    كان بيخلّي الكتاب يتسجّل في مادة غلط.
    """
    for entry in read_entries(str(CATALOG)):
        assert entry.title, entry.url
        assert "#" not in entry.title
        assert "studentbooks.moe.gov.eg" not in entry.title
        assert len(entry.title) <= 240, len(entry.title)


def test_comments_and_blank_lines_reset_the_title(tmp_path):
    catalog = tmp_path / "mixed.txt"
    catalog.write_text(
        "# هيدر طويل فيه كلام عن Cristian_reliogion وعن اللغة العربية\n"
        "# سطر تعليق تاني\n"
        "\n"
        "# ── الأول الابتدائي ──\n"
        "اللغة العربية - الصف الأول الإبتدائى - الفصل الدراسى الأول\n"
        "https://example.com/a/Arabic_prim1_t1.pdf\n"
        "\n"
        "الرياضيات - الصف الأول الإبتدائى - الفصل الدراسى الأول\n"
        "https://example.com/a/Math_prim1_t1.pdf\n",
        encoding="utf-8",
    )
    entries = read_entries(str(catalog))
    assert len(entries) == 2
    assert entries[0].title == "اللغة العربية - الصف الأول الإبتدائى - الفصل الدراسى الأول"
    assert entries[1].title == "الرياضيات - الصف الأول الإبتدائى - الفصل الدراسى الأول"


def test_a_url_with_no_title_still_reads(tmp_path):
    catalog = tmp_path / "bare.txt"
    catalog.write_text("https://example.com/a/Math_prim1_t1.pdf\n", encoding="utf-8")
    entries = read_entries(str(catalog))
    assert len(entries) == 1
    assert entries[0].title == ""


def test_the_book_title_is_clamped_to_the_column():
    from app.tools.import_moe import BOOK_TITLE_MAX

    assert BOOK_TITLE_MAX == 240
