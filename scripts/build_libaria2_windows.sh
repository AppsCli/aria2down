#!/usr/bin/env bash
# Build libaria2 (静态库) for Windows x86_64 via mingw-w64 (跨平台 Docker)。
#
# 输出：packages/aria2_native/prebuilt/windows/x86_64/{libaria2.a, include/aria2/aria2.h, deps/*.a}
#
# 依赖：Docker（推荐 buildx）。复用 third_party/aria2/Dockerfile.mingw 的 toolchain
# 但目标改为 libaria2.a 而非 aria2c.exe。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARIA2="$ROOT/third_party/aria2"
TARGET="$ROOT/packages/aria2_native/prebuilt/windows/x86_64"

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

IMG_TAG="aria2down/libaria2-mingw:latest"
docker build -f "$ARIA2/Dockerfile.mingw" -t "$IMG_TAG" "$ARIA2"

# 在容器中跑 configure/make，输出装载到 $TARGET
mkdir -p "$TARGET/include/aria2" "$TARGET/deps"

docker run --rm -v "$ARIA2":/aria2 -v "$TARGET":/out "$IMG_TAG" bash -c '
  set -euo pipefail
  cd /aria2
  [[ -f configure ]] || autoreconf -i
  rm -rf /build && mkdir -p /build && cd /build
  HOST=x86_64-w64-mingw32
  PREFIX=/install
  CFLAGS="-O2" CXXFLAGS="-O2" \
  $HOST_PREFIX_OVERRIDE \
  /aria2/configure \
      --host=$HOST --prefix=$PREFIX \
      --enable-libaria2 --enable-static --disable-shared \
      --without-libxml2 --without-libgmp --without-libgcrypt \
      --without-libnettle --without-gnutls --with-openssl \
      --with-libssh2=no --without-libuv \
      ARIA2_STATIC=yes
  make -j"$(nproc)"
  make install
  cp $PREFIX/lib/libaria2.a /out/libaria2.a
  cp $PREFIX/include/aria2/aria2.h /out/include/aria2/aria2.h
  for dep in libssl libcrypto libcares libsqlite3; do
    hit=$(find /usr/$HOST/lib /usr/lib/$HOST -maxdepth 3 -name "${dep}.a" 2>/dev/null | head -n1 || true)
    [[ -n "$hit" ]] && cp "$hit" /out/deps/${dep}.a || true
  done
'

echo "Windows libaria2 已就绪：$TARGET"
