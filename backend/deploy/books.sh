#!/usr/bin/env bash
#
# اختصار لأوامر استيراد كتب الوزارة.
#
#   sudo bash deploy/books.sh crawl                   # كل المراحل من مكتبة الوزارة
#   sudo bash deploy/books.sh crawl <رابط صفحة>       # صفحة واحدة
#   sudo bash deploy/books.sh probe [الصفوف]          # تخمين الروابط
#   sudo bash deploy/books.sh list                    # فهرس المكتبة (لو مسموح)
#   sudo bash deploy/books.sh plan catalog.txt        # معاينة من غير تنزيل
#   sudo bash deploy/books.sh import catalog.txt      # التنزيل والاستيراد
#   sudo bash deploy/books.sh import catalog.txt 10   # تجربة على 10 كتب بس
#
set -euo pipefail

DOMAIN="${DOMAIN:-student-helper.stop4web.online}"
SITE_USER="${SITE_USER:-stop4web-student-helper}"
YEAR="${YEAR:-2026_2027}"

APP_DIR="/home/${SITE_USER}/htdocs/${DOMAIN}"
BACKEND_DIR="${APP_DIR}/backend"
PYTHON="${APP_DIR}/.venv/bin/python"

fail() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

[[ -x "$PYTHON" ]] || fail "البيئة الافتراضية مش موجودة: ${PYTHON}"

command="${1:-}"
[[ -n "$command" ]] || fail "الاستخدام: bash deploy/books.sh {list|plan|import} [ملف] [عدد]"

run() {
  # الملفات لازم تتكتب بملكية مستخدم الموقع مش root
  ( cd "$BACKEND_DIR" && sudo -u "$SITE_USER" "$PYTHON" -m app.tools.import_moe "$@" )
}

case "$command" in
  list)
    run list --prefix "${YEAR}/" --out "${BACKEND_DIR}/catalog.txt"
    ;;
  crawl)
    page="${2:-}"
    if [[ -n "$page" ]]; then
      run crawl --url "$page" --depth "${3:-1}" --out "${BACKEND_DIR}/catalog.txt"
    else
      run crawl --all --depth "${3:-1}" --out "${BACKEND_DIR}/catalog.txt"
    fi
    ;;
  probe)
    run probe --year "$YEAR" ${2:+--grades "$2"} --out "${BACKEND_DIR}/catalog.txt"
    ;;
  plan)
    source_file="${2:-catalog.txt}"
    run plan --from "$source_file" ${3:+--limit "$3"}
    ;;
  import)
    source_file="${2:-catalog.txt}"
    run import --from "$source_file" ${3:+--limit "$3"}
    ;;
  *)
    fail "أمر غير معروف: ${command} (المتاح: crawl / probe / list / plan / import)"
    ;;
esac
