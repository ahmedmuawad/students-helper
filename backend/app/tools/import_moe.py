"""استيراد كتب الوزارة مباشرة من مكتبتها الإلكترونية.

السيرفر هو اللي بينزّل — مفيش تنزيل على جهازك ولا رفع يدوي.

الاستخدام:

    # ١. محاولة جلب فهرس المكتبة كامل (Azure Blob listing)
    python -m app.tools.import_moe list --out catalog.txt

    # ٢. معاينة اللي هيتستورد من غير تنزيل
    python -m app.tools.import_moe plan --from catalog.txt

    # ٣. التنزيل والاستيراد الفعلي
    python -m app.tools.import_moe import --from catalog.txt

الملف اللي بيتقرا ممكن يكون:
  - روابط PDF (سطر لكل رابط)
  - أو صيغة "عنوان عربي" + سطر الرابط (زي ما بيتنسخ من الموقع)
"""

from __future__ import annotations

import argparse
import re
import sys
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse

import httpx
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.database import Base, SessionLocal, engine
from app.core.schema_sync import sync_schema
from app.core import media
from app.models import (
    Book,
    BookKind,
    Curriculum,
    EducationStage,
    Grade,
    Lesson,
    Subject,
    Unit,
)
from app.tools.moe_crawl import (
    DEFAULT_PAGES,
    crawl,
    crawl_all,
    from_html_file,
    probe,
)
from app.tools import structure
from app.tools.moe_patterns import GRADE_NAMES_AR
from app.tools.moe_urls import BookRef, parse_url

DEFAULT_CONTAINER = "https://elearnningcontent.blob.core.windows.net/elearnningcontent"

_STAGE_ENUM = {
    "kindergarten": EducationStage.kindergarten,
    "primary": EducationStage.primary,
    "preparatory": EducationStage.preparatory,
    "secondary": EducationStage.secondary,
}


def log(message: str) -> None:
    print(message, flush=True)


def ensure_schema() -> list[str]:
    """ينشئ الجداول الناقصة ويظبّط القديمة على الموديلات."""
    Base.metadata.create_all(bind=engine)
    return sync_schema(engine)


def log_schema_changes(changes: list[str]) -> None:
    if not changes:
        return
    log("تعديلات على الجداول القديمة:")
    for change in changes:
        log(f"  {change}")


def expand_html_paths(paths: list[str]) -> list[str]:
    """يوسّع أي مجلد للملفات اللي جواه، ويرتّبهم."""
    found: list[str] = []
    for raw in paths:
        candidate = Path(raw).expanduser()
        if candidate.is_dir():
            pages = sorted(
                item for item in candidate.iterdir()
                if item.suffix.lower() in {".html", ".htm"}
            )
            if not pages:
                log(f"✗ مفيش ملفات HTML في {candidate}")
                return []
            found.extend(str(item) for item in pages)
        else:
            found.append(str(candidate))
    return found


def explain_read_error(path: str, error: OSError) -> None:
    """رسالة مفهومة بدل traceback."""
    resolved = Path(path).expanduser()
    log(f"✗ مش قادر أقرا: {resolved}")
    if isinstance(error, FileNotFoundError):
        log("  الملف ده مش موجود. المسار لازم يكون مسار حقيقي على السيرفر،")
        log(f"  والمجلد الحالي دلوقتي: {Path.cwd()}")
    elif isinstance(error, PermissionError):
        log("  الملف موجود بس الصلاحيات مش سامحة. الأمر بيشتغل بمستخدم الموقع،")
        log("  فحطّ الملفات في مكان يقدر يقراه (مش /root) أو شغّل:")
        log("    sudo bash deploy/books.sh html <ملفاتك>")
        log("  السكربت بينسخهم لمكان مناسب لوحده.")
    else:
        log(f"  ({error.strerror})")




# --------------------------------------------------------------------------
# ١. جلب فهرس المكتبة
# --------------------------------------------------------------------------


