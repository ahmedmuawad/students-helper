"""إعداد اتصال قاعدة البيانات وجلسات SQLAlchemy."""

from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.core.config import get_settings

settings = get_settings()

# pool_pre_ping بيتأكد إن الاتصال لسه حي قبل الاستخدام — مهم على سيرفر
# بيفضل شغال أيام من غير إعادة تشغيل.
engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,
    pool_size=10,
    max_overflow=20,
    future=True,
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    """الأساس اللي كل الجداول بترث منه."""


def get_db() -> Iterator[Session]:
    """يوفّر جلسة قاعدة بيانات لكل طلب ويقفلها بعده."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
