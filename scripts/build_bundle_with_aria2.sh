#!/usr/bin/env bash
# 从 third_party/aria2 编译 aria2c，打入桌面 bundle，并生成分发包。
#
# 用法：
#   ./scripts/build_bundle_with_aria2.sh linux
#   ./scripts/build_bundle_with_aria2.sh macos
#   ./scripts/build_bundle_with_aria2.sh windows
#
# 环境变量：
#   SKIP_ARIA2_BUILD=1  跳过编译，仅 stage 已有路径（需 ARIA2C_SRC）
#   ARIA2C_SRC=/path/to/aria2c  指定已编译二进制
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

target="${1:?用法: $0 macos|linux|windows}"
SKIP_ARIA2_BUILD="${SKIP_ARIA2_BUILD:-0}"

aria2_src=""

if [[ "$SKIP_ARIA2_BUILD" == "1" ]]; then
  aria2_src="${ARIA2C_SRC:?请设置 ARIA2C_SRC}"
else
  "$ROOT/scripts/build_aria2.sh"
  aria2_src="$ROOT/third_party/aria2/src/aria2c"
  if [[ "$target" == "windows" ]]; then
    aria2_src="$ROOT/third_party/aria2/src/aria2c.exe"
    if [[ ! -f "$aria2_src" ]]; then
      aria2_src="$ROOT/third_party/aria2/src/aria2c"
    fi
  fi
fi

if [[ ! -f "$aria2_src" ]]; then
  echo "未找到 aria2c: $aria2_src" >&2
  exit 1
fi

"$ROOT/scripts/build_desktop.sh" "$target"
"$ROOT/scripts/stage_aria2c.sh" "$target" "$aria2_src"
SKIP_BUILD=1 "$ROOT/scripts/package_desktop.sh" "$target"

echo "完成：build/dist/ 下应有对应平台分发包（含内嵌 aria2c）。"