def list_container(container_url: str, prefix: str = "") -> list[str]:
    """يحاول جلب كل ملفات الحاوية عبر واجهة فهرسة Azure.

    بتنجح لو الحاوية مسموح فيها بالفهرسة العامة. لو مسموح بالقراءة فقط،
    بترجّع قائمة فاضية ووقتها بنستخدم قائمة روابط جاهزة.
    """
    blobs: list[str] = []
    marker = ""

    with httpx.Client(timeout=60, follow_redirects=True) as client:
        while True:
            params = {"restype": "container", "comp": "list", "maxresults": "5000"}
            if prefix:
                params["prefix"] = prefix
            if marker:
                params["marker"] = marker

            response = client.get(container_url, params=params)
            if response.status_code != 200:
                log(
                    f"  فهرسة الحاوية مرفوضة ({response.status_code}) — "
                    "استخدم قائمة روابط جاهزة بدلها"
                )
                return []

            try:
                root = ET.fromstring(response.text)
            except ET.ParseError:
                log("  الرد مش XML — الفهرسة غالبًا مقفولة")
                return []

            for blob in root.iter("Blob"):
                name = blob.findtext("Name") or ""
                if name.lower().endswith(".pdf"):
                    blobs.append(f"{container_url.rstrip('/')}/{name}")

            marker = (root.findtext("NextMarker") or "").strip()
            if not marker:
                break

    return blobs


# --------------------------------------------------------------------------
# ٢. قراءة قائمة الروابط
# --------------------------------------------------------------------------

_URL_RE = re.compile(r"https?://\S+\.pdf", re.IGNORECASE)

# نفس طول عمود books.title_ar
BOOK_TITLE_MAX = 240


@dataclass
class Entry:
    url: str
    title: str


def read_entries(path: str) -> list[Entry]:
    """يقرأ ملف روابط، ويربط كل رابط بسطور العنوان اللي قبله على طول.

    السطر اللي بيبدأ بـ `#` تعليق، والسطر الفاضي بيفصل بين كتاب والتاني.
    الاتنين بيصفّروا العنوان المتراكم — من غير كده هيدر الملف كله بيتلزق
    في عنوان أول كتاب، وكلامه بيشوّش تحديد المادة كمان.
    """
    entries: list[Entry] = []
    buffer: list[str] = []

    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()

            if not line or line.startswith("#") or set(line) <= {"-", "=", "_"}:
                buffer = []
                continue

            match = _URL_RE.search(line)
            if match:
                entries.append(Entry(url=match.group(0), title=" ".join(buffer)))
                buffer = []
            else:
                buffer.append(line)

    return entries


# --------------------------------------------------------------------------
# ٣. بناء شجرة المنهج
# --------------------------------------------------------------------------


def _curriculum_for(db: Session, ref: BookRef, language: str) -> Curriculum:
    """بيجيب أو ينشئ منهج للنسخة دي (عربي / لغات)."""
    system_id = "egyptBaccalaureate" if ref.grade_level >= 10 else "egyptGeneral"
    year = ref.academic_year or "2026/2027"

    curriculum = (
        db.query(Curriculum)
        .filter(
            Curriculum.country_code == "EG",
            Curriculum.system_id == system_id,
            Curriculum.language == language,
            Curriculum.academic_year == year,
        )
        .one_or_none()
    )
    if curriculum is None:
        label = "لغات" if language == "languages" else "عربي"
        curriculum = Curriculum(
            country_code="EG",
            system_id=system_id,
            language=language,
            academic_year=year,
            name_ar=f"المنهج المصري - {label}",
            name_en=f"Egyptian Curriculum - {label}",
            is_published=True,
        )
        db.add(curriculum)
        db.flush()
    return curriculum


def _grade_for(db: Session, curriculum: Curriculum, ref: BookRef) -> Grade:
    grade = (
        db.query(Grade)
        .filter(Grade.curriculum_id == curriculum.id, Grade.level == ref.grade_level)
        .one_or_none()
    )
    if grade is None:
        grade = Grade(
            curriculum_id=curriculum.id,
            level=ref.grade_level,
            stage=_STAGE_ENUM.get(ref.stage, EducationStage.primary),
            name_ar=GRADE_NAMES_AR.get(ref.grade_level, f"الصف {ref.grade_level}"),
            name_en=f"Grade {ref.grade_level}",
        )
        db.add(grade)
        db.flush()
    return grade


