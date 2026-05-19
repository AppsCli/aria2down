#!/usr/bin/env bash
# Build libaria2 (静态库) for iOS — device(arm64) + simulator(arm64/x86_64)。
#
# 输出：packages/aria2_native/prebuilt/ios/{arm64,sim}/{libaria2.a, include/..., deps/*.a}
#
# 依赖：Xcode CLT、autoconf/automake/libtool、与 macOS 一致的 Homebrew openssl/c-ares/sqlite3。
# 注：iOS 静态依赖通常需要 OpenSSL-Universal（CocoaPods）或自行交叉编译。
# 本脚本演示链路；正式发布请在 docs/BUILD_LIBARIA2.md 进一步细化。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARIA2="$ROOT/third_party/aria2"
TARGET_ROOT="$ROOT/packages/aria2_native/prebuilt/ios"

if [[ ! -d "$ARIA2" ]]; then
  echo "缺少子模块 third_party/aria2" >&2; exit 1
fi
cd "$ARIA2"
[[ -f configure ]] || autoreconf -i

IPHONEOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
IPHONESIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
DEPLOY=14.0

build_for() {
  local SLUG="$1"     # arm64 / sim
  local SDK="$2"
  local ARCH="$3"
  local HOST="$4"
  local MIN_FLAG="$5"
  local BUILD_DIR="$ROOT/build/libaria2/ios-$SLUG-$ARCH"
  local INSTALL_DIR="$ROOT/build/libaria2/ios-$SLUG-$ARCH-install"
  rm -rf "$BUILD_DIR" "$INSTALL_DIR"
  mkdir -p "$BUILD_DIR"

  local CFLAGS="-arch $ARCH -isysroot $SDK $MIN_FLAG -fembed-bitcode -O2 -fPIC"

  (cd "$BUILD_DIR" && \
    CC="$(xcrun -find clang)" \
    CXX="$(xcrun -find clang++)" \
    CFLAGS="$CFLAGS" CXXFLAGS="$CFLAGS" LDFLAGS="$CFLAGS" \
    "$ARIA2/configure" \
      --host="$HOST" \
      --prefix="$INSTALL_DIR" \
      --enable-libaria2 --enable-static --disable-shared \
      --without-libxml2 --without-libgmp --without-libgcrypt \
      --without-libnettle --without-gnutls --with-openssl \
      --with-libssh2=no --without-libuv \
      --without-appletls \
      ARIA2_STATIC=yes)
  make -C "$BUILD_DIR" -j"$(sysctl -n hw.ncpu)"
  make -C "$BUILD_DIR" install
  echo "$INSTALL_DIR"
}

DEVICE_ARM64=$(build_for arm64 "$IPHONEOS_SDK" arm64 arm-apple-darwin "-miphoneos-version-min=$DEPLOY")
SIM_ARM64=$(build_for sim "$IPHONESIM_SDK" arm64 arm-apple-darwin "-mios-simulator-version-min=$DEPLOY")
SIM_X86=$(build_for sim "$IPHONESIM_SDK" x86_64 x86_64-apple-darwin "-mios-simulator-version-min=$DEPLOY")

mkdir -p "$TARGET_ROOT/arm64/include/aria2" "$TARGET_ROOT/arm64/deps"
mkdir -p "$TARGET_ROOT/sim/include/aria2"   "$TARGET_ROOT/sim/deps"

cp "$DEVICE_ARM64/lib/libaria2.a" "$TARGET_ROOT/arm64/libaria2.a"
cp "$DEVICE_ARM64/include/aria2/aria2.h" "$TARGET_ROOT/arm64/include/aria2/aria2.h"

lipo -create -output "$TARGET_ROOT/sim/libaria2.a" \
  "$SIM_ARM64/lib/libaria2.a" "$SIM_X86/lib/libaria2.a"
cp "$SIM_ARM64/include/aria2/aria2.h" "$TARGET_ROOT/sim/include/aria2/aria2.h"

echo "iOS libaria2 已就绪：$TARGET_ROOT"
echo "提示：OpenSSL/c-ares/sqlite3 等依赖请使用预编译的 iOS 静态库（如 OpenSSL-Universal CocoaPods）放入对应 deps/ 目录。"
