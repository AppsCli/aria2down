#!/usr/bin/env bash
# Build libaria2 (静态库) for Linux。
#
# 输出：packages/aria2_native/prebuilt/linux/<arch>/{libaria2.a, include/aria2/aria2.h, deps/*.a}
# 默认架构由当前主机决定（x86_64 / arm64）；交叉编译请覆盖 ARCH 与 HOST_TRIPLET。
#
# 依赖（Debian/Ubuntu 示例）：
#   sudo apt install build-essential autoconf automake libtool pkg-config \
#       libssl-dev libc-ares-dev libsqlite3-dev zlib1g-dev libssh2-1-dev
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARIA2="$ROOT/third_party/aria2"

ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in
  x86_64|amd64) ARCH_DIR=x86_64 ;;
  aarch64|arm64) ARCH_DIR=arm64 ;;
  *) ARCH_DIR="$ARCH" ;;
esac
TARGET="$ROOT/packages/aria2_native/prebuilt/linux/$ARCH_DIR"

if [[ ! -d "$ARIA2" ]]; then
  echo "缺少子模块 third_party/aria2" >&2; exit 1
fi

# 应用 aria2down 本地补丁——详见 build_libaria2_macos.sh 同名段落。在 Linux
# 上 OpenSSL DRBG 补丁的 `#ifdef __ANDROID__` 守护让它对本平台编译没有副作用，
# `aria2-public-api-extensions.patch` 则是必须的（FFI shim 用于探测能力宏）。
ARIA2_PATCHED_FILES=(
  src/LibsslTLSContext.cc
  src/Platform.cc
  src/SimpleRandomizer.cc
  src/aria2api.cc
  src/includes/aria2/aria2.h
)
revert_aria2_patches() {
  (cd "$ARIA2" && git checkout -- "${ARIA2_PATCHED_FILES[@]}" 2>/dev/null) || true
}
trap revert_aria2_patches EXIT
revert_aria2_patches  # 见 build_libaria2_macos.sh 同名段落：始终从干净源 patch
for p in \
  "$ROOT/patches/third_party-aria2/android-openssl-drbg-and-ssl-guards.patch" \
  "$ROOT/patches/third_party-aria2/aria2-public-api-extensions.patch"; do
  if [[ -f "$p" ]]; then
    (cd "$ARIA2" && patch -p1 --no-backup-if-mismatch <"$p") || {
      echo "应用补丁失败：$p" >&2; exit 1
    }
  fi
done

cd "$ARIA2"
[[ -f configure ]] || autoreconf -i

BUILD_DIR="$ROOT/build/libaria2/linux-$ARCH_DIR"
INSTALL_DIR="$ROOT/build/libaria2/linux-$ARCH_DIR-install"
rm -rf "$BUILD_DIR" "$INSTALL_DIR"
mkdir -p "$BUILD_DIR"

(cd "$BUILD_DIR" && \
  CFLAGS="${CFLAGS:--O2 -fPIC}" \
  CXXFLAGS="${CXXFLAGS:--O2 -fPIC}" \
  LDFLAGS="${LDFLAGS:--static-libstdc++ -static-libgcc}" \
  "$ARIA2/configure" \
    ${HOST_TRIPLET:+--host="$HOST_TRIPLET"} \
    --prefix="$INSTALL_DIR" \
    --enable-libaria2 \
    --enable-static \
    --disable-shared \
    --without-libxml2 \
    --without-libgmp \
    --without-libgcrypt \
    --without-libnettle \
    --without-gnutls \
    --with-openssl \
    --with-libssh2=no \
    --without-libuv \
    ARIA2_STATIC=yes)
make -C "$BUILD_DIR" -j"$(nproc)"
make -C "$BUILD_DIR" install

mkdir -p "$TARGET/include/aria2" "$TARGET/deps"
cp "$INSTALL_DIR/lib/libaria2.a" "$TARGET/libaria2.a"
cp "$INSTALL_DIR/include/aria2/aria2.h" "$TARGET/include/aria2/aria2.h"

# 系统依赖 .a 路径在各发行版上略有不同；CI 中通常使用静态分发包。
for dep in libssl libcrypto libcares libsqlite3; do
  hit="$(find /usr/lib* /usr/local/lib* -maxdepth 3 -name "${dep}.a" 2>/dev/null | head -n1 || true)"
  if [[ -n "$hit" ]]; then
    cp "$hit" "$TARGET/deps/${dep}.a"
  else
    echo "[warn] 缺少 ${dep}.a — 将由系统动态库兜底"
  fi
done

echo "Linux libaria2 已就绪：$TARGET"
