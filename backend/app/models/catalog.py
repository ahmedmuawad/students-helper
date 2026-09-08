"""جداول المناهج والكتب.

الشجرة: منهج (دولة + نظام + لغة) ← صف ← مادة ← وحدة ← درس
والكتب بتترّبط بالمادة والترم، وممكن تترّبط بدرس لفتح صفحته مباشرة.
"""

from __future__ import annotations

import enum
from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class EducationStage(str, enum.Enum):
    kindergarten = "kindergarten"
    primary = "primary"
    preparatory = "preparatory"
    secondary = "secondary"


class BookKind(str, enum.Enum):
    """تصنيف المادة التعليمية المرفوعة."""

    textbook = "textbook"        # كتاب الوزارة
    workbook = "workbook"        # كتاب الأنشطة
    booklet = "booklet"          # ملزمة
    revision = "revision"        # مراجعة نهائية
    exam = "exam"                # نماذج امتحانات
    teacher_guide = "teacher_guide"  # دليل المعلم
    other = "other"


class Curriculum(Base):
    """منهج = دولة + نظام تعليمي + لغة الدراسة + سنة دراسية."""

    __tablename__ = "curricula"
    __table_args__ = (
        UniqueConstraint(
            "country_code", "system_id", "language", "academic_year",
            name="uq_curriculum_identity",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    country_code: Mapped[str] = mapped_column(String(2), index=True)
    system_id: Mapped[str] = mapped_column(String(40), index=True)
    language: Mapped[str] = mapped_column(String(20), default="arabic")
    academic_year: Mapped[str] = mapped_column(String(12), default="2025/2026")

    name_ar: Mapped[str] = mapped_column(String(160))
    name_en: Mapped[str] = mapped_column(String(160), default="")

    is_published: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    grades: Mapped[list["Grade"]] = relationship(
        back_populates="curriculum",
        cascade="all, delete-orphan",
        order_by="Grade.level",
    )


class Grade(Base):
    """صف دراسي داخل منهج معيّن."""

    __tablename__ = "grades"
    __table_args__ = (
        UniqueConstraint("curriculum_id", "level", name="uq_grade_level"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    curriculum_id: Mapped[int] = mapped_column(
        ForeignKey("curricula.id", ondelete="CASCADE"), index=True
    )
    level: Mapped[int] = mapped_column(Integer)          # 1..12
    stage: Mapped[EducationStage] = mapped_column(Enum(EducationStage))
    name_ar: Mapped[str] = mapped_column(String(80))
    name_en: Mapped[str] = mapped_column(String(80), default="")

    # المسار الدراسي للثانوي (مسارات البكالوريا الأربعة مثلاً)
    track_id: Mapped[str] = mapped_column(String(40), default="")

    curriculum: Mapped[Curriculum] = relationship(back_populates="grades")
    subjects: Mapped[list["Subject"]] = relationship(
        back_populates="grade",
        cascade="all, delete-orphan",
        order_by="Subject.sort_order",
    )


class Subject(Base):
    """مادة دراسية في صف معيّن."""

    __tablename__ = "subjects"

    id: Mapped[int] = mapped_column(primary_key=True)
    grade_id: Mapped[int] = mapped_column(
        ForeignKey("grades.id", ondelete="CASCADE"), index=True
    )
    slug: Mapped[str] = mapped_column(String(60), index=True)
    name_ar: Mapped[str] = mapped_column(String(120))
    name_en: Mapped[str] = mapped_column(String(120), default="")
    color: Mapped[str] = mapped_column(String(9), default="#2E7D91")

    # في نظام البكالوريا فيه مواد لا تُضاف للمجموع
    counts_toward_total: Mapped[bool] = mapped_column(Boolean, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)

    grade: Mapped[Grade] = relationship(back_populates="subjects")
    units: Mapped[list["Unit"]] = relationship(
        back_populates="subject",
        cascade="all, delete-orphan",
        order_by="Unit.number",
    )
    books: Mapped[list["Book"]] = relationship(
        back_populates="subject", cascade="all, delete-orphan"
    )


class Unit(Base):
    """وحدة داخل المادة، في ترم معيّن."""

    __tablename__ = "units"

    id: Mapped[int] = mapped_column(primary_key=True)
    subject_id: Mapped[int] = mapped_column(
        ForeignKey("subjects.id", ondelete="CASCADE"), index=True
    )
    term: Mapped[int] = mapped_column(Integer, default=1)   # 1 أو 2
    number: Mapped[int] = mapped_column(Integer, default=1)
    title_ar: Mapped[str] = mapped_column(String(200))
    title_en: Mapped[str] = mapped_column(String(200), default="")

    subject: Mapped[Subject] = relationship(back_populates="units")
    lessons: Mapped[list["Lesson"]] = relationship(
        back_populates="unit",
        cascade="all, delete-orphan",
        order_by="Lesson.number",
    )


class Lesson(Base):
    """درس داخل وحدة — ده اللي خطة المذاكرة بتتبني عليه."""

    __tablename__ = "lessons"

    id: Mapped[int] = mapped_column(primary_key=True)
    unit_id: Mapped[int] = mapped_column(
        ForeignKey("units.id", ondelete="CASCADE"), index=True
    )
    number: Mapped[int] = mapped_column(Integer, default=1)
    title_ar: Mapped[str] = mapped_column(String(240))
    title_en: Mapped[str] = mapped_column(String(240), default="")

    # صفحات الدرس في كتاب الوزارة — بتخلي التطبيق يفتح الكتاب على الدرس
    # مباشرة، ويطبع صفحات الدرس بس.
    page_start: Mapped[int | None] = mapped_column(Integer, nullable=True)
    page_end: Mapped[int | None] = mapped_column(Integer, nullable=True)

    # مدخلات خوارزمية توزيع خطة المذاكرة
    estimated_minutes: Mapped[int] = mapped_column(Integer, default=45)
    difficulty: Mapped[int] = mapped_column(Integer, default=3)   # 1..5

    unit: Mapped[Unit] = relationship(back_populates="lessons")


class Book(Base):
    """كتاب أو ملزمة أو مراجعة مرفوعة من لوحة التحكم."""

    __tablename__ = "books"

    id: Mapped[int] = mapped_column(primary_key=True)
    subject_id: Mapped[int] = mapped_column(
        ForeignKey("subjects.id", ondelete="CASCADE"), index=True
    )
    kind: Mapped[BookKind] = mapped_column(Enum(BookKind), default=BookKind.textbook)
    term: Mapped[int] = mapped_column(Integer, default=1)

    title_ar: Mapped[str] = mapped_column(String(240))
    title_en: Mapped[str] = mapped_column(String(240), default="")
    publisher: Mapped[str] = mapped_column(String(160), default="")

    # المصدر ومعلومات الحقوق — مهم نوثّقها لكل ملف مرفوع.
    source_url: Mapped[str] = mapped_column(Text, default="")
    license_note: Mapped[str] = mapped_column(Text, default="")

    file_path: Mapped[str] = mapped_column(Text)          # مسار نسبي داخل media
    file_size: Mapped[int] = mapped_column(Integer, default=0)
    page_count: Mapped[int] = mapped_column(Integer, default=0)
    cover_path: Mapped[str] = mapped_column(Text, default="")
    checksum: Mapped[str] = mapped_column(String(64), default="")

    is_published: Mapped[bool] = mapped_column(Boolean, default=False)
    download_count: Mapped[int] = mapped_column(Integer, default=0)
    sort_order: Mapped[float] = mapped_column(Float, default=0)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    subject: Mapped[Subject] = relationship(back_populates="books")
