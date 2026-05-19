#!/usr/bin/env bash
# 将已编译的 aria2c 拷入 Flutter assets（按 ABI）。
#
# 用法：
#   ./scripts/stage_android_aria2.sh <abi> <path-to-aria2c>
#
# 示例：
#   ./scripts/stage_android_aria2.sh arm64-v8a build/android-arm64/aria2c
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ABI="${1:?用法: $0 <abi> <aria2c-path>}"
SRC="${2:?}"

if [[ ! -f "$SRC" ]]; then
  echo "找不到二进制: $SRC" >&2
  exit 1
fi

DEST_DIR="$ROOT/assets/android/$ABI"
mkdir -p "$DEST_DIR"
cp -f "$SRC" "$DEST_DIR/aria2c"
chmod +x "$DEST_DIR/aria2c"
echo "已写入: $DEST_DIR/aria2c"
