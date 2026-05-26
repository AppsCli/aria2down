#!/usr/bin/env bash
# 把 aria2down 的 .desktop 与自定义 MIME 类型安装到本机 xdg 体系中，
# 让文件管理器双击 .torrent / .metalink、浏览器点击 magnet:、
# 任意应用打开 aria2down:// 都能路由到 aria2down。
#
# 用法：
#   sudo ./scripts/install_linux_associations.sh                   # 系统级（/usr/share）
#        ./scripts/install_linux_associations.sh --user            # 用户级（~/.local/share）
#        ./scripts/install_linux_associations.sh --bin /opt/aria2down/aria2down
#                                                                  # 指定可执行路径，
#                                                                  # 会写入 .desktop 的 Exec=
#        ./scripts/install_linux_associations.sh --set-default    # 同时把 aria2down 设为
#                                                                  # magnet/torrent/metalink/scheme 默认处理器
#
# 环境变量：
#   PREFIX=/usr/local 改写系统级前缀（默认 /usr）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP_SRC="$ROOT/linux/aria2down.desktop"
MIME_SRC="$ROOT/linux/aria2down-mime.xml"
ICON_SRC="$ROOT/linux/icons/256x256/apps/aria2down.png"

if [[ ! -f "$DESKTOP_SRC" ]]; then
  echo "未找到 $DESKTOP_SRC" >&2
  exit 1
fi
if [[ ! -f "$MIME_SRC" ]]; then
  echo "未找到 $MIME_SRC" >&2
  exit 1
fi

SCOPE="system"
BIN_PATH=""
SET_DEFAULT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) SCOPE="user"; shift ;;
    --system) SCOPE="system"; shift ;;
    --bin) BIN_PATH="$2"; shift 2 ;;
    --set-default) SET_DEFAULT=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

if [[ "$SCOPE" == "user" ]]; then
  BASE="${XDG_DATA_HOME:-$HOME/.local/share}"
  APP_DIR="$BASE/applications"
  MIME_DIR="$BASE/mime/packages"
  ICON_DIR="$BASE/icons/hicolor/scalable/apps"
else
  PREFIX="${PREFIX:-/usr}"
  if [[ "$EUID" -ne 0 ]]; then
    echo "系统级安装需要 root（或加 --user 改为用户级）。" >&2
    exit 1
  fi
  APP_DIR="$PREFIX/share/applications"
  MIME_DIR="$PREFIX/share/mime/packages"
  ICON_DIR="$PREFIX/share/icons/hicolor/scalable/apps"
fi

mkdir -p "$APP_DIR" "$MIME_DIR" "$ICON_DIR"

if [[ -f "$ICON_SRC" ]]; then
  hicolor_root="$(dirname "$(dirname "$ICON_DIR")")"
  for size_dir in "$ROOT/linux/icons/"*x*/apps; do
    [[ -d "$size_dir" ]] || continue
    size_name=$(basename "$(dirname "$size_dir")")
    dest_dir="$hicolor_root/$size_name/apps"
    mkdir -p "$dest_dir"
    install -m 0644 "$size_dir/aria2down.png" "$dest_dir/aria2down.png"
  done
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$hicolor_root" 2>/dev/null || true
  fi
fi

DEST_DESKTOP="$APP_DIR/aria2down.desktop"
DEST_MIME="$MIME_DIR/aria2down.xml"

if [[ -n "$BIN_PATH" ]]; then
  sed -E "s|^Exec=.*|Exec=$BIN_PATH %U|; s|^TryExec=.*|TryExec=$BIN_PATH|" \
    "$DESKTOP_SRC" >"$DEST_DESKTOP"
else
  cp -f "$DESKTOP_SRC" "$DEST_DESKTOP"
fi
chmod 0644 "$DEST_DESKTOP"

cp -f "$MIME_SRC" "$DEST_MIME"
chmod 0644 "$DEST_MIME"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APP_DIR" || true
fi
if command -v update-mime-database >/dev/null 2>&1; then
  update-mime-database "$(dirname "$MIME_DIR")" || true
fi

if [[ "$SET_DEFAULT" -eq 1 ]] && command -v xdg-mime >/dev/null 2>&1; then
  for mime in \
    x-scheme-handler/aria2down \
    x-scheme-handler/magnet \
    application/x-bittorrent \
    application/metalink+xml \
    application/metalink4+xml; do
    xdg-mime default aria2down.desktop "$mime" || true
  done
fi

cat <<EOF
已安装：
  $DEST_DESKTOP
  $DEST_MIME

验证：
  xdg-mime query default application/x-bittorrent
  xdg-mime query default x-scheme-handler/magnet
  xdg-open 'aria2down://add?uri=https%3A%2F%2Fexample.com%2Ffile.zip'
EOF
