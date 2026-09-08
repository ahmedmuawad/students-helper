"""إعداد اتصال قاعدة البيانات وجلسات SQLAlchemy."""

from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.core.config import get_settings

settings = get_settings()

# pool_pre_ping بيتأكد إن الاتصال لسه حي قبل الاستخدام — مهم على سيرفر
# بيفضل شغال أيام من غير إعادة تشغيل.
# pool_pre_ping بيتأكد إن الاتصال لسه حي قبل الاستخدام، و pool_recycle
# بيجدّد الاتصالات قبل ما MySQL يقفلها (wait_timeout الافتراضي 8 ساعات).
_engine_options: dict = {
    "pool_pre_ping": True,
    "pool_size": 10,
    "max_overflow": 20,
    "future": True,
}
if settings.database_url.startswith("mysql"):
    _engine_options["pool_recycle"] = 3600
elif settings.database_url.startswith("sqlite"):
    # SQLite للتطوير المحلي فقط — مبيدعمش تجميع الاتصالات بنفس الشكل.
    _engine_options = {"future": True}

engine = create_engine(settings.database_url, **_engine_options)

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
