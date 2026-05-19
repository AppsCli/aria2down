#!/usr/bin/env bash
# 构建 Windows MSIX（需先完成 flutter build windows --release）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

flutter pub get
flutter build windows --release
dart run msix:create

mkdir -p build/dist
find build/windows -name '*.msix' -exec cp -f {} build/dist/ \;
echo "MSIX 已复制到 build/dist/（若存在）"
