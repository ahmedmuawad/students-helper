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
from urllib.parse import urlparse

import httpx
from sqlalchemy.orm import Session

from app.core.database import Base, SessionLocal, engine
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


@dataclass
class Entry:
    url: str
    title: str


def read_entries(path: str) -> list[Entry]:
    """يقرأ ملف روابط، ويربط كل رابط بالسطور العربية اللي قبله كعنوان."""
    entries: list[Entry] = []
    buffer: list[str] = []

    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line or set(line) <= {"-", "=", "_"}:
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
) -> None:
    Base.metadata.create_all(bind=engine)
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

    downloaded = 0
    reused = 0
    failed = 0
    lessons_created = 0

    with httpx.Client(timeout=180, follow_redirects=True) as client:
        for index, (entry, ref) in enumerate(parsed, start=1):
            if limit and downloaded + reused >= limit:
                break

            # المادة المشتركة بتتسجّل في المنهجين (عربي ولغات)
            languages = (
                ["arabic", "languages"] if ref.is_shared else [ref.language]
            )

            try:
                response = client.get(ref.url)
                if response.status_code != 200:
                    log(f"  ✗ [{index}/{len(parsed)}] {response.status_code} — "
                        f"{ref.subject_name_ar} صف {ref.grade_level}")
                    failed += 1
                    continue
                content = response.content
            except httpx.HTTPError as error:
                log(f"  ✗ [{index}/{len(parsed)}] فشل التحميل: {error}")
                failed += 1
                continue

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
                    reused += 1
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
                lessons_created += _import_toc(db, subject, ref.term, content)
                downloaded += 1

            db.commit()
            log(
                f"  ✓ [{index}/{len(parsed)}] {ref.subject_name_ar} · "
                f"صف {ref.grade_level} · ترم {ref.term} · {ref.language}"
            )
            time.sleep(delay)

    db.close()
    log(
        f"\nخلص: {downloaded} ملف جديد · {reused} موجود قبل كده · "
        f"{failed} فشل · {lessons_created} درس من الفهارس"
    )


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

    plan = sub.add_parser("plan", help="معاينة من غير تنزيل")
    plan.add_argument("--from", dest="source", required=True)
    plan.add_argument("--limit", type=int)

    run = sub.add_parser("import", help="التنزيل والاستيراد")
    run.add_argument("--from", dest="source", required=True)
    run.add_argument("--limit", type=int, help="عدد الكتب (للتجربة)")
    run.add_argument("--delay", type=float, default=0.5,
                     help="ثواني بين كل تحميل والتاني")

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
        results: list[tuple[str, str]] = []
        seen: set[str] = set()
        for path in args.files:
            found = from_html_file(path)
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

    if args.command == "structure":
        Base.metadata.create_all(bind=engine)
        db = SessionLocal()
        created = structure.build(db, academic_year=args.year)
        db.close()
        log(
            f"✓ اتضاف {created['curricula']} منهج · "
            f"{created['grades']} صف · {created['subjects']} مادة"
        )
        return 0

    if args.command == "status":
        Base.metadata.create_all(bind=engine)
        _print_status()
        return 0

    entries = read_entries(args.source)
    log(f"اتقرا {len(entries)} رابط من {args.source}")

    import_entries(
        entries,
        dry_run=args.command == "plan",
        delay=getattr(args, "delay", 0.5),
        limit=args.limit,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
