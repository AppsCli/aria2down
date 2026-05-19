#!/usr/bin/env bash
# Build libaria2 (静态库) for macOS — arm64 + x86_64 → lipo universal。
#
# 输出落到 packages/aria2_native/prebuilt/macos/universal/，包含：
#   include/aria2/aria2.h
#   libaria2.a            (lipo merged)
#   deps/*.a              (openssl 等静态依赖)
#
# 依赖：autoconf、automake、libtool、pkg-config、Homebrew 的 c-ares/sqlite3
#   $ brew install autoconf automake libtool pkg-config c-ares sqlite3 zlib
#
# 注意：macOS 上使用 AppleTLS (SecureTransport) 作为 TLS 后端，
# 不再依赖 OpenSSL，可避免静态 OpenSSL 3 在 provider 加载上的种种陷阱。
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
CARES_PREFIX="$(brew --prefix c-ares 2>/dev/null || echo $BREW_PREFIX/opt/c-ares)"
SQLITE_PREFIX="$(brew --prefix sqlite3 2>/dev/null || echo $BREW_PREFIX/opt/sqlite)"

for prefix in "$CARES_PREFIX" "$SQLITE_PREFIX"; do
  if [[ ! -d "$prefix" ]]; then
    echo "未找到依赖前缀：$prefix（请 brew install）" >&2
    exit 1
  fi
done

build_for_arch() {
  local ARCH="$1"
  local BUILD_DIR="$ROOT/build/libaria2/macos-$ARCH"
  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"

  local DEPLOY=11.0
  local FLAGS="-arch $ARCH -mmacosx-version-min=$DEPLOY"

  # 注意：函数 stdout 仅用于返回 BUILD_DIR；configure / make 全部重定向到
  # stderr (>&2)，否则会污染 $(build_for_arch) 的捕获结果。
  (cd "$BUILD_DIR" && \
    PKG_CONFIG_PATH="$CARES_PREFIX/lib/pkgconfig:$SQLITE_PREFIX/lib/pkgconfig" \
    CFLAGS="$FLAGS -O2" \
    CXXFLAGS="$FLAGS -O2" \
    LDFLAGS="$FLAGS" \
    "$ARIA2/configure" \
      --host="$ARCH-apple-darwin" \
      --enable-libaria2 \
      --enable-static \
      --disable-shared \
      --without-libxml2 \
      --without-libgmp \
      --without-libgcrypt \
      --without-libnettle \
      --without-gnutls \
      --without-openssl \
      --with-appletls \
      --with-libssh2=no \
      --without-libuv \
      ARIA2_STATIC=yes) >&2
  # 先编内部 deps（wslay 等），再编 src 下的 libaria2.la。
  # 不跑 `make install`：新版 macOS libtool 在 install 静态库时常因
  # relink_command 缓冲区限制误报 "File name too long"。libtool 在归档
  # 完成后的 .la 后处理步骤也会触发同一报错；只要 .libs/libaria2.a
  # 实际产出即视为成功。
  make -C "$BUILD_DIR/deps" -j"$(sysctl -n hw.ncpu)" >&2
  make -C "$BUILD_DIR/src"  -j"$(sysctl -n hw.ncpu)" libaria2.la >&2 || true
  local LIB_OUT="$BUILD_DIR/src/.libs/libaria2.a"
  if [[ ! -f "$LIB_OUT" ]]; then
    echo "[fatal] 未找到 $LIB_OUT；make 真的失败了" >&2
    exit 1
  fi
  echo "$BUILD_DIR"
}

BUILD_DIRS=()
for ARCH in "${TARGETS[@]}"; do
  BUILD_DIR=$(build_for_arch "$ARCH")
  BUILD_DIRS+=("$BUILD_DIR")
done

OUT="$TARGET_ROOT/universal"
mkdir -p "$OUT/include/aria2" "$OUT/deps"

# brew 的 .a 文件复制后是 read-only；先清掉旧产物以便覆盖。
rm -f "$OUT/libaria2.a" "$OUT/include/aria2/aria2.h"
rm -f "$OUT/deps/"*.a

if [[ ${#BUILD_DIRS[@]} -gt 1 ]]; then
  LIBS=()
  for d in "${BUILD_DIRS[@]}"; do LIBS+=("$d/src/.libs/libaria2.a"); done
  lipo -create -output "$OUT/libaria2.a" "${LIBS[@]}"
else
  cp "${BUILD_DIRS[0]}/src/.libs/libaria2.a" "$OUT/libaria2.a"
fi
cp "$ARIA2/src/includes/aria2/aria2.h" "$OUT/include/aria2/aria2.h"

# 依赖静态库（Homebrew 提供；macOS 上 TLS 由系统 SecureTransport 提供，
# 不再拷贝 OpenSSL libssl/libcrypto）。
for SRC in \
  "$CARES_PREFIX/lib/libcares.a" \
  "$SQLITE_PREFIX/lib/libsqlite3.a"; do
  if [[ -f "$SRC" ]]; then
    cp "$SRC" "$OUT/deps/"
  else
    echo "[warn] 缺少 $SRC，运行时由系统库兜底"
  fi
done

echo ""
echo "macOS libaria2 已就绪：$OUT"
echo "目录内容："
find "$OUT" -maxdepth 3 -print
