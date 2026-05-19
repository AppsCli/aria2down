#!/usr/bin/env bash
# 发布前本地校验：分析、格式、测试、关键文件存在。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

./scripts/check_submodule.sh
flutter pub get
flutter analyze
dart format --set-exit-if-changed lib test bin
flutter test

for f in PLAN.md CHANGELOG.md pubspec.yaml \
         packages/aria2_native/pubspec.yaml \
         packages/aria2_native/src/aria2_ffi.h \
         packages/aria2_native/src/aria2_ffi.cc; do
  test -f "$f" || {
    echo "missing $f" >&2
    exit 1
  }
done

echo "validate_release: OK"
