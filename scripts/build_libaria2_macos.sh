#!/usr/bin/env bash
# Build libaria2 (静态库) for macOS — arm64 + x86_64 → lipo universal。
#
# 输出落到 packages/aria2_native/prebuilt/macos/universal/，包含：
#   include/aria2/aria2.h
#   libaria2.a            (lipo merged)
#   deps/*.a              (openssl 等静态依赖)
#
# 依赖：autoconf、automake、libtool、pkg-config、Homebrew 的 openssl/c-ares/sqlite3
#   $ brew install autoconf automake libtool pkg-config openssl@3 c-ares sqlite3 zlib
#
# 用法：
#   ./scripts/build_libaria2_macos.sh          # 双架构 + lipo
#   ./scripts/build_libaria2_macos.sh arm64    # 仅 arm64
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARIA2="$ROOT/third_party/aria2"
TARGET_ROOT="$ROOT/packages/aria2_native/prebuilt/macos"
TARGETS=("${@:-arm64 x86_64}")
TARGETS=(${TARGETS[@]:-arm64 x86_64})

if [[ ! -d "$ARIA2" ]]; then
  echo "缺少子模块 third_party/aria2，请执行: git submodule update --init" >&2
  exit 1
fi

command -v autoreconf >/dev/null || { echo "需要 autoconf/automake/libtool" >&2; exit 1; }

cd "$ARIA2"
if [[ ! -f configure ]]; then
  autoreconf -i
fi

BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
OPENSSL_PREFIX="$(brew --prefix openssl@3 2>/dev/null || echo $BREW_PREFIX/opt/openssl@3)"
CARES_PREFIX="$(brew --prefix c-ares 2>/dev/null || echo $BREW_PREFIX/opt/c-ares)"
SQLITE_PREFIX="$(brew --prefix sqlite3 2>/dev/null || echo $BREW_PREFIX/opt/sqlite)"

for prefix in "$OPENSSL_PREFIX" "$CARES_PREFIX" "$SQLITE_PREFIX"; do
  if [[ ! -d "$prefix" ]]; then
    echo "未找到依赖前缀：$prefix（请 brew install）" >&2
    exit 1
  fi
done

build_for_arch() {
  local ARCH="$1"
  local BUILD_DIR="$ROOT/build/libaria2/macos-$ARCH"
  local INSTALL_DIR="$ROOT/build/libaria2/macos-$ARCH-install"
  rm -rf "$BUILD_DIR" "$INSTALL_DIR"
  mkdir -p "$BUILD_DIR"

  local DEPLOY=11.0
  local FLAGS="-arch $ARCH -mmacosx-version-min=$DEPLOY"

  (cd "$BUILD_DIR" && \
    PKG_CONFIG_PATH="$OPENSSL_PREFIX/lib/pkgconfig:$CARES_PREFIX/lib/pkgconfig:$SQLITE_PREFIX/lib/pkgconfig" \
    CFLAGS="$FLAGS -O2" \
    CXXFLAGS="$FLAGS -O2" \
    LDFLAGS="$FLAGS" \
    "$ARIA2/configure" \
      --host="$ARCH-apple-darwin" \
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
      --without-appletls \
      --with-libssh2=no \
      --without-libuv \
      ARIA2_STATIC=yes)
  make -C "$BUILD_DIR" -j"$(sysctl -n hw.ncpu)"
  make -C "$BUILD_DIR" install
  echo "$INSTALL_DIR"
}

INSTALL_DIRS=()
for ARCH in "${TARGETS[@]}"; do
  INSTALL_DIR=$(build_for_arch "$ARCH")
  INSTALL_DIRS+=("$INSTALL_DIR")
done

OUT="$TARGET_ROOT/universal"
mkdir -p "$OUT/include/aria2" "$OUT/deps"

if [[ ${#INSTALL_DIRS[@]} -gt 1 ]]; then
  LIBS=()
  for d in "${INSTALL_DIRS[@]}"; do LIBS+=("$d/lib/libaria2.a"); done
  lipo -create -output "$OUT/libaria2.a" "${LIBS[@]}"
else
  cp "${INSTALL_DIRS[0]}/lib/libaria2.a" "$OUT/libaria2.a"
fi
cp "${INSTALL_DIRS[0]}/include/aria2/aria2.h" "$OUT/include/aria2/aria2.h"

# 依赖静态库（Homebrew 提供的 .a；只取 universal 或当前架构可用的）。
for src in \
  "$OPENSSL_PREFIX/lib/libssl.a" \
  "$OPENSSL_PREFIX/lib/libcrypto.a" \
  "$CARES_PREFIX/lib/libcares.a" \
  "$SQLITE_PREFIX/lib/libsqlite3.a"; do
  [[ -f "$src" ]] && cp "$src" "$OUT/deps/" || echo "[warn] 缺少 $src，运行时由系统库兜底"
done

echo ""
echo "macOS libaria2 已就绪：$OUT"
echo "目录内容："
find "$OUT" -maxdepth 3 -print
