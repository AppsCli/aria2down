#!/usr/bin/env bash
# Build libaria2 (静态库) for iOS — device(arm64) + simulator(arm64/x86_64)。
#
# 输出：packages/aria2_native/prebuilt/ios/{arm64,sim}/{libaria2.a, include/..., deps/}
#
# 依赖：Xcode CLT、autoconf/automake/libtool。
#
# TLS 后端：与 macOS 保持一致使用 AppleTLS (SecureTransport)，由系统
# Security.framework 提供，无需为 iOS 交叉编译 OpenSSL。原脚本曾尝试
# 让 configure 自动探测 Homebrew openssl@3——但那是 macOS dylib，
# `ld: building for 'iOS', but linking in dylib built for 'macOS'`，
# 最终 ipa 链接必然失败。改 AppleTLS 后 deps/ 仅放可选静态依赖
# （目前为空；c-ares/sqlite3 视需要可后续补齐）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARIA2="$ROOT/third_party/aria2"
TARGET_ROOT="$ROOT/packages/aria2_native/prebuilt/ios"

if [[ ! -d "$ARIA2" ]]; then
  echo "缺少子模块 third_party/aria2" >&2; exit 1
fi

# 应用 aria2down 本地补丁——详见 build_libaria2_macos.sh 同名段落。
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

  # 注：本脚本目前依赖系统 / 外部 OpenSSL 静态库，没有就地编译 OpenSSL。
  # 如要在 deps/ 提供 libssl.a / libcrypto.a，OpenSSL Configure 必须加
  # `no-module no-dynamic-engine`，否则 OSSL_PROVIDER_load 在 iOS 沙盒里
  # 会尝试 dlopen 一个不存在的 modulesdir 而把 OpenSSL error queue 污染
  # 成 `DSO support routines::could not load the shared library`，进而
  # 让 SSL_CTX_new 返回 NULL，HTTPS 全失败。详见
  # scripts/build_libaria2_android_macos.sh OpenSSL configure 段注释。
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
