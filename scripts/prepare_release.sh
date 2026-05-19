#!/usr/bin/env bash
# 发版前检查（不自动打 tag / 不 push）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VER="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
echo "== aria2down release prep (pubspec: $VER) =="

./scripts/validate_release.sh

echo ""
echo "通过静态检查与测试。请手动："
echo "  1. 更新 CHANGELOG.md 中 [Unreleased] → [$VER]"
echo "  2. ./scripts/package_desktop.sh <platform>  # 或含自编译 aria2: ./scripts/build_bundle_with_aria2.sh <platform>"
echo "     Windows MSIX: ./scripts/package_msix.sh"
echo "  3. git tag v${VER%%+*}"
echo "  4. gh release create v${VER%%+*} --notes-file CHANGELOG.md"
echo ""
echo "详见 docs/RELEASE.md"
