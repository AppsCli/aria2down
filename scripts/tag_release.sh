#!/usr/bin/env bash
# 发版辅助：校验通过后打印打 tag / gh release 命令（不自动执行 git tag）。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VER="$(grep '^version:' pubspec.yaml | head -1 | awk '{print $2}' | cut -d+ -f1)"
TAG="v${VER}"

echo "== aria2down tag helper (version ${VER}) =="
./scripts/validate_release.sh

echo ""
echo "校验通过。若 CHANGELOG 已整理，可执行："
echo "  git tag -a ${TAG} -m \"aria2down ${TAG}\""
echo "  git push origin ${TAG}"
echo "  ./scripts/create_github_release.sh ${TAG}"
echo ""
echo "详见 docs/RELEASE.md"
