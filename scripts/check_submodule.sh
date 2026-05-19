#!/usr/bin/env bash
# 检查 aria2 子模块是否已初始化。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f third_party/aria2/configure.ac ]] && [[ ! -f third_party/aria2/configure ]]; then
  echo "aria2 submodule missing. Run:" >&2
  echo "  git submodule update --init --recursive" >&2
  exit 1
fi

echo "aria2 submodule: OK"
