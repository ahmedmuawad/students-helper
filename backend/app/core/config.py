"""إعدادات التطبيق — كلها بتتقرأ من متغيرات البيئة."""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "مساعد الطالب"
    environment: str = "development"
    debug: bool = False

    # قاعدة البيانات. CloudPanel بيوفّر MySQL جاهز، فده الافتراضي.
    # charset=utf8mb4 ضروري عشان العربية والإيموجي تتخزّن صح.
    database_url: str = (
        "mysql+pymysql://students:students@127.0.0.1:3306/students_helper"
        "?charset=utf8mb4"
    )

    # Firebase بيتستخدم لتسجيل الدخول فقط؛ السيرفر بيتحقق من التوكن.
    firebase_project_id: str = ""

    # يسمح بتخطي التحقق من Firebase في التطوير المحلي فقط.
    allow_dev_tokens: bool = False

    # تخزين ملفات الكتب على قرص السيرفر (nginx بيخدمها مباشرة).
    media_root: str = "./media"
    media_url_prefix: str = "/media"

    # حد أقصى لحجم الملف المرفوع (بالميجابايت).
    max_upload_mb: int = 200

    # جلسة لوحة التحكم
    admin_session_secret: str = "change-me-in-production"
    admin_email: str = "admin@example.com"
    admin_password_hash: str = ""

    # قائمة الأصول المسموح لها بالاتصال
    cors_origins: str = "*"

    @property
    def cors_origin_list(self) -> list[str]:
        if self.cors_origins.strip() == "*":
            return ["*"]
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def max_upload_bytes(self) -> int:
        return self.max_upload_mb * 1024 * 1024


@lru_cache
def get_settings() -> Settings:
    return Settings()
