"""اكتشاف روابط كتب الوزارة من مكتبتها الإلكترونية.

المكتبة على studentbooks.moe.gov.eg بتعرض الكتب في بطاقات بالشكل ده:

    <article class="book-card">
      <h3>الرياضيات باللغة الإنجليزية</h3>   ← المادة
      <p>الصف الأول الإبتدائى</p>            ← الصف
      <p>الفصل الدراسى الأول</p>             ← الترم
      <p>كتاب الطالب</p>                      ← النوع
      <a class="book-link" href="....pdf">

⚠️ البطاقات دي **بتتحقن بجافاسكربت**، يعني تحميل الصفحة بـHTTP عادي
بيرجّع حاوية فاضية. عشان كده بنجرّب على ترتيب:

  ١. نقرا البطاقات من الـHTML (لو الصفحة متولّدة من السيرفر)
  ٢. لو فاضية، نقرا ملفات الجافاسكربت المرتبطة ونستخرج البيانات منها
  ٣. لو فشل ده كمان، نخمّن الروابط ونتأكد منها بطلبات HEAD
"""

from __future__ import annotations

import json
import re
from urllib.parse import urljoin, urlparse

import httpx
from bs4 import BeautifulSoup

# الموقع بيرفض الطلبات اللي شكلها مش متصفح (403)، فبنبعت ترويسات
# متصفح كاملة مش بس User-Agent.
_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    ),
    "Accept": (
        "text/html,application/xhtml+xml,application/xml;q=0.9,"
        "image/avif,image/webp,*/*;q=0.8"
    ),
    "Accept-Language": "ar,en-US;q=0.9,en;q=0.8",
    "Accept-Encoding": "gzip, deflate, br",
    "Upgrade-Insecure-Requests": "1",
    "Sec-Fetch-Dest": "document",
    "Sec-Fetch-Mode": "navigate",
    "Sec-Fetch-Site": "none",
    "Sec-Fetch-User": "?1",
    "Cache-Control": "no-cache",
}

# صفحات المكتبة حسب المرحلة (المسارات زي ما هي على الموقع — لاحظ
# "Books-sec" مش "Books-Secondary")
DEFAULT_PAGES = [
    "https://studentbooks.moe.gov.eg/Books/Books-Kindergarten/",
    "https://studentbooks.moe.gov.eg/Books/Books-Primary/",
    "https://studentbooks.moe.gov.eg/Books/Books-Preparatory/",
    "https://studentbooks.moe.gov.eg/Books/Books-sec/",
]

_PDF_RE = re.compile(r"https?://[^\s\"'<>()]+\.pdf", re.IGNORECASE)


# --------------------------------------------------------------------------
# ١. قراءة البطاقات من الـHTML
# --------------------------------------------------------------------------


def parse_cards(html: str) -> list[tuple[str, str]]:
    """يستخرج (رابط، عنوان كامل) من بطاقات الكتب."""
    soup = BeautifulSoup(html, "html.parser")
    results: list[tuple[str, str]] = []

    for card in soup.select("article.book-card, .book-card"):
        anchor = card.find("a", href=True)
        if anchor is None:
            continue
        href = anchor["href"].split("#")[0]
        if not href.lower().endswith(".pdf"):
            continue

        # العنوان = اسم المادة + الصف + الترم + النوع، كل واحد في عنصر
        parts: list[str] = []
        heading = card.find(["h1", "h2", "h3", "h4"])
        if heading:
            parts.append(heading.get_text(" ", strip=True))
        for paragraph in card.find_all("p"):
            text = paragraph.get_text(" ", strip=True)
            if text:
                parts.append(text)

        results.append((href, " - ".join(parts)))

    return results


# --------------------------------------------------------------------------
# ٢. استخراج البيانات من ملفات الجافاسكربت
# --------------------------------------------------------------------------


def _strings_near(source: str, url: str, window: int = 500) -> str:
    """يجمع النصوص العربية اللي حوالين الرابط في كود الجافاسكربت."""
    index = source.find(url)
    if index < 0:
        return ""

    chunk = source[max(0, index - window): index + len(url) + 120]
    # أي نص عربي بين علامتي اقتباس
    arabic = re.findall(r'["\']([^"\']*[؀-ۿ][^"\']*)["\']', chunk)
    unique: list[str] = []
    for item in arabic:
        cleaned = item.strip()
        if cleaned and cleaned not in unique:
            unique.append(cleaned)
    return " - ".join(unique[:6])


def parse_scripts(page_url: str, html: str, client: httpx.Client) -> list[tuple[str, str]]:
    """يحمّل ملفات الجافاسكربت المرتبطة بالصفحة ويستخرج الكتب منها."""
    soup = BeautifulSoup(html, "html.parser")
    results: dict[str, str] = {}

    sources: list[str] = []
    for script in soup.find_all("script"):
        src = script.get("src")
        if src:
            sources.append(urljoin(page_url, src))
        elif script.string and ".pdf" in script.string:
            # بيانات مكتوبة جوّه الصفحة نفسها
            sources.append("")

    # الكود المضمّن في الصفحة
    inline = "\n".join(
        script.string or "" for script in soup.find_all("script") if not script.get("src")
    )

    bodies = [inline] if inline else []

    for src in [s for s in sources if s]:
        try:
            response = client.get(src)
        except httpx.HTTPError:
            continue
        if response.status_code == 200:
            bodies.append(response.text)
            print(f"  · قرأنا {src.split('/')[-1]} ({len(response.text)} حرف)")

    for body in bodies:
        # المحاولة الأولى: بيانات JSON منظّمة
        for match in re.finditer(r"\{[^{}]*\.pdf[^{}]*\}", body):
            try:
                record = json.loads(match.group(0))
            except json.JSONDecodeError:
                continue
            url = next(
                (v for v in record.values()
                 if isinstance(v, str) and v.lower().endswith(".pdf")),
                None,
            )
            if not url:
                continue
            title = " - ".join(
                str(v) for v in record.values()
                if isinstance(v, str) and not v.lower().endswith(".pdf")
            )
            results.setdefault(url, title)

        # المحاولة التانية: أي رابط PDF مع النصوص العربية اللي حواليه
        for url in _PDF_RE.findall(body):
            results.setdefault(url, _strings_near(body, url))

    return sorted(results.items())


