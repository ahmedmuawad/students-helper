#!/usr/bin/env bash
#
# تركيب "مساعد الطالب" على سيرفر CloudPanel.
# السيرفر بيسحب الكود من GitHub مباشرة — مفيش رفع ملفات يدوي.
#
#   sudo bash install.sh
#
set -euo pipefail

# ---------------- إعدادات الموقع ----------------
DOMAIN="${DOMAIN:-student-helper.stop4web.online}"
SITE_USER="${SITE_USER:-stop4web-student-helper}"
APP_PORT="${APP_PORT:-8090}"
PYTHON_BIN="${PYTHON_BIN:-python3.10}"
REPO_URL="${REPO_URL:-https://github.com/ahmedmuawad/students-helper.git}"
BRANCH="${BRANCH:-claude/flutter-student-management-app-8bhzc6}"

APP_DIR="/home/${SITE_USER}/htdocs/${DOMAIN}"
BACKEND_DIR="${APP_DIR}/backend"
VENV_DIR="${APP_DIR}/.venv"
MEDIA_DIR="${APP_DIR}/media"
ENV_FILE="${BACKEND_DIR}/.env"
SERVICE_NAME="students-helper"

log()  { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m  ✗ %s\033[0m\n' "$*" >&2; exit 1; }

as_site() { sudo -u "$SITE_USER" "$@"; }

if [[ $EUID -ne 0 ]]; then
  fail "السكربت محتاج صلاحيات root.

  مستخدم الموقع في CloudPanel (${USER}) معندوش sudo — وده مقصود للأمان.
  ادخل بمستخدم root وشغّله من هناك:

      ssh root@SERVER_IP
      curl -fsSLO ${RAW_URL:-https://raw.githubusercontent.com/ahmedmuawad/students-helper/main/backend/deploy/install.sh}
      bash install.sh

  (لو بتدخل بمستخدم تاني عنده sudo، استخدم: sudo bash install.sh)"
fi

id "$SITE_USER" >/dev/null 2>&1 || fail "المستخدم ${SITE_USER} مش موجود — اعمل الـ Python Site من CloudPanel الأول"
[[ -d "$APP_DIR" ]] || fail "مجلد الموقع مش موجود: ${APP_DIR}"

# ------------------------------------------------------------ حزم النظام
log "تثبيت حزم النظام"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# MySQL موجود أصلاً مع CloudPanel، فمحتاجين بايثون وgit وأدوات البناء بس.
apt-get install -y -qq git \
  "${PYTHON_BIN}" "${PYTHON_BIN}-venv" "${PYTHON_BIN}-dev" build-essential >/dev/null
ok "تم"

# ------------------------------------------------------------ سحب الكود
log "سحب الكود من GitHub"
# git بيرفض يشتغل على مجلد مملوك لمستخدم تاني، فبنسمح بالمسار ده صراحة.
as_site git config --global --add safe.directory "$APP_DIR" 2>/dev/null || true

if [[ -d "${APP_DIR}/.git" ]]; then
  as_site git -C "$APP_DIR" fetch --depth 1 origin "$BRANCH"
  as_site git -C "$APP_DIR" checkout -f -B "$BRANCH" "origin/${BRANCH}"
  ok "تم التحديث لآخر نسخة"
else
  # المجلد ممكن يكون فيه ملفات افتراضية من CloudPanel، فبنهيّئ مستودع
  # جوّاه بدل clone (اللي بيرفض المجلدات غير الفاضية).
  as_site git -C "$APP_DIR" init -q
  as_site git -C "$APP_DIR" remote add origin "$REPO_URL" 2>/dev/null || \
    as_site git -C "$APP_DIR" remote set-url origin "$REPO_URL"

  if ! as_site git -C "$APP_DIR" fetch --depth 1 origin "$BRANCH"; then
    fail "فشل السحب من GitHub.
  لو المستودع خاص، جهّز الوصول الأول (اختار واحدة):

  (أ) مفتاح نشر SSH — الأأمن، للقراءة فقط:
      sudo -u ${SITE_USER} ssh-keygen -t ed25519 -N '' -f /home/${SITE_USER}/.ssh/id_ed25519
      sudo cat /home/${SITE_USER}/.ssh/id_ed25519.pub
      ضيف المفتاح ده في: GitHub ← المستودع ← Settings ← Deploy keys
      وبعدين شغّل السكربت تاني بـ:
      sudo REPO_URL=git@github.com:ahmedmuawad/students-helper.git bash install.sh

  (ب) توكن وصول شخصي بصلاحية قراءة المحتوى:
      sudo REPO_URL=https://TOKEN@github.com/ahmedmuawad/students-helper.git bash install.sh"
  fi

  as_site git -C "$APP_DIR" checkout -f -B "$BRANCH" "origin/${BRANCH}"
  ok "تم سحب الكود"
fi

[[ -f "${BACKEND_DIR}/requirements.txt" ]] || fail "مش لاقي backend/requirements.txt بعد السحب"

# ------------------------------------------------------------ بيئة بايثون
log "تجهيز بيئة بايثون"
if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  as_site "$PYTHON_BIN" -m venv "$VENV_DIR"
fi
as_site "${VENV_DIR}/bin/pip" install --quiet --upgrade pip wheel
as_site "${VENV_DIR}/bin/pip" install --quiet -r "${BACKEND_DIR}/requirements.txt"
ok "الحزم اتثبتت"

# ------------------------------------------------------------ ملف الإعدادات
if [[ -f "$ENV_FILE" ]]; then
  log "ملف .env موجود — مش هيتغيّر"
  ok "لو عايز تعدّله: ${ENV_FILE}"
else
  log "إعداد الاتصال بقاعدة البيانات"
  echo "  (البيانات من CloudPanel ← Databases)"
  read -rp  "  اسم قاعدة البيانات: " DB_NAME
  read -rp  "  اسم المستخدم: " DB_USER
  read -rsp "  كلمة المرور: " DB_PASS; echo

  # نتأكد من الاتصال قبل ما نكمّل، بدل ما نكتشف الغلط بعد التركيب.
  if command -v mysql >/dev/null 2>&1; then
    if mysql -h 127.0.0.1 -u "$DB_USER" -p"$DB_PASS" \
         -e "USE \`${DB_NAME}\`;" >/dev/null 2>&1; then
      ok "الاتصال بقاعدة البيانات ناجح"
    else
      fail "مش قادر أتصل بقاعدة البيانات — راجع البيانات"
    fi
  else
    warn "أداة mysql مش متاحة — هنكمّل من غير اختبار الاتصال"
  fi

  log "إعداد لوحة التحكم"
  read -rp  "  البريد الإلكتروني للأدمن: " ADMIN_EMAIL
  read -rsp "  كلمة مرور لوحة التحكم: " ADMIN_PW; echo

  # الباسورد ممكن يكون فيه رموز (@ أو /) تكسر رابط الاتصال، فبنرمّزها.
  ENCODED="$("${VENV_DIR}/bin/python" "${BACKEND_DIR}/deploy/make_env.py" \
    "$DB_USER" "$DB_PASS" "$DB_NAME" "$ADMIN_PW")"
  DB_USER_ENC="$(sed -n 1p <<<"$ENCODED")"
  DB_PASS_ENC="$(sed -n 2p <<<"$ENCODED")"
  DB_NAME_ENC="$(sed -n 3p <<<"$ENCODED")"
  ADMIN_HASH="$(sed -n 4p <<<"$ENCODED")"

  SESSION_SECRET="$(openssl rand -hex 32)"

  umask 077
  cat > "$ENV_FILE" <<ENVFILE
ENVIRONMENT=production
DEBUG=false

# charset=utf8mb4 ضروري عشان العربية والإيموجي تتخزّن صح
DATABASE_URL=mysql+pymysql://${DB_USER_ENC}:${DB_PASS_ENC}@127.0.0.1:3306/${DB_NAME_ENC}?charset=utf8mb4

# يتحدد من لوحة التحكم ← إعدادات التكامل
FIREBASE_PROJECT_ID=

MEDIA_ROOT=${MEDIA_DIR}
MEDIA_URL_PREFIX=/media
MAX_UPLOAD_MB=200

ADMIN_SESSION_SECRET=${SESSION_SECRET}
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_PASSWORD_HASH=${ADMIN_HASH}

CORS_ORIGINS=https://${DOMAIN}
ENVFILE
  chown "${SITE_USER}:${SITE_USER}" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  ok "الملف اتكتب ومحمي (600)"
fi

# ------------------------------------------------------------ مجلد الكتب
log "تجهيز مجلد الكتب"
mkdir -p "$MEDIA_DIR"
chown -R "${SITE_USER}:${SITE_USER}" "$MEDIA_DIR"
ok "$MEDIA_DIR"

# ------------------------------------------------------------ الخدمة
log "تسجيل الخدمة"
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<SERVICE
[Unit]
Description=Students Helper API
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
User=${SITE_USER}
Group=${SITE_USER}
WorkingDirectory=${BACKEND_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=${VENV_DIR}/bin/uvicorn app.main:app --host 127.0.0.1 --port ${APP_PORT} --workers 2 --proxy-headers --forwarded-allow-ips=127.0.0.1
Restart=always
RestartSec=5

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=read-only
ReadWritePaths=${MEDIA_DIR}

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable "$SERVICE_NAME" >/dev/null
systemctl restart "$SERVICE_NAME"
sleep 4

if ! systemctl is-active --quiet "$SERVICE_NAME"; then
  journalctl -u "$SERVICE_NAME" -n 40 --no-pager
  fail "الخدمة مش شغالة — الأخطاء فوق"
fi
ok "الخدمة شغالة"

# ------------------------------------------------------------ التحقق
log "اختبار السيرفر"
for attempt in 1 2 3 4 5; do
  if curl -fsS "http://127.0.0.1:${APP_PORT}/health" >/dev/null 2>&1; then
    ok "السيرفر بيرد على /health"
    break
  fi
  [[ $attempt -eq 5 ]] && fail "السيرفر مش بيرد على البورت ${APP_PORT}"
  sleep 3
done

cat <<DONE

────────────────────────────────────────────────
 ✅ التركيب خلص

 لوحة التحكم:  https://${DOMAIN}/admin
 توثيق الـAPI: https://${DOMAIN}/api/docs

 الخطوات الجاية:
  1. فعّل SSL من CloudPanel (Sites ← SSL/TLS ← Let's Encrypt)
  2. من لوحة التحكم ← إعدادات التكامل: حط مفاتيح
     Firebase و AdMob و Google Play
  3. غيّر باسورد Site User وقاعدة البيانات من CloudPanel

 للتحديث بعد أي تعديل على الكود:
  sudo bash ${BACKEND_DIR}/deploy/update.sh

 متابعة الخدمة:
  systemctl status ${SERVICE_NAME}
  journalctl -u ${SERVICE_NAME} -f
────────────────────────────────────────────────
DONE
