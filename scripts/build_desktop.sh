#!/usr/bin/env bash
# 桌面端发布构建：分析、单测、再按平台执行 flutter build。
# 用法：
#   ./scripts/build_desktop.sh           # 根据当前 OS 选择目标（Darwin→macOS，Linux→linux，Windows→windows）
#   ./scripts/build_desktop.sh macos
#   ./scripts/build_desktop.sh linux
#   ./scripts/build_desktop.sh windows
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

flutter pub get
flutter analyze
flutter test

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

case "$target" in
  macos) flutter build macos --release ;;
  linux) flutter build linux --release ;;
  windows) flutter build windows --release ;;
  *)
    echo "未知目标: $target（支持 macos / linux / windows）" >&2
    exit 1
    ;;
esac

echo "构建完成: build/${target}/..."
