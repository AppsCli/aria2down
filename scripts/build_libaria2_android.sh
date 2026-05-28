#!/usr/bin/env bash
# Build libaria2 (静态库) for Android — armeabi-v7a / arm64-v8a / x86_64。
#
# 输出：packages/aria2_native/prebuilt/android/<abi>/{libaria2.a, include/aria2/aria2.h, deps/*.a}
#
# 复用 third_party/aria2 的 Dockerfile.android 提供的 NDK + 依赖交叉编译方案，
# 把上游的 aria2c 目标替换为 libaria2 静态库。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARIA2="$ROOT/third_party/aria2"
TARGET_ROOT="$ROOT/packages/aria2_native/prebuilt/android"

ABIS=("${@:-armeabi-v7a arm64-v8a x86_64}")
ABIS=(${ABIS[@]:-armeabi-v7a arm64-v8a x86_64})

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

IMG_TAG="aria2down/libaria2-android:latest"
docker build -f "$ARIA2/Dockerfile.android" -t "$IMG_TAG" "$ARIA2"

for ABI in "${ABIS[@]}"; do
  case "$ABI" in
    armeabi-v7a) HOST=arm-linux-androideabi; API=21 ;;
    arm64-v8a)   HOST=aarch64-linux-android; API=21 ;;
    x86_64)      HOST=x86_64-linux-android;  API=21 ;;
    *) echo "不支持的 ABI: $ABI" >&2; exit 1 ;;
  esac
  OUT="$TARGET_ROOT/$ABI"
  mkdir -p "$OUT/include/aria2" "$OUT/deps"

  docker run --rm -v "$ARIA2":/aria2 -v "$OUT":/out \
    -e HOST_TRIPLET="$HOST" -e API="$API" "$IMG_TAG" bash -c '
      set -euo pipefail
      cd /aria2
      [[ -f configure ]] || autoreconf -i
      rm -rf /build && mkdir -p /build && cd /build
      NDK="${ANDROID_NDK_HOME:-/opt/android-ndk}"
      TOOLS=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin
      export PATH=$TOOLS:$PATH
      case "$HOST_TRIPLET" in
        arm-linux-androideabi) CLANG=armv7a-linux-androideabi$API-clang ;;
        *) CLANG=${HOST_TRIPLET}${API}-clang ;;
      esac
      export CC=$CLANG
      export CXX=${CLANG}++
      export AR=$TOOLS/llvm-ar
      export RANLIB=$TOOLS/llvm-ranlib
      export STRIP=$TOOLS/llvm-strip
      PREFIX=/install
      /aria2/configure \
        --host=$HOST_TRIPLET --prefix=$PREFIX \
        --enable-libaria2 --enable-static --disable-shared \
        --without-libxml2 --without-libgmp --without-libgcrypt \
        --without-libnettle --without-gnutls --with-openssl \
        --with-libssh2=no --without-libuv \
        ARIA2_STATIC=yes \
        CFLAGS="-O2 -fPIC" CXXFLAGS="-O2 -fPIC"
      make -j"$(nproc)"
      make install
      cp $PREFIX/lib/libaria2.a /out/libaria2.a
      cp $PREFIX/include/aria2/aria2.h /out/include/aria2/aria2.h
      for dep in libssl libcrypto libcares libsqlite3; do
        hit=$(find /deps /usr -name "${dep}.a" 2>/dev/null | head -n1 || true)
        [[ -n "$hit" ]] && cp "$hit" /out/deps/${dep}.a || true
      done
    '
  echo "Android $ABI 已就绪：$OUT"
done
