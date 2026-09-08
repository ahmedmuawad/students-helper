"""مزامنة الجداول الموجودة مع الموديلات (من غير Alembic).

`create_all` بينشئ الجداول الناقصة بس — عمره ما بيعدّل جدول موجود.
يعني لما بنضيف قيمة جديدة لـ Enum (زي `kindergarten`) أو عمود جديد،
الجدول القديم على السيرفر بيفضل زي ما هو والإدخال بيقع بـ:

    (1265, "Data truncated for column 'stage' at row 1")

الموديول ده بيقارن الموديلات باللي فعلاً في قاعدة البيانات وبينفّذ
الـ ALTER الناقص بس. كله إضافي (بيوسّع ومبيضيّقش) وممكن يتنفّذ أكتر
من مرة من غير أي أثر جانبي.
"""

from __future__ import annotations

import re

from sqlalchemy import MetaData, inspect, text
from sqlalchemy.engine import Connection, Engine
from sqlalchemy.schema import CreateColumn
from sqlalchemy.sql.sqltypes import Enum as SAEnum

from app.core.database import Base, engine as default_engine

# القيم جوه enum('a','b') — والاقتباس المزدوج '' معناه علامة اقتباس عادية.
_ENUM_VALUE = re.compile(r"'((?:[^']|'')*)'")


def _db_enum_values(conn: Connection, table: str, column: str) -> list[str] | None:
    """قيم الـ ENUM زي ما هي مخزّنة في MySQL، أو None لو العمود مش ENUM."""
    column_type = conn.execute(
        text(
            "SELECT COLUMN_TYPE FROM information_schema.COLUMNS "
            "WHERE TABLE_SCHEMA = DATABASE() "
            "AND TABLE_NAME = :table AND COLUMN_NAME = :column"
        ),
        {"table": table, "column": column},
    ).scalar()
    if not column_type:
        return None
    if not column_type.lower().startswith("enum("):
        return None
    inner = column_type[len("enum(") : column_type.rfind(")")]
    return [match.group(1).replace("''", "'") for match in _ENUM_VALUE.finditer(inner)]


def _column_ddl(column, dialect) -> str:
    """يرندر تعريف العمود زي ما create_all كان هيعمله."""
    return str(CreateColumn(column).compile(dialect=dialect)).strip()


def sync_schema(
    bind: Engine | None = None,
    metadata: MetaData | None = None,
    *,
    dry_run: bool = False,
) -> list[str]:
    """يظبّط الجداول الموجودة على الموديلات ويرجّع وصف اللي اتعمل.

    بيعمل حاجتين بس، والاتنين إضافيين:

    * توسيع أعمدة ENUM في MySQL عشان تشيل القيم الجديدة.
    * إضافة الأعمدة الناقصة من جدول موجود.

    مبيحذفش عمود ولا قيمة ولا بيغيّر نوع — ده شغل ترحيل حقيقي (Alembic)
    ولازم يتعمل بإيد واعية.
    """
    bind = bind or default_engine
    metadata = metadata or Base.metadata
    dialect = bind.dialect
    is_mysql = dialect.name in {"mysql", "mariadb"}
    preparer = dialect.identifier_preparer

    changes: list[str] = []
    statements: list[str] = []

    with bind.connect() as conn:
        inspector = inspect(conn)
        existing_tables = set(inspector.get_table_names())

        for table in metadata.sorted_tables:
            if table.name not in existing_tables:
                # جدول جديد بالكامل — create_all هو اللي بينشئه.
                continue

            db_columns = {
                info["name"]: info for info in inspector.get_columns(table.name)
            }
            quoted_table = preparer.format_table(table)

            for column in table.columns:
                if column.name not in db_columns:
                    ddl = _column_ddl(column, dialect)
                    statements.append(f"ALTER TABLE {quoted_table} ADD COLUMN {ddl}")
                    changes.append(f"+ عمود {table.name}.{column.name}")
                    continue

                if not is_mysql or not isinstance(column.type, SAEnum):
                    continue

                wanted = list(column.type.enums)
                current = _db_enum_values(conn, table.name, column.name)
                if current is None:
                    continue
                missing = [value for value in wanted if value not in current]
                if not missing:
                    continue

                ddl = _column_ddl(column, dialect)
                statements.append(f"ALTER TABLE {quoted_table} MODIFY COLUMN {ddl}")
                changes.append(
                    f"~ {table.name}.{column.name}: اتضاف {', '.join(missing)}"
                )

    if dry_run or not statements:
        return changes

    with bind.begin() as conn:
        for statement in statements:
            conn.exec_driver_sql(statement)

    return changes