# --------------------------------------------------------------------------
# الزحف
# --------------------------------------------------------------------------


def crawl(
    start_url: str,
    *,
    depth: int = 1,
    timeout: int = 60,
) -> list[tuple[str, str]]:
    """يجمع كتب صفحة (أو مجموعة صفحات) من مكتبة الوزارة."""

    seen: set[str] = set()
    found: dict[str, str] = {}
    queue: list[tuple[str, int]] = [(start_url, 0)]
    origin = urlparse(start_url).netloc

    with httpx.Client(timeout=timeout, follow_redirects=True, headers=_HEADERS) as client:
        while queue:
            url, level = queue.pop(0)
            if url in seen:
                continue
            seen.add(url)

            try:
                response = client.get(url)
            except httpx.HTTPError as error:
                print(f"  ✗ تعذّر فتح {url}: {error}")
                continue

            if response.status_code != 200:
                print(f"  ✗ {response.status_code} — {url}")
                continue

            html = response.text
            before = len(found)

            # ١) البطاقات في الـHTML
            for book_url, title in parse_cards(html):
                found.setdefault(urljoin(url, book_url), title)

            # ٢) لو مفيش، نبص في الجافاسكربت
            if len(found) == before:
                for book_url, title in parse_scripts(url, html, client):
                    found.setdefault(book_url, title)

            # ٣) أي روابط PDF مباشرة في الصفحة
            soup = BeautifulSoup(html, "html.parser")
            for anchor in soup.find_all("a", href=True):
                href = urljoin(url, anchor["href"]).split("#")[0]
                if href.lower().endswith(".pdf"):
                    found.setdefault(href, anchor.get_text(" ", strip=True))
                elif level < depth and urlparse(href).netloc == origin:
                    queue.append((href, level + 1))

            print(f"  ✓ {url} — {len(found) - before} كتاب جديد "
                  f"(الإجمالي {len(found)})")

    return sorted(found.items())


def crawl_all(pages: list[str] | None = None, *, depth: int = 1) -> list[tuple[str, str]]:
    """يزحف على صفحات المراحل الثلاثة."""
    combined: dict[str, str] = {}
    for page in pages or DEFAULT_PAGES:
        print(f"\n▶ {page}")
        for url, title in crawl(page, depth=depth):
            combined.setdefault(url, title)
    return sorted(combined.items())


# --------------------------------------------------------------------------
# التخمين (احتياطي)
# --------------------------------------------------------------------------

_SUBJECT_TOKENS: list[str] = [
    "Arabic_language", "English_language", "Math_Ar", "Math_EN", "Math_FR",
    "Science_Ar", "Science_EN", "Islamic_religion", "Cristian_religion",
    "Christian_religion", "Social_studies", "Social_Studies",
    "Multi_disciplinary", "Professional_skills", "Art_education",
    "Music_education", "Physics", "Chemistry", "Biology", "Geology",
    "History", "Geography", "Philosophy", "Egyptian_history",
    "Integrated_science", "Computer_science", "French_language",
    "German_language", "Italian_language",
]

_STAGE_PATHS: list[tuple[str, str, int, int]] = [
    ("Primary", "prim", 1, 6),
    ("Preparatory", "prep", 7, 3),
    ("Secondary", "sec", 10, 3),
]

_KIND_PATHS = ["StudentBook", "TeacherGuide", "ActivityBook"]


def _candidate_names(prefix: str, number: int, term: int) -> list[str]:
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

    with httpx.Client(timeout=timeout, follow_redirects=True, headers=_HEADERS) as client:

        def check(url: str) -> str | None:
            try:
                return url if client.head(url).status_code == 200 else None
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


# --------------------------------------------------------------------------
# قراءة صفحة محفوظة من المتصفح
# --------------------------------------------------------------------------


def from_html_file(path: str) -> list[tuple[str, str]]:
    """يقرا كتب من ملف HTML محفوظ.

    لو الموقع رافض طلبات السيرفر (403)، افتح الصفحة في متصفحك واحفظها
    (Ctrl+S) أو انسخ الـHTML وحطه في ملف، وشغّل الأمر ده عليه. البطاقات
    اللي بيرسمها الجافاسكربت بتبقى موجودة في الحفظ ده.
    """
    from pathlib import Path

    html = Path(path).read_text(encoding="utf-8", errors="ignore")
    results = parse_cards(html)

    if not results:
        # مفيش بطاقات — ناخد أي روابط PDF في الملف
        soup = BeautifulSoup(html, "html.parser")
        for anchor in soup.find_all("a", href=True):
            href = anchor["href"].split("#")[0]
            if href.lower().endswith(".pdf"):
                results.append((href, anchor.get_text(" ", strip=True)))

    return results