def _subject_for(db: Session, grade: Grade, ref: BookRef) -> Subject:
    subject = (
        db.query(Subject)
        .filter(Subject.grade_id == grade.id, Subject.slug == ref.subject_slug)
        .one_or_none()
    )
    if subject is None:
        order = db.query(Subject).filter(Subject.grade_id == grade.id).count()
        subject = Subject(
            grade_id=grade.id,
            slug=ref.subject_slug,
            name_ar=ref.subject_name_ar,
            name_en=ref.subject_name_en,
            color=ref.subject_color,
            counts_toward_total=not ref.subject_slug.startswith("religion"),
            sort_order=order,
        )
        db.add(subject)
        db.flush()
    return subject


def _import_toc(db: Session, subject: Subject, term: int, content: bytes) -> int:
    """يستخرج فهرس الكتاب المدمج ويحوّله وحدات ودروس.

    كتب كتير متولّدة رقميًا وفيها فهرس (bookmarks) — لو موجود بنبني منه
    شجرة الدروس تلقائيًا بدل الإدخال اليدوي.
    """
    toc = media.extract_table_of_contents(content)
    if not toc:
        return 0

    # لو فيه وحدات لنفس المادة والترم من استيراد سابق، منعيدش البناء.
    exists = (
        db.query(Unit)
        .filter(Unit.subject_id == subject.id, Unit.term == term)
        .count()
    )
    if exists:
        return 0

    created = 0
    current_unit: Unit | None = None
    unit_number = 0
    lesson_number = 0

    for item in toc:
        level, title, page = item["level"], item["title"], item["page"]

        if level == 1:
            unit_number += 1
            lesson_number = 0
            current_unit = Unit(
                subject_id=subject.id,
                term=term,
                number=unit_number,
                title_ar=title[:200],
            )
            db.add(current_unit)
            db.flush()
        elif current_unit is not None:
            lesson_number += 1
            db.add(
                Lesson(
                    unit_id=current_unit.id,
                    number=lesson_number,
                    title_ar=title[:240],
                    page_start=page or None,
                )
            )
            created += 1

    return created


# --------------------------------------------------------------------------
# ٤. الاستيراد
# --------------------------------------------------------------------------


def import_entries(
    entries: list[Entry],
    *,
    dry_run: bool = False,
    delay: float = 0.5,
    limit: int | None = None,
    replace: bool = False,
) -> None:
    log_schema_changes(ensure_schema())
    db = SessionLocal()

    parsed: list[tuple[Entry, BookRef]] = []
    skipped: list[Entry] = []

    for entry in entries:
        ref = parse_url(entry.url, entry.title)
        if ref is None:
            skipped.append(entry)
        else:
            parsed.append((entry, ref))

    log(f"\nاتعرّف على {len(parsed)} كتاب · اتخطى {len(skipped)}")

    if skipped:
        log("\nملفات مش متعرّف عليها:")
        for entry in skipped[:12]:
            log(f"  - {entry.url.split('/')[-1]}")
        if len(skipped) > 12:
            log(f"  ... و {len(skipped) - 12} غيرهم")

    if dry_run:
        log("\nالخطة:")
        log(f"  {'الصف':6} {'ترم':4} {'النسخة':10} {'النوع':12} المادة")
        log("  " + "-" * 62)
        for _, ref in parsed[: (limit or 40)]:
            log(
                f"  {ref.grade_level:<6} {ref.term:<4} {ref.language:10} "
                f"{ref.kind:12} {ref.subject_name_ar}"
            )
        if limit is None and len(parsed) > 40:
            log(f"  ... و {len(parsed) - 40} غيرهم")
        db.close()
        return

    counters = {"downloaded": 0, "reused": 0, "failed": 0, "lessons": 0,
                "replaced": 0}
    broken: list[tuple[BookRef, Exception]] = []

    with httpx.Client(timeout=180, follow_redirects=True) as client:
        for index, (entry, ref) in enumerate(parsed, start=1):
            if limit and counters["downloaded"] + counters["reused"] >= limit:
                break

            try:
                response = client.get(ref.url)
                if response.status_code != 200:
                    log(f"  ✗ [{index}/{len(parsed)}] {response.status_code} — "
                        f"{ref.subject_name_ar} صف {ref.grade_level}")
                    counters["failed"] += 1
                    continue
                content = response.content
            except httpx.HTTPError as error:
                log(f"  ✗ [{index}/{len(parsed)}] فشل التحميل: {error}")
                counters["failed"] += 1
                continue

            try:
                _store_book(db, ref, content, counters, replace=replace)
                db.commit()
            except SQLAlchemyError as error:
                # كتاب واحد بايظ مايوقّفش الباقي
                db.rollback()
                counters["failed"] += 1
                broken.append((ref, error))
                log(f"  ✗ [{index}/{len(parsed)}] اتخطّيناه — "
                    f"{ref.subject_name_ar} صف {ref.grade_level}")
                continue

            log(
                f"  ✓ [{index}/{len(parsed)}] {ref.subject_name_ar} · "
                f"صف {ref.grade_level} · ترم {ref.term} · {ref.language}"
            )
            time.sleep(delay)

    db.close()

    log(
        f"\nخلص: {counters['downloaded']} ملف جديد · "
        f"{counters['reused']} موجود قبل كده · {counters['failed']} فشل · "
        f"{counters['lessons']} درس من الفهارس"
    )
    if counters["replaced"]:
        log(f"  ({counters['replaced']} تسجيل قديم اتشال واتكتب من جديد)")
    if broken:
        log("")
        log(f"⚠ الكتب اللي اتخطّت ({len(broken)}):")
        for ref, error in broken:
            reason = str(getattr(error, "orig", error)).split("\n")[0]
            log(f"  · {ref.subject_name_ar} صف {ref.grade_level} — {reason}")


