#!/usr/bin/env bash
# 桌面端分发包：先执行 analyze + test + flutter build，再在 build/dist/ 产出归档。
#
# 用法：
#   ./scripts/package_desktop.sh           # 按当前 OS 推断目标（同 build_desktop.sh）
#   ./scripts/package_desktop.sh macos
#   ./scripts/package_desktop.sh linux
#   ./scripts/package_desktop.sh windows
#
# 环境变量：
#   SKIP_BUILD=1    跳过构建（假定 build/ 下已有对应 release 产物）
#   VERSION_SUFFIX  追加到文件名（默认取 pubspec.yaml 的 version 主段，如 1.0.0）
#
# 产物：
#   macOS   — build/dist/aria2down-macos-<ver>.dmg（需本机 hdiutil）
#   Linux   — build/dist/aria2down-linux-<ver>.tar.gz（bundle 目录整包）
#             若安装 appimagetool：额外 build/dist/aria2down-linux-<ver>.AppImage
#   Windows — build/dist/aria2down-windows-<ver>.zip（Release 目录整包，bsdtar/GNU tar -a）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

read_app_version() {
  grep '^version:' pubspec.yaml | head -1 | awk '{print $2}' | cut -d+ -f1
}

VER="${VERSION_SUFFIX:-$(read_app_version)}"
SKIP_BUILD="${SKIP_BUILD:-0}"

raw_target="${1:-}"
if [[ -z "$raw_target" ]]; then
  case "$(uname -s)" in
    Darwin) target="macos" ;;
    Linux) target="linux" ;;
    MINGW*|MSYS*|CYGWIN*) target="windows" ;;
    *)
      echo "无法从 uname 推断目标，请显式传入: macos | linux | windows" >&2
      exit 1
      ;;
  esac
else
  target="$raw_target"
fi

if [[ "$SKIP_BUILD" != "1" ]]; then
  "$ROOT/scripts/build_desktop.sh" "$target"
fi

mkdir -p build/dist

find_macos_app() {
  # Flutter 常见路径：build/macos/Build/Products/Release/*.app
  find build/macos -type d -name "*.app" 2>/dev/null | grep -E '/[Rr]elease(/|$)' | head -n 1
}

find_linux_bundle() {
  find build/linux -path "*/release/bundle" -type d 2>/dev/null | head -n 1
}

find_windows_release() {
  local p
  p="build/windows/x64/runner/Release"
  if [[ -d "$p" ]]; then echo "$p"; return 0; fi
  p="build/windows/runner/Release"
  if [[ -d "$p" ]]; then echo "$p"; return 0; fi
  find build/windows -path "*/runner/Release" -type d 2>/dev/null | head -n 1
}

package_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "错误: 创建 .dmg 需要 macOS（hdiutil）。" >&2
    exit 1
  fi
  local app vol dmg
  app="$(find_macos_app || true)"
  if [[ -z "$app" || ! -d "$app" ]]; then
    echo "未找到 Release .app（请先 flutter build macos 或勿设 SKIP_BUILD=1）。" >&2
    exit 1
  fi
  vol="aria2down"
  dmg="build/dist/aria2down-macos-${VER}.dmg"
  rm -f "$dmg"
  hdiutil create -volname "$vol" -srcfolder "$app" -ov -format UDZO "$dmg"
  echo "已生成: $dmg"
}

package_linux_appimage() {
  local bundle appdir out desktop_src mime_src icon_src
  bundle="$1"
  if ! command -v appimagetool >/dev/null 2>&1; then
    echo "跳过 AppImage：未找到 appimagetool（可选）。" >&2
    return 0
  fi
  appdir="build/dist/aria2down.AppDir"
  out="build/dist/aria2down-linux-${VER}.AppImage"
  desktop_src="$ROOT/linux/aria2down.desktop"
  mime_src="$ROOT/linux/aria2down-mime.xml"

  rm -rf "$appdir" "$out"
  mkdir -p \
    "$appdir/usr/bin" \
    "$appdir/usr/share/applications" \
    "$appdir/usr/share/mime/packages" \
    "$appdir/usr/share/icons/hicolor/256x256/apps"
  cp -a "$bundle"/. "$appdir/usr/bin/"

  cat >"$appdir/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/bin/lib:${LD_LIBRARY_PATH-}"
exec "$HERE/usr/bin/aria2down" "$@"
EOF
  chmod +x "$appdir/AppRun"

  # 复用仓库内完整 .desktop（含 MimeType=），同时放到 AppDir 根（appimagetool 要求）
  # 与 usr/share/applications/（让 AppImageLauncher / 部分集成把 MIME 注册到系统）。
  cp -f "$desktop_src" "$appdir/aria2down.desktop"
  cp -f "$desktop_src" "$appdir/usr/share/applications/aria2down.desktop"
  if [[ -f "$mime_src" ]]; then
    cp -f "$mime_src" "$appdir/usr/share/mime/packages/aria2down.xml"
  fi

  # 图标：appimagetool 需要 .DirIcon 与同名 png/svg。若仓库内无 256x256 PNG，
  # 退化使用 assets/tray/tray.png（小图也能用，但只用于 AppImage 缺省图标）。
  icon_src="$ROOT/linux/icons/256x256/aria2down.png"
  if [[ ! -f "$icon_src" ]]; then
    icon_src="$ROOT/assets/tray/tray.png"
  fi
  if [[ -f "$icon_src" ]]; then
    cp -f "$icon_src" "$appdir/aria2down.png"
    cp -f "$icon_src" "$appdir/usr/share/icons/hicolor/256x256/apps/aria2down.png"
    cp -f "$icon_src" "$appdir/.DirIcon"
  fi

  appimagetool "$appdir" "$out"
  echo "已生成: $out"
}

package_linux() {
  local bundle out
  bundle="$(find_linux_bundle || true)"
  if [[ -z "$bundle" || ! -d "$bundle" ]]; then
    echo "未找到 Linux bundle 目录（build/linux/.../release/bundle）。" >&2
    exit 1
  fi
  out="build/dist/aria2down-linux-${VER}.tar.gz"
  rm -f "$out"
  tar -czf "$out" -C "$bundle" .
  echo "已生成: $out"
  package_linux_appimage "$bundle"
}

package_windows() {
  local rel out
  rel="$(find_windows_release || true)"
  if [[ -z "$rel" || ! -d "$rel" ]]; then
    echo "未找到 Windows Release 目录（runner/Release）。" >&2
    exit 1
  fi
  out="build/dist/aria2down-windows-${VER}.zip"
  rm -f "$out"
  # libarchive / GNU tar：按扩展名推断 zip
  (cd "$rel" && tar -a -c -f "$ROOT/$out" .)
  echo "已生成: $out"

  if command -v flutter >/dev/null 2>&1; then
    if flutter build windows --help 2>/dev/null | grep -q msix; then
      echo "尝试构建 MSIX…"
      if flutter build windows --release --msix 2>/dev/null; then
        find build/windows -name '*.msix' -exec cp -f {} build/dist/ \; 2>/dev/null || true
        echo "MSIX 已复制到 build/dist/（若存在）"
      else
        echo "跳过 MSIX：当前 Flutter 通道未启用 msix 或构建失败。"
      fi
    fi
  fi
}

case "$target" in
  macos) package_macos ;;
  linux) package_linux ;;
  windows) package_windows ;;
  *)
    echo "未知目标: $target（支持 macos / linux / windows）" >&2
    exit 1
    ;;
esac
