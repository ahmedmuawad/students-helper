"""اكتشاف روابط كتب الوزارة بطريقتين.

١. الزحف (crawl): بيجيب صفحة الكتب من الموقع ويستخرج روابط الـPDF
   والعناوين اللي جنبها. دي الطريقة المفضّلة — بتجيب الأسماء الصحيحة.

٢. التخمين (probe): بيولّد روابط محتملة من نمط الملفات المعروف ويتأكد
   من وجود كل واحد بطلب HEAD. بنستخدمها لو الصفحة مش متاحة.
"""

from __future__ import annotations

import re
from urllib.parse import urljoin, urlparse

import httpx
from bs4 import BeautifulSoup

# --------------------------------------------------------------------------
# ١. الزحف على صفحة الموقع
# --------------------------------------------------------------------------

_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/122.0 Safari/537.36"
    ),
    "Accept-Language": "ar,en;q=0.8",
}


def _title_near(anchor) -> str:
    """يجمع النص الوصفي حوالين الرابط.

    صفحات الوزارة بتحط اسم المادة والصف والترم في عناصر قبل الرابط، مش
    في نص الرابط نفسه، فبنقرا نص الصف/الخلية اللي الرابط جواها.
    """
    parts: list[str] = []

    text = anchor.get_text(" ", strip=True)
    if text:
        parts.append(text)

    # نطلع لفوق لحد ما نلاقي حاوية فيها نص كفاية
    node = anchor.parent
    for _ in range(4):
        if node is None:
            break
        container_text = node.get_text(" ", strip=True)
        if container_text and len(container_text) > len(" ".join(parts)):
            parts = [container_text]
            if len(container_text) > 25:
                break
        node = node.parent

    combined = " ".join(parts)
    return re.sub(r"\s+", " ", combined).strip()[:300]


def crawl(
    start_url: str,
    *,
    depth: int = 1,
    timeout: int = 60,
) -> list[tuple[str, str]]:
    """يرجّع قائمة (رابط PDF، العنوان) من صفحة وما يتفرّع عنها."""

    seen_pages: set[str] = set()
    found: dict[str, str] = {}
    queue: list[tuple[str, int]] = [(start_url, 0)]
    origin = urlparse(start_url).netloc

    with httpx.Client(
        timeout=timeout, follow_redirects=True, headers=_HEADERS
    ) as client:
        while queue:
            url, level = queue.pop(0)
            if url in seen_pages:
                continue
            seen_pages.add(url)

            try:
                response = client.get(url)
            except httpx.HTTPError as error:
                print(f"  ✗ تعذّر فتح {url}: {error}")
                continue

            if response.status_code != 200:
                print(f"  ✗ {response.status_code} — {url}")
                continue

            soup = BeautifulSoup(response.text, "html.parser")

            for anchor in soup.find_all("a", href=True):
                href = urljoin(url, anchor["href"])
                clean = href.split("#")[0]

                if clean.lower().endswith(".pdf"):
                    found.setdefault(clean, _title_near(anchor))
                elif level < depth and urlparse(clean).netloc == origin:
                    queue.append((clean, level + 1))

            print(f"  ✓ {url} — إجمالي {len(found)} ملف لحد دلوقتي")

    return sorted(found.items())


# --------------------------------------------------------------------------
# ٢. تخمين الروابط والتأكد منها
# --------------------------------------------------------------------------

# صيغ اسم الملف اللي شفناها في مكتبة الوزارة. الأسماء مش موحّدة تمامًا
# (Math_Ar_prim1_t1 مقابل Math_EN_P1_T1)، فبنجرّب الصيغ المعروفة.
_SUBJECT_TOKENS: list[str] = [
    "Arabic_language", "English_language", "Math_Ar", "Math_EN",
    "Science_Ar", "Science_EN", "Islamic_religion", "Cristian_religion",
    "Christian_religion", "Social_studies", "Social_Studies",
    "Multi_disciplinary", "Professional_skills", "Art_education",
    "Music_education", "Physics", "Chemistry", "Biology", "Geology",
    "History", "Geography", "Philosophy", "Egyptian_history",
    "Integrated_science", "Computer_science", "French_language",
    "German_language", "Italian_language",
]

_STAGE_PATHS: list[tuple[str, str, int, int]] = [
    # (اسم المرحلة في المسار، بادئة الصف في اسم الملف، أول صف، عدد الصفوف)
    ("Primary", "prim", 1, 6),
    ("Preparatory", "prep", 7, 3),
    ("Secondary", "sec", 10, 3),
]

_KIND_PATHS = ["StudentBook", "TeacherGuide", "ActivityBook"]


def _candidate_names(prefix: str, number: int, term: int) -> list[str]:
    """صيغ اسم الملف المحتملة لصف وترم معيّنين."""
    initial = prefix[0].upper()
    return [
        f"{prefix}{number}_t{term}",
        f"{prefix}{number}_T{term}",
        f"{initial}{number}_T{term}",
        f"{initial}{number}_t{term}",
        f"{prefix}{number}_term{term}",
    ]


def probe(
    container: str,
    year: str,
    *,
    grades: list[int] | None = None,
    timeout: int = 20,
    max_workers: int = 12,
) -> list[tuple[str, str]]:
    """يجرّب الروابط المحتملة ويرجّع اللي موجود فعلاً."""

    from concurrent.futures import ThreadPoolExecutor

    candidates: list[str] = []
    for stage_path, prefix, first, count in _STAGE_PATHS:
        for offset in range(count):
            level = first + offset
            if grades and level not in grades:
                continue
            number = offset + 1
            for term in (1, 2):
                for kind in _KIND_PATHS:
                    base = (
                        f"{container.rstrip('/')}/{year}/{stage_path}/"
                        f"{stage_path}{number}/Term{term}/{kind}"
                    )
                    for subject in _SUBJECT_TOKENS:
                        for name in _candidate_names(prefix, number, term):
                            candidates.append(f"{base}/{subject}_{name}.pdf")

    print(f"جاري التأكد من {len(candidates)} رابط محتمل ...")
    found: list[tuple[str, str]] = []

    with httpx.Client(
        timeout=timeout, follow_redirects=True, headers=_HEADERS
    ) as client:

        def check(url: str) -> str | None:
            try:
                response = client.head(url)
                return url if response.status_code == 200 else None
            except httpx.HTTPError:
                return None

        with ThreadPoolExecutor(max_workers=max_workers) as pool:
            for index, result in enumerate(pool.map(check, candidates), start=1):
                if result:
                    found.append((result, ""))
                    print(f"  ✓ {result.split('/')[-1]}")
                if index % 500 == 0:
                    print(f"  ... {index}/{len(candidates)} · لقينا {len(found)}")

    return found
