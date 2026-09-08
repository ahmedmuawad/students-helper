#!/usr/bin/env bash
#
# تحديث "مساعد الطالب" لآخر نسخة من GitHub.
#
#   sudo bash update.sh
#
set -euo pipefail

DOMAIN="${DOMAIN:-student-helper.stop4web.online}"
SITE_USER="${SITE_USER:-stop4web-student-helper}"
BRANCH="${BRANCH:-claude/flutter-student-management-app-8bhzc6}"
APP_PORT="${APP_PORT:-8090}"

APP_DIR="/home/${SITE_USER}/htdocs/${DOMAIN}"
BACKEND_DIR="${APP_DIR}/backend"
VENV_DIR="${APP_DIR}/.venv"
SERVICE_NAME="students-helper"

log()  { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m  ✗ %s\033[0m\n' "$*" >&2; exit 1; }

as_site() { sudo -u "$SITE_USER" "$@"; }

[[ $EUID -eq 0 ]] || fail "شغّله بـ sudo"
[[ -d "${APP_DIR}/.git" ]] || fail "المشروع مش متركّب هنا — شغّل install.sh الأول"

BEFORE="$(as_site git -C "$APP_DIR" rev-parse --short HEAD)"

log "سحب آخر نسخة"
as_site git -C "$APP_DIR" fetch --depth 1 origin "$BRANCH"
as_site git -C "$APP_DIR" checkout -f -B "$BRANCH" "origin/${BRANCH}"
AFTER="$(as_site git -C "$APP_DIR" rev-parse --short HEAD)"

if [[ "$BEFORE" == "$AFTER" ]]; then
  ok "مفيش تحديثات جديدة (${AFTER})"
else
  ok "من ${BEFORE} إلى ${AFTER}"
fi

log "تحديث الحزم"
as_site "${VENV_DIR}/bin/pip" install --quiet -r "${BACKEND_DIR}/requirements.txt"
ok "تم"

log "إعادة تشغيل الخدمة"
systemctl restart "$SERVICE_NAME"
sleep 4

if ! systemctl is-active --quiet "$SERVICE_NAME"; then
  journalctl -u "$SERVICE_NAME" -n 40 --no-pager
  fail "الخدمة مش شغالة بعد التحديث — الأخطاء فوق"
fi

for attempt in 1 2 3 4 5; do
  if curl -fsS "http://127.0.0.1:${APP_PORT}/health" >/dev/null 2>&1; then
    ok "التحديث تم والسيرفر شغال"
    exit 0
  fi
  [[ $attempt -eq 5 ]] && fail "السيرفر مش بيرد بعد التحديث"
  sleep 3
done
