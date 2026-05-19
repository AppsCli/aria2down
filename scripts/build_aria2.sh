#!/usr/bin/env bash
# 在本机构建 third_party/aria2 的 aria2c（macOS / Linux）。
#
# 用法：
#   ./scripts/build_aria2.sh              # 动态链接
#   ./scripts/build_aria2.sh --static   # ARIA2_STATIC=yes
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARIA2="$ROOT/third_party/aria2"
STATIC=0
if [[ "${1:-}" == "--static" ]]; then
  STATIC=1
fi

if [[ ! -d "$ARIA2" ]]; then
  echo "缺少子模块 third_party/aria2，请执行: git submodule update --init" >&2
  exit 1
fi

cd "$ARIA2"
if [[ ! -f configure ]]; then
  autoreconf -i
fi

if [[ "$STATIC" -eq 1 ]]; then
  ./configure ARIA2_STATIC=yes
else
  ./configure
fi

CORES=4
if [[ "$(uname -s)" == Darwin ]]; then
  CORES="$(sysctl -n hw.ncpu)"
else
  CORES="$(nproc)"
fi
make -j"$CORES"

echo ""
echo "构建完成: $ARIA2/src/aria2c"
echo "桌面内嵌: ./scripts/stage_aria2c.sh <platform> $ARIA2/src/aria2c"
