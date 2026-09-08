"""اختبارات مزامنة الجداول مع الموديلات.

بتعيد إنتاج العطل اللي ظهر على السيرفر بالظبط: جدول `grades` اتعمل قبل
ما `kindergarten` تتضاف لـ EducationStage، فالـ ENUM في MySQL فضل ناقص
والإدخال وقع بـ (1265, "Data truncated for column 'stage' at row 1").
"""

from __future__ import annotations

import os

import pytest
from sqlalchemy import create_engine, insert, inspect, select, text

from app.core.database import Base
from app.core.schema_sync import sync_schema
from app.models import Curriculum, EducationStage, Grade

MYSQL_URL = os.environ.get("TEST_MYSQL_URL")


def _fresh_engine(url: str):
    engine = create_engine(url, future=True)
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    return engine


# --------------------------------------------------------------------------
# SQLite — الأعمدة الناقصة
# --------------------------------------------------------------------------


def test_adds_missing_column(tmp_path):
    """عمود اتضاف للموديل بعد ما الجدول اتعمل — لازم يترجّع."""
    engine = _fresh_engine(f"sqlite:///{tmp_path / 'drift.db'}")

    with engine.begin() as conn:
        conn.exec_driver_sql("ALTER TABLE books DROP COLUMN publisher")

    assert "publisher" not in {
        column["name"] for column in inspect(engine).get_columns("books")
    }

    changes = sync_schema(engine)

    assert any("books.publisher" in change for change in changes)
    assert "publisher" in {
        column["name"] for column in inspect(engine).get_columns("books")
    }
    # التشغيل التاني مالوش أثر
    assert sync_schema(engine) == []


def test_no_changes_on_a_matching_schema(tmp_path):
    engine = _fresh_engine(f"sqlite:///{tmp_path / 'clean.db'}")
    assert sync_schema(engine) == []


# --------------------------------------------------------------------------
# MySQL — قيم ENUM الناقصة (العطل الأصلي)
# --------------------------------------------------------------------------

mysql_only = pytest.mark.skipif(
    not MYSQL_URL, reason="محتاج TEST_MYSQL_URL عشان يشتغل على MySQL حقيقي"
)


@mysql_only
def test_widens_a_stale_enum():
    engine = _fresh_engine(MYSQL_URL)

    # نرجّع الجدول لحالته القديمة: ENUM من غير kindergarten
    with engine.begin() as conn:
        conn.exec_driver_sql(
            "ALTER TABLE grades MODIFY COLUMN stage "
            "ENUM('primary','preparatory','secondary') NOT NULL"
        )
        conn.execute(
            insert(Curriculum),
            {
                "country_code": "EG",
                "system_id": "national",
                "language": "ar",
                "academic_year": "2026/2027",
                "name_ar": "قومي",
                "name_en": "National",
            },
        )

    # قبل التظبيط: الإدخال بيقع زي ما وقع على السيرفر
    with pytest.raises(Exception) as caught:
        with engine.begin() as conn:
            conn.exec_driver_sql(
                "INSERT INTO grades (curriculum_id, level, stage, name_ar, "
                "name_en, track_id) VALUES (1, -1, 'kindergarten', 'كي جي ١', "
                "'KG1', '')"
            )
    assert "1265" in str(caught.value) or "truncat" in str(caught.value).lower()

    changes = sync_schema(engine)
    assert any("grades.stage" in change and "kindergarten" in change
               for change in changes)

    # وبعده بيعدّي
    with engine.begin() as conn:
        conn.exec_driver_sql(
            "INSERT INTO grades (curriculum_id, level, stage, name_ar, "
            "name_en, track_id) VALUES (1, -1, 'kindergarten', 'كي جي ١', "
            "'KG1', '')"
        )
        stored = conn.execute(
            text("SELECT stage FROM grades WHERE level = -1")
        ).scalar()
    assert stored == "kindergarten"

    # القيم القديمة زي ما هي، والتشغيل التاني مالوش أثر
    with engine.connect() as conn:
        column_type = conn.execute(
            text(
                "SELECT COLUMN_TYPE FROM information_schema.COLUMNS "
                "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'grades' "
                "AND COLUMN_NAME = 'stage'"
            )
        ).scalar()
    for stage in EducationStage:
        assert stage.value in column_type
    assert sync_schema(engine) == []


@mysql_only
def test_structure_runs_after_the_repair():
    """اللي المستخدم شغّله على السيرفر: migrate بعديه structure."""
    from sqlalchemy.orm import Session

    from app.tools import structure

    engine = _fresh_engine(MYSQL_URL)
    with engine.begin() as conn:
        conn.exec_driver_sql(
            "ALTER TABLE grades MODIFY COLUMN stage "
            "ENUM('primary','preparatory','secondary') NOT NULL"
        )

    sync_schema(engine)

    with Session(engine) as db:
        created = structure.build(db, academic_year="2026/2027")
        kg = db.execute(
            select(Grade).where(Grade.stage == EducationStage.kindergarten)
        ).scalars().all()

    assert created["grades"] > 0
    assert kg, "المفروض اتعمل صفوف رياض أطفال"