def _store_book(
    db: Session,
    ref: BookRef,
    content: bytes,
    counters: dict[str, int],
    *,
    replace: bool = False,
) -> None:
    """يحفظ كتاب واحد. أي استثناء هنا بيترجع بـ rollback بره من غير ما
    يوقّف باقي الاستيراد."""
    if replace:
        # نمسح أي تسجيل قديم للرابط ده مهما كانت المادة اللي اتسجّل تحتها —
        # ده اللي بيصلّح كتاب اتحطّ في مادة غلط في استيراد سابق.
        removed = (
            db.query(Book)
            .filter(Book.source_url == ref.url)
            .delete(synchronize_session=False)
        )
        counters["replaced"] += removed

    # المادة المشتركة بتتسجّل في المنهجين (عربي ولغات)
    languages = ["arabic", "languages"] if ref.is_shared else [ref.language]

    for language in languages:
        curriculum = _curriculum_for(db, ref, language)
        grade = _grade_for(db, curriculum, ref)
        subject = _subject_for(db, grade, ref)

        existing = (
            db.query(Book)
            .filter(
                Book.subject_id == subject.id,
                Book.term == ref.term,
                Book.kind == BookKind(ref.kind),
                Book.source_url == ref.url,
            )
            .one_or_none()
        )
        if existing is not None:
            counters["reused"] += 1
            continue

        saved = media.save_book_file(
            content=content,
            original_name=ref.url.split("/")[-1],
            curriculum_id=curriculum.id,
            grade_level=ref.grade_level,
            subject_slug=ref.subject_slug,
        )

        title = ref.title_ar or (
            f"{ref.subject_name_ar} - "
            f"{GRADE_NAMES_AR.get(ref.grade_level, '')} - "
            f"الترم {'الأول' if ref.term == 1 else 'الثاني'}"
        )
        # عمود العنوان 240 حرف — أطول من كده MySQL بيرفض الصف كله
        title = title[:BOOK_TITLE_MAX]

        db.add(
            Book(
                subject_id=subject.id,
                kind=BookKind(ref.kind),
                term=ref.term,
                title_ar=title,
                publisher="وزارة التربية والتعليم",
                source_url=ref.url,
                license_note="منشور مجانًا من وزارة التربية والتعليم",
                is_published=True,
                **saved,
            )
        )
        counters["lessons"] += _import_toc(db, subject, ref.term, content)
        counters["downloaded"] += 1


# --------------------------------------------------------------------------
# سطر الأوامر
# --------------------------------------------------------------------------


