#!/usr/bin/env bash
# 反向操作 install_linux_associations.sh：移除 .desktop / MIME 注册。
#
# 用法：
#   sudo ./scripts/uninstall_linux_associations.sh           # 系统级
#        ./scripts/uninstall_linux_associations.sh --user    # 用户级
set -euo pipefail

SCOPE="system"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) SCOPE="user"; shift ;;
    --system) SCOPE="system"; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

if [[ "$SCOPE" == "user" ]]; then
  BASE="${XDG_DATA_HOME:-$HOME/.local/share}"
  APP_DIR="$BASE/applications"
  MIME_DIR="$BASE/mime/packages"
else
  PREFIX="${PREFIX:-/usr}"
  if [[ "$EUID" -ne 0 ]]; then
    echo "系统级卸载需要 root（或加 --user）。" >&2
    exit 1
  fi
  APP_DIR="$PREFIX/share/applications"
  MIME_DIR="$PREFIX/share/mime/packages"
fi

rm -f "$APP_DIR/aria2down.desktop" "$MIME_DIR/aria2down.xml"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APP_DIR" || true
fi
if command -v update-mime-database >/dev/null 2>&1; then
  update-mime-database "$(dirname "$MIME_DIR")" || true
fi

echo "已移除 aria2down 的 desktop / MIME 注册。"
