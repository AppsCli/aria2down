#!/usr/bin/env bash
# 将本机构建好的 aria2c 复制到 Flutter 桌面 release 产物旁，供 BinaryResolver 同目录发现。
#
# 用法：
#   ./scripts/stage_aria2c.sh macos   /path/to/aria2c
#   ./scripts/stage_aria2c.sh linux   /path/to/aria2c
#   ./scripts/stage_aria2c.sh windows /path/to/aria2c.exe
#
# 前提：已对对应平台执行过 flutter build（或与 package_desktop.sh 配合 SKIP_BUILD=1 前已构建）。
# Linux CI：`.github/workflows/flutter.yml` 中 `linux-release-bundle` 使用 apt 的 aria2c 做相同拷贝并上传 artifact。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

target="${1:?用法: $0 macos|linux|windows <aria2c 路径>}"
src="${2:?请传入 aria2c 源文件路径}"

if [[ ! -f "$src" ]]; then
  echo "源文件不存在: $src" >&2
  exit 1
fi

find_macos_app() {
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

case "$target" in
  macos)
    app="$(find_macos_app || true)"
    if [[ -z "$app" ]]; then
      echo "未找到 macOS .app，请先 flutter build macos。" >&2
      exit 1
    fi
    dst="$app/Contents/MacOS/aria2c"
    cp -f "$src" "$dst"
    chmod +x "$dst"
    echo "已安装: $dst"
    ;;
  linux)
    bundle="$(find_linux_bundle || true)"
    if [[ -z "$bundle" ]]; then
      echo "未找到 Linux bundle，请先 flutter build linux。" >&2
      exit 1
    fi
    dst="$bundle/aria2c"
    cp -f "$src" "$dst"
    chmod +x "$dst"
    echo "已安装: $dst"
    ;;
  windows)
    if [[ "$src" != *.exe ]]; then
      echo "提示: Windows 下建议使用 aria2c.exe 作为源路径。" >&2
    fi
    rel="$(find_windows_release || true)"
    if [[ -z "$rel" ]]; then
      echo "未找到 Windows Release 目录，请先 flutter build windows。" >&2
      exit 1
    fi
    dst="$rel/aria2c.exe"
    cp -f "$src" "$dst"
    echo "已安装: $dst"
    ;;
  *)
    echo "未知目标: $target（macos | linux | windows）" >&2
    exit 1
    ;;
esac
