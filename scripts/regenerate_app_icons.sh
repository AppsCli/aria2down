#!/usr/bin/env bash
# 从 assets/icon/app_icon.png（1024×1024 正方形）再生各平台启动图标。
# 依赖: flutter pub get、dart run flutter_launcher_icons、sips（macOS）或 ImageMagick convert。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/assets/icon/app_icon.png"

if [[ ! -f "$SRC" ]]; then
  echo "缺少主图标: $SRC" >&2
  exit 1
fi

w=$(sips -g pixelWidth "$SRC" 2>/dev/null | awk '/pixelWidth/{print $2}')
h=$(sips -g pixelHeight "$SRC" 2>/dev/null | awk '/pixelHeight/{print $2}')
if [[ "$w" != "$h" ]] || [[ "$w" -lt 1024 ]]; then
  echo "app_icon.png 须为 ≥1024 的正方形，当前 ${w:-?}×${h:-?}" >&2
  exit 1
fi

cd "$ROOT"
dart run flutter_launcher_icons

resize() {
  local size=$1 out=$2
  if command -v sips >/dev/null 2>&1; then
    sips -z "$size" "$size" "$SRC" --out "$out" >/dev/null
  elif command -v convert >/dev/null 2>&1; then
    convert "$SRC" -resize "${size}x${size}" "$out"
  else
    echo "需要 sips（macOS）或 ImageMagick convert 以生成 Linux / 托盘图标" >&2
    exit 1
  fi
}

for size in 16 32 48 64 128 256; do
  dir="$ROOT/linux/icons/${size}x${size}/apps"
  mkdir -p "$dir"
  resize "$size" "$dir/aria2down.png"
done

resize 32 "$ROOT/assets/tray/tray.png"

echo "完成: flutter_launcher_icons + linux/icons/* + assets/tray/tray.png"
