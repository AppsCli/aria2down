#!/usr/bin/env bash
# P4-01：在 Docker 中交叉编译 aria2 for Android（需本机 Docker）。
#
# 用法：
#   ./scripts/build_android_aria2_docker.sh arm64-v8a
#   ./scripts/build_android_aria2_docker.sh armeabi-v7a
#   ./scripts/build_android_aria2_docker.sh x86_64
#
# 成功后执行：
#   ./scripts/stage_android_aria2.sh <abi> /path/to/out/aria2c
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ABI="${1:?用法: $0 armeabi-v7a|arm64-v8a|x86_64}"

ARIA2_DIR="$ROOT/third_party/aria2"
if [[ ! -d "$ARIA2_DIR" ]]; then
  echo "缺少 third_party/aria2，请: git submodule update --init" >&2
  exit 1
fi

DOCKERFILE="$ARIA2_DIR/Dockerfile.android"
if [[ ! -f "$DOCKERFILE" ]]; then
  echo "未找到 $DOCKERFILE，请参考 docs/ANDROID.md 手动 NDK 构建。" >&2
  exit 1
fi

echo "== 使用 upstream Dockerfile.android 构建 ABI=$ABI =="
echo "提示：首次构建较慢；产物路径因镜像而异，请查阅 aria2 文档后 stage_android_aria2.sh"

docker build -f "$DOCKERFILE" \
  --build-arg TARGET_ABI="$ABI" \
  -t "aria2down-aria2-android:$ABI" \
  "$ARIA2_DIR"

echo "镜像 aria2down-aria2-android:$ABI 已构建。"
echo "请从容器内拷贝 aria2c 到主机后运行 stage_android_aria2.sh。"
