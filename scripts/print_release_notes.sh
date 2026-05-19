#!/usr/bin/env bash
# 从 CHANGELOG 打印当前 [Unreleased] 段落，供 GitHub Release 草稿粘贴。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG="$ROOT/CHANGELOG.md"

if [[ ! -f "$CHANGELOG" ]]; then
  echo "缺少 CHANGELOG.md" >&2
  exit 1
fi

awk '
  /^## \[Unreleased\]/ { show=1; next }
  /^## \[/ && show { exit }
  show { print }
' "$CHANGELOG"

echo ""
echo "---"
echo "Tag example: git tag -a v0.1.0 -m \"v0.1.0\" && git push origin v0.1.0"
echo "Then: gh release create v0.1.0 --notes-file -  < <(./scripts/print_release_notes.sh)"
