#!/usr/bin/env bash
#
# بناء نسخة APK على السيرفر.
#
#   sudo bash backend/deploy/build_apk.sh
#
# بيسطّب Flutter وأدوات أندرويد أول مرة بس (حوالي ٦ جيجا)، وبعدها
# البناء بياخد دقايق. الملف الناتج بيتحط في /root/students-helper.apk
#
# بديل أسهل لو GitHub Actions شغّال على حسابك: التبويب Actions في
# المستودع → "بناء تطبيق أندرويد" → Run workflow، والـAPK بينزل من
# صفحة التشغيل من غير ما تسطّب حاجة.
#
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.2}"
TOOLS_DIR="${TOOLS_DIR:-/opt/flutter-build}"
API_URL="${API_URL:-https://student-helper.stop4web.online}"
OUT="${OUT:-/root/students-helper.apk}"

DOMAIN="${DOMAIN:-student-helper.stop4web.online}"
SITE_USER="${SITE_USER:-stop4web-student-helper}"
APP_DIR="/home/${SITE_USER}/htdocs/${DOMAIN}"

log()  { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m  ✗ %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "شغّله بـ sudo"
[[ -d "$APP_DIR" ]] || fail "المشروع مش موجود في ${APP_DIR}"

FREE_GB=$(df -BG --output=avail /opt | tail -1 | tr -dc '0-9')
[[ "${FREE_GB:-0}" -ge 8 ]] || fail "محتاج ٨ جيجا فاضية على الأقل (المتاح ${FREE_GB}G)"

mkdir -p "$TOOLS_DIR"

# ---------------------------------------------------------------- الأدوات

log "جافا"
if ! command -v java >/dev/null; then
  apt-get update -qq && apt-get install -y -qq openjdk-17-jdk-headless unzip curl
fi
export JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"
ok "$(java -version 2>&1 | head -1)"

log "Flutter"
if [[ ! -x "${TOOLS_DIR}/flutter/bin/flutter" ]]; then
  curl -fsSL -o /tmp/flutter.tar.xz \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  tar -xf /tmp/flutter.tar.xz -C "$TOOLS_DIR"
  rm -f /tmp/flutter.tar.xz
fi
export PATH="${TOOLS_DIR}/flutter/bin:$PATH"
git config --global --add safe.directory "${TOOLS_DIR}/flutter" || true
ok "$(flutter --version 2>/dev/null | head -1)"

log "أدوات أندرويد"
export ANDROID_SDK_ROOT="${TOOLS_DIR}/android-sdk"
SDKMANAGER="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager"
if [[ ! -x "$SDKMANAGER" ]]; then
  mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools"
  curl -fsSL -o /tmp/cmdline.zip \
    "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  unzip -q /tmp/cmdline.zip -d "${ANDROID_SDK_ROOT}/cmdline-tools"
  mv "${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools" \
     "${ANDROID_SDK_ROOT}/cmdline-tools/latest"
  rm -f /tmp/cmdline.zip
fi
yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
"$SDKMANAGER" --install "platform-tools" "platforms;android-35" \
  "build-tools;35.0.0" >/dev/null
flutter config --android-sdk "$ANDROID_SDK_ROOT" >/dev/null
ok "تم"

# ---------------------------------------------------------------- البناء

log "سحب آخر نسخة"
sudo -u "$SITE_USER" git -C "$APP_DIR" pull --ff-only || true

if [[ -f "${APP_DIR}/android/app/google-services.json" ]]; then
  ok "إعدادات Firebase موجودة — تسجيل الدخول هيشتغل"
else
  printf '\033[1;33m  ⚠ google-services.json مش موجود — النسخة دي من غير تسجيل دخول\033[0m\n'
  printf '    الخطوات في docs/FIREBASE.md\n'
fi

log "البناء (بياخد دقايق)"
cd "$APP_DIR"
flutter pub get
flutter build apk --release --dart-define="API_BASE_URL=${API_URL}"

cp build/app/outputs/flutter-apk/app-release.apk "$OUT"
chmod 644 "$OUT"

SIZE=$(du -h "$OUT" | cut -f1)
log "خلص"
ok "الملف: ${OUT} (${SIZE})"
printf '\n  نزّله على جهازك بالأمر ده من الكمبيوتر بتاعك:\n'
printf '    scp root@%s:%s .\n\n' "${SERVER_IP:-<عنوان-السيرفر>}" "$OUT"