def _print_status() -> None:
    """ملخص اللي في قاعدة البيانات."""
    from sqlalchemy import func

    db = SessionLocal()
    try:
        log("\nالمناهج:")
        curricula = db.query(Curriculum).order_by(Curriculum.id).all()
        if not curricula:
            log("  (فاضية — شغّل الأمر structure الأول)")

        for curriculum in curricula:
            grades = (
                db.query(Grade).filter(Grade.curriculum_id == curriculum.id).all()
            )
            subject_count = (
                db.query(func.count(Subject.id))
                .join(Grade)
                .filter(Grade.curriculum_id == curriculum.id)
                .scalar()
                or 0
            )
            book_count = (
                db.query(func.count(Book.id))
                .join(Subject)
                .join(Grade)
                .filter(Grade.curriculum_id == curriculum.id)
                .scalar()
                or 0
            )
            log(
                f"  {curriculum.name_ar} ({curriculum.academic_year}) — "
                f"{len(grades)} صف · {subject_count} مادة · {book_count} كتاب"
            )

        totals = {
            "الصفوف": db.query(func.count(Grade.id)).scalar() or 0,
            "المواد": db.query(func.count(Subject.id)).scalar() or 0,
            "الوحدات": db.query(func.count(Unit.id)).scalar() or 0,
            "الدروس": db.query(func.count(Lesson.id)).scalar() or 0,
            "الكتب": db.query(func.count(Book.id)).scalar() or 0,
        }
        log("\nالإجمالي:")
        for label, value in totals.items():
            log(f"  {label}: {value}")

        published = (
            db.query(func.count(Book.id)).filter(Book.is_published.is_(True)).scalar()
            or 0
        )
        log(f"  منشور للطلاب: {published}")
    finally:
        db.close()


