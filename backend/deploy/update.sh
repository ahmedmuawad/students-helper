#!/usr/bin/env bash
#
# تحديث التطبيق بعد سحب نسخة جديدة من الكود:
#   sudo bash deploy/update.sh
#
set -euo pipefail

DOMAIN="${DOMAIN:-student-helper.stop4web.online}"
SITE_USER="${SITE_USER:-stop4web-student-helper}"
APP_DIR="/home/${SITE_USER}/htdocs/${DOMAIN}"
SERVICE_NAME="students-helper"

[[ $EUID -eq 0 ]] || { echo "شغّله بـ sudo"; exit 1; }

echo "▶ تحديث الحزم"
sudo -u "$SITE_USER" "${APP_DIR}/.venv/bin/pip" install --quiet -r "${APP_DIR}/requirements.txt"

echo "▶ إعادة تشغيل الخدمة"
systemctl restart "$SERVICE_NAME"
sleep 4

if systemctl is-active --quiet "$SERVICE_NAME"; then
  echo "✓ التحديث تم والخدمة شغالة"
else
  journalctl -u "$SERVICE_NAME" -n 30 --no-pager
  exit 1
fi
