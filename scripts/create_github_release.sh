#!/usr/bin/env bash
# 辅助创建 GitHub Release（不自动 commit；需已打 tag）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  VER="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
  TAG="v${VER}"
fi

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "标签 $TAG 不存在。请先: git tag -a $TAG -m \"aria2down $TAG\"" >&2
  exit 1
fi

NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
"$ROOT/scripts/print_release_notes.sh" > "$NOTES" || true

if ! command -v gh >/dev/null 2>&1; then
  echo "请安装 GitHub CLI (gh) 或手动在网页创建 Release。" >&2
  echo "Tag: $TAG" >&2
  cat "$NOTES"
  exit 1
fi

gh release create "$TAG" --notes-file "$NOTES" "${@:2}"
echo "Release $TAG 已创建。"