def _write_catalog(path: str, results: list[tuple[str, str]]) -> None:
    """يكتب النتايج بصيغة: سطر العنوان بعدين سطر الرابط."""
    with open(path, "w", encoding="utf-8") as handle:
        for url, title in results:
            if title:
                handle.write(f"{title}\n")
            handle.write(f"{url}\n")
            handle.write("-" * 30 + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="استيراد كتب الوزارة مباشرة من مكتبتها الإلكترونية"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    listing = sub.add_parser("list", help="جلب فهرس المكتبة")
    listing.add_argument("--container", default=DEFAULT_CONTAINER)
    listing.add_argument("--prefix", default="", help="مثال: 2026_2027/Primary/")
    listing.add_argument("--out", default="catalog.txt")

    crawler = sub.add_parser("crawl", help="سحب الروابط من صفحة الموقع")
    crawler.add_argument("--url", help="رابط صفحة كتب معيّنة")
    crawler.add_argument("--all", action="store_true",
                         help="الزحف على المراحل الثلاثة (ابتدائي وإعدادي وثانوي)")
    crawler.add_argument("--depth", type=int, default=1,
                         help="عدد مستويات الروابط اللي يتبعها")
    crawler.add_argument("--out", default="catalog.txt")

    prober = sub.add_parser("probe", help="تخمين الروابط والتأكد منها")
    prober.add_argument("--container", default=DEFAULT_CONTAINER)
    prober.add_argument("--year", default="2026_2027")
    prober.add_argument("--grades", help="مثال: 1,2,3 (الافتراضي: كل الصفوف)")
    prober.add_argument("--out", default="catalog.txt")

    from_html = sub.add_parser(
        "html", help="قراءة الكتب من صفحة HTML محفوظة من المتصفح"
    )
    from_html.add_argument("files", nargs="+", help="ملف أو أكتر")
    from_html.add_argument("--out", default="catalog.txt")

    struct = sub.add_parser(
        "structure", help="إنشاء المناهج والصفوف والمواد (بدون كتب)"
    )
    struct.add_argument("--year", default="2026/2027")

    sub.add_parser("status", help="عرض محتوى قاعدة البيانات")

    sub.add_parser(
        "migrate", help="تظبيط الجداول القديمة على الموديلات (Enum وأعمدة ناقصة)"
    )

    plan = sub.add_parser("plan", help="معاينة من غير تنزيل")
    plan.add_argument("--from", dest="source", required=True)
    plan.add_argument("--limit", type=int)

    run = sub.add_parser("import", help="التنزيل والاستيراد")
    run.add_argument("--from", dest="source", required=True)
    run.add_argument("--limit", type=int, help="عدد الكتب (للتجربة)")
    run.add_argument("--delay", type=float, default=0.5,
                     help="ثواني بين كل تحميل والتاني")
    run.add_argument("--replace", action="store_true",
                     help="يشيل التسجيل القديم لكل رابط ويكتبه من جديد "
                          "(لإصلاح كتب اتسجّلت في مادة غلط)")

    args = parser.parse_args()

    if args.command == "list":
        log(f"جاري فهرسة {args.container} ...")
        urls = list_container(args.container, args.prefix)
        if not urls:
            log("مفيش نتايج — الفهرسة مقفولة على الحاوية دي.")
            log("الحل: حضّر ملف فيه روابط الكتب وشغّل:")
            log("  python -m app.tools.import_moe import --from روابطك.txt")
            return 1
        with open(args.out, "w", encoding="utf-8") as handle:
            handle.write("\n".join(urls))
        log(f"✓ لقينا {len(urls)} ملف — اتحفظوا في {args.out}")
        return 0

    if args.command == "crawl":
        if args.all or not args.url:
            log("الزحف على مكتبة الوزارة (المراحل الثلاثة):")
            for page in DEFAULT_PAGES:
                log(f"  · {page}")
            results = crawl_all(depth=args.depth)
        else:
            log(f"جاري الزحف على {args.url} ...")
            results = crawl(args.url, depth=args.depth)
        if not results:
            log("مفيش روابط PDF في الصفحة دي.")
            return 1
        _write_catalog(args.out, results)
        log(f"✓ لقينا {len(results)} ملف — اتحفظوا في {args.out}")
        return 0

    if args.command == "probe":
        grades = None
        if args.grades:
            grades = [int(part) for part in args.grades.split(",") if part.strip()]
        results = probe(args.container, args.year, grades=grades)
        if not results:
            log("مفيش روابط اشتغلت — راجع السنة أو صيغة المسار.")
            return 1
        _write_catalog(args.out, results)
        log(f"✓ لقينا {len(results)} ملف — اتحفظوا في {args.out}")
        return 0

    if args.command == "html":
        paths = expand_html_paths(args.files)
        if not paths:
            return 1
        results: list[tuple[str, str]] = []
        seen: set[str] = set()
        for path in paths:
            try:
                found = from_html_file(path)
            except OSError as error:
                explain_read_error(path, error)
                return 1
            new_count = 0
            for url, title in found:
                if url not in seen:
                    seen.add(url)
                    results.append((url, title))
                    new_count += 1
            log(f"  · {path} — {new_count} كتاب")
        if not results:
            log("مفيش كتب في الملفات دي.")
            return 1
        _write_catalog(args.out, results)
        log(f"✓ إجمالي {len(results)} كتاب — اتحفظوا في {args.out}")
        return 0

    if args.command == "migrate":
        changes = ensure_schema()
        if changes:
            log_schema_changes(changes)
            log(f"✓ اتظبط {len(changes)} تعديل")
        else:
            log("✓ الجداول متطابقة مع الموديلات — مفيش حاجة تتعمل")
        return 0

    if args.command == "structure":
        log_schema_changes(ensure_schema())
        db = SessionLocal()
        created = structure.build(db, academic_year=args.year)
        db.close()
        log(
            f"✓ اتضاف {created['curricula']} منهج · "
            f"{created['grades']} صف · {created['subjects']} مادة"
        )
        return 0

    if args.command == "status":
        ensure_schema()
        _print_status()
        return 0

    try:
        entries = read_entries(args.source)
    except OSError as error:
        explain_read_error(args.source, error)
        log("")
        log("حضّر ملف الروابط الأول:")
        log("  bash deploy/books.sh crawl                 # من موقع الوزارة مباشرة")
        log("  bash deploy/books.sh html <صفحاتك.html>    # من صفحات محفوظة")
        return 1

    if not entries:
        log(f"✗ مفيش روابط في {args.source}")
        return 1
    log(f"اتقرا {len(entries)} رابط من {args.source}")

    import_entries(
        entries,
        dry_run=args.command == "plan",
        delay=getattr(args, "delay", 0.5),
        limit=args.limit,
        replace=getattr(args, "replace", False),
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
