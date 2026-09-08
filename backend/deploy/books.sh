#!/usr/bin/env bash
#
# اختصار لأوامر استيراد كتب الوزارة.
#
#   sudo bash deploy/books.sh migrate                 # تظبيط الجداول القديمة
#   sudo bash deploy/books.sh structure               # المناهج والصفوف والمواد
#   sudo bash deploy/books.sh status                  # عرض اللي في قاعدة البيانات
#   sudo bash deploy/books.sh html صفحة.html          # من صفحة محفوظة من المتصفح
#   sudo bash deploy/books.sh html /root/pages/       # أو مجلد فيه الصفحات
#   sudo bash deploy/books.sh crawl                   # كل المراحل من مكتبة الوزارة
#   sudo bash deploy/books.sh crawl <رابط صفحة>       # صفحة واحدة
#   sudo bash deploy/books.sh probe [الصفوف]          # تخمين الروابط
#   sudo bash deploy/books.sh list                    # فهرس المكتبة (لو مسموح)
#   sudo bash deploy/books.sh all                     # ← كل حاجة مرة واحدة
#   sudo bash deploy/books.sh plan                    # معاينة من غير تنزيل
#   sudo bash deploy/books.sh import                  # التنزيل والاستيراد
#   sudo bash deploy/books.sh import '' 10            # تجربة على 10 كتب بس
#
# من غير ما تدّي ملف، بيستخدم الكتالوج الجاهز اللي جاي مع الكود:
#   backend/catalogs/moe-2026-2027-term1.txt
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

STAGE_DIR="${BACKEND_DIR}/.incoming"

run() {
  # الملفات لازم تتكتب بملكية مستخدم الموقع مش root
  ( cd "$BACKEND_DIR" && sudo -u "$SITE_USER" "$PYTHON" -m app.tools.import_moe "$@" )
}

site_can_read() { sudo -u "$SITE_USER" test -r "$1" 2>/dev/null; }

# بيرجّع مسار الملف بشكل يقدر مستخدم الموقع يقراه — بينسخه لو محتاج.
# (الملفات اللي في /root مثلاً مقفولة عليه تمامًا)
stage_file() {
  local src="$1"
  [[ -e "$src" ]] || { printf '\033[1;31m✗ الملف مش موجود: %s\033[0m\n' "$src" >&2; return 1; }
  if site_can_read "$src"; then
    printf '%s' "$src"
    return 0
  fi
  if [[ $EUID -ne 0 ]]; then
    printf '\033[1;31m✗ مستخدم الموقع مش قادر يقرا %s — شغّل الأمر بـ sudo\033[0m\n' "$src" >&2
    return 1
  fi
  mkdir -p "$STAGE_DIR" || return 1
  chown "$SITE_USER":"$SITE_USER" "$STAGE_DIR" || return 1
  local dest="${STAGE_DIR}/$(basename "$src")"
  cp -f "$src" "$dest" || return 1
  chown "$SITE_USER":"$SITE_USER" "$dest" || return 1
  chmod 640 "$dest" || return 1
  printf '%s' "$dest"
}

# الكتالوج الجاهز اللي بيتشحن مع الكود — فيه كل كتب الترم الأول
SHIPPED_CATALOG="${BACKEND_DIR}/catalogs/moe-2026-2027-term1.txt"

# ملف الروابط: من غير وسيط بنستخدم catalog.txt لو اتعمل، وإلا الكتالوج الجاهز.
# والمسار النسبي بيتحسب من مجلد backend.
catalog_path() {
  local file="${1:-}"
  if [[ -z "$file" ]]; then
    if [[ -f "${BACKEND_DIR}/catalog.txt" ]]; then
      file="${BACKEND_DIR}/catalog.txt"
    else
      file="$SHIPPED_CATALOG"
    fi
  elif [[ "$file" != /* && ! -f "$file" && -f "${BACKEND_DIR}/${file}" ]]; then
    file="${BACKEND_DIR}/${file}"
  fi
  if [[ ! -f "$file" ]]; then
    local shown="$file"
    [[ "$shown" == /* ]] || shown="${BACKEND_DIR}/${shown}"
    printf '\033[1;31m✗ ملف الروابط مش موجود: %s\033[0m\n' "$shown" >&2
    printf '  حضّره الأول: bash deploy/books.sh crawl   أو   bash deploy/books.sh html <صفحاتك>\n' >&2
    return 1
  fi
  stage_file "$file"
}

case "$command" in
  list)
    run list --prefix "${YEAR}/" --out "${BACKEND_DIR}/catalog.txt"
    ;;
  migrate)
    run migrate
    ;;
  structure)
    run structure ${2:+--year "$2"}
    ;;
  status)
    run status
    ;;
  html)
    shift
    [[ $# -gt 0 ]] || fail "محتاج ملف أو مجلد: bash deploy/books.sh html صفحة.html"
    staged=()
    for page in "$@"; do
      if [[ -d "$page" ]]; then
        found=("$page"/*.html "$page"/*.htm)
        for item in "${found[@]}"; do
          [[ -f "$item" ]] || continue
          staged+=( "$(stage_file "$item")" ) || exit 1
        done
      else
        staged+=( "$(stage_file "$page")" ) || exit 1
      fi
    done
    [[ ${#staged[@]} -gt 0 ]] || fail "مفيش ملفات HTML في اللي اديتهولي"
    run html "${staged[@]}" --out "${BACKEND_DIR}/catalog.txt"
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
    source_file="$(catalog_path "${2:-}")" || exit 1
    printf '\033[1;36m▶ الكتالوج: %s\033[0m\n' "$source_file"
    run plan --from "$source_file" ${3:+--limit "$3"}
    ;;
  import)
    source_file="$(catalog_path "${2:-}")" || exit 1
    printf '\033[1;36m▶ الكتالوج: %s\033[0m\n' "$source_file"
    run import --from "$source_file" ${3:+--limit "$3"}
    ;;
  all)
    # التركيبة الكاملة: تظبيط الجداول ← المناهج والصفوف ← الكتب
    run migrate
    run structure
    source_file="$(catalog_path "${2:-}")" || exit 1
    printf '\033[1;36m▶ الكتالوج: %s\033[0m\n' "$source_file"
    run import --from "$source_file" ${3:+--limit "$3"}
    run status
    ;;
  *)
    fail "أمر غير معروف: ${command}
  المتاح: all / migrate / structure / status / html / crawl / probe / list / plan / import"
    ;;
esac
