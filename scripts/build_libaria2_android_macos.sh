#!/usr/bin/env bash
# 在 macOS 本机上交叉编译 libaria2 + 依赖（OpenSSL / zlib / expat / c-ares）为
# Android 三个 ABI（armeabi-v7a / arm64-v8a / x86_64），落到
# packages/aria2_native/prebuilt/android/<abi>/。
#
# 行为与 docs/BUILD_LIBARIA2.md 描述一致：
#   ./scripts/build_libaria2_android_macos.sh               # 三个 ABI
#   ./scripts/build_libaria2_android_macos.sh arm64-v8a     # 只编 arm64
#   ANDROID_API=24  ./scripts/build_libaria2_android_macos.sh
#   NDK_HOME=/path/to/ndk ./scripts/build_libaria2_android_macos.sh
#   ENABLE_SQLITE3=1 ./scripts/build_libaria2_android_macos.sh
#
# 依赖：autoconf / automake / libtool / pkg-config / perl / curl
#   brew install autoconf automake libtool pkg-config perl
#
# 注：本脚本完全不依赖 Docker；NDK 中的 clang 跨编译直接产出静态库。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARIA2_SRC="$ROOT/third_party/aria2"
PREBUILT_ROOT="$ROOT/packages/aria2_native/prebuilt/android"
WORK_ROOT="$ROOT/build/libaria2/android-native"
CACHE_DIR="$WORK_ROOT/cache"

if [[ ! -d "$ARIA2_SRC" ]]; then
  echo "缺少子模块 third_party/aria2，请先 git submodule update --init --recursive" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# 参数 / 环境
# -----------------------------------------------------------------------------
ABIS=("$@")
[[ ${#ABIS[@]} -eq 0 ]] && ABIS=(armeabi-v7a arm64-v8a x86_64)

API="${ANDROID_API:-24}"   # Bionic 上 fseeko/ftello（被 NDK <fstream> 引用）要求 ≥ 24；
                           # 而 aria2_native 的 minSdk 本就锁定 24，保持一致。
ENABLE_SQLITE3="${ENABLE_SQLITE3:-0}"

OPENSSL_VER="${OPENSSL_VER:-3.0.15}"
ZLIB_VER="${ZLIB_VER:-1.3.1}"
EXPAT_VER="${EXPAT_VER:-2.5.0}"
CARES_VER="${CARES_VER:-1.21.0}"
SQLITE_VER="${SQLITE_VER:-3460000}"

JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

# -----------------------------------------------------------------------------
# 探测 NDK
# -----------------------------------------------------------------------------
detect_ndk() {
  local candidates=(
    "${NDK_HOME:-}"
    "${ANDROID_NDK_HOME:-}"
    "${ANDROID_NDK_ROOT:-}"
  )
  for c in "${candidates[@]}"; do
    if [[ -n "$c" && -d "$c/toolchains/llvm/prebuilt" ]]; then
      echo "$c"; return 0
    fi
  done
  local roots=(
    "${ANDROID_HOME:-}"
    "${ANDROID_SDK_ROOT:-}"
    "$HOME/Library/Android/sdk"
  )
  for r in "${roots[@]}"; do
    [[ -z "$r" || ! -d "$r/ndk" ]] && continue
    local latest
    latest="$(ls "$r/ndk" 2>/dev/null | sort -V | tail -n1 || true)"
    [[ -n "$latest" && -d "$r/ndk/$latest/toolchains/llvm/prebuilt" ]] && {
      echo "$r/ndk/$latest"; return 0
    }
  done
  return 1
}

NDK="$(detect_ndk || true)"
[[ -d "$NDK" ]] || { echo "无法定位 Android NDK；请设置 NDK_HOME 或 ANDROID_NDK_HOME" >&2; exit 1; }

# 工具链目录（NDK 27+ 在 Apple Silicon 仍只提供 darwin-x86_64，跑在 Rosetta 下；
# 未来若 Google 加入 darwin-arm64 也兼容）。
TC=""
for d in darwin-arm64 darwin-x86_64; do
  [[ -d "$NDK/toolchains/llvm/prebuilt/$d" ]] && TC="$NDK/toolchains/llvm/prebuilt/$d" && break
done
[[ -d "$TC" ]] || { echo "NDK $NDK 不含可用的 darwin LLVM 工具链" >&2; exit 1; }

echo "[info] NDK     = $NDK"
echo "[info] Toolch  = $TC"
echo "[info] API     = $API"
echo "[info] ABIs    = ${ABIS[*]}"
echo "[info] sqlite3 = $ENABLE_SQLITE3"
echo

# -----------------------------------------------------------------------------
# 工具
# -----------------------------------------------------------------------------
mkdir -p "$CACHE_DIR"

fetch() {
  # fetch <url> <archive>
  local url="$1"
  local file="$2"
  local target="$CACHE_DIR/$file"
  if [[ -f "$target" ]]; then return 0; fi
  echo "[fetch] $file <- $url"
  curl --fail --silent --show-error --location \
       --retry 3 --retry-delay 2 \
       -o "$target.part" "$url"
  mv "$target.part" "$target"
}

extract_to() {
  # extract_to <archive-file-in-cache> <destination-dir>
  local file="$1"
  local dest="$2"
  rm -rf "$dest"; mkdir -p "$dest"
  tar -xf "$CACHE_DIR/$file" -C "$dest" --strip-components=1
}

# -----------------------------------------------------------------------------
# 预下载（所有 ABI 共用同一份 tarball 缓存）
# -----------------------------------------------------------------------------
fetch "https://www.openssl.org/source/openssl-$OPENSSL_VER.tar.gz"                          "openssl-$OPENSSL_VER.tar.gz"
fetch "https://zlib.net/fossils/zlib-$ZLIB_VER.tar.gz"                                       "zlib-$ZLIB_VER.tar.gz"
fetch "https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VER//./_}/expat-$EXPAT_VER.tar.bz2" "expat-$EXPAT_VER.tar.bz2"
fetch "https://github.com/c-ares/c-ares/releases/download/cares-${CARES_VER//./_}/c-ares-$CARES_VER.tar.gz" "c-ares-$CARES_VER.tar.gz"
if [[ "$ENABLE_SQLITE3" == "1" ]]; then
  fetch "https://www.sqlite.org/2024/sqlite-autoconf-$SQLITE_VER.tar.gz" "sqlite-autoconf-$SQLITE_VER.tar.gz"
fi

# -----------------------------------------------------------------------------
# ABI -> 工具链/三元组映射
# -----------------------------------------------------------------------------
abi_triplet() {
  case "$1" in
    armeabi-v7a) echo "armv7a-linux-androideabi arm-linux-androideabi  android-arm";;
    arm64-v8a)   echo "aarch64-linux-android    aarch64-linux-android android-arm64";;
    x86_64)      echo "x86_64-linux-android     x86_64-linux-android  android-x86_64";;
    x86)         echo "i686-linux-android       i686-linux-android    android-x86";;
    *) return 1;;
  esac
}

# -----------------------------------------------------------------------------
# 单个 ABI 构建
# -----------------------------------------------------------------------------
build_abi() {
  local abi="$1"
  local triplet_line; triplet_line="$(abi_triplet "$abi")" || { echo "不支持 ABI: $abi" >&2; return 1; }
  # shellcheck disable=SC2206
  local triplet=($triplet_line)
  local CLANG_PREFIX="${triplet[0]}"
  local HOST="${triplet[1]}"
  local OPENSSL_TARGET="${triplet[2]}"

  local prefix="$WORK_ROOT/$abi/install"
  local workdir="$WORK_ROOT/$abi/src"
  mkdir -p "$prefix" "$workdir"

  export ANDROID_NDK_ROOT="$NDK"
  export ANDROID_NDK_HOME="$NDK"
  export PATH="$TC/bin:$PATH"
  export CC="$TC/bin/${CLANG_PREFIX}${API}-clang"
  export CXX="$TC/bin/${CLANG_PREFIX}${API}-clang++"
  export AR="$TC/bin/llvm-ar"
  export RANLIB="$TC/bin/llvm-ranlib"
  export NM="$TC/bin/llvm-nm"
  export STRIP="$TC/bin/llvm-strip"
  export LD="$TC/bin/ld"
  export CFLAGS="-O2 -fPIC -DANDROID -D__ANDROID_API__=$API"
  export CXXFLAGS="$CFLAGS"
  export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"
  export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
  export PKG_CONFIG_SYSROOT_DIR=""

  [[ -x "$CC"  ]] || { echo "找不到编译器 $CC" >&2; return 1; }
  [[ -x "$CXX" ]] || { echo "找不到编译器 $CXX" >&2; return 1; }

  # --- OpenSSL ---
  if [[ ! -f "$prefix/lib/libssl.a" ]]; then
    echo "==== [$abi] OpenSSL $OPENSSL_VER ===="
    extract_to "openssl-$OPENSSL_VER.tar.gz" "$workdir/openssl"
    (
      cd "$workdir/openssl"
      ./Configure no-shared no-tests no-engine \
        --prefix="$prefix" \
        -D__ANDROID_API__="$API" \
        "$OPENSSL_TARGET"
      make -j"$JOBS"
      make install_sw
    )
  else
    echo "==== [$abi] OpenSSL 已缓存，跳过 ===="
  fi

  # --- zlib ---
  if [[ ! -f "$prefix/lib/libz.a" ]]; then
    echo "==== [$abi] zlib $ZLIB_VER ===="
    extract_to "zlib-$ZLIB_VER.tar.gz" "$workdir/zlib"
    (
      cd "$workdir/zlib"
      CHOST="$HOST" ./configure --static --prefix="$prefix"
      make -j"$JOBS"
      make install
    )
  else
    echo "==== [$abi] zlib 已缓存，跳过 ===="
  fi

  # --- expat ---
  if [[ ! -f "$prefix/lib/libexpat.a" ]]; then
    echo "==== [$abi] expat $EXPAT_VER ===="
    extract_to "expat-$EXPAT_VER.tar.bz2" "$workdir/expat"
    (
      cd "$workdir/expat"
      ./configure --host="$HOST" --prefix="$prefix" \
        --disable-shared --enable-static \
        --without-docbook --without-examples --without-tests
      make -j"$JOBS"
      make install
    )
  else
    echo "==== [$abi] expat 已缓存，跳过 ===="
  fi

  # --- c-ares ---
  if [[ ! -f "$prefix/lib/libcares.a" ]]; then
    echo "==== [$abi] c-ares $CARES_VER ===="
    extract_to "c-ares-$CARES_VER.tar.gz" "$workdir/cares"
    (
      cd "$workdir/cares"
      ./configure --host="$HOST" --prefix="$prefix" \
        --disable-shared --enable-static \
        --disable-tests
      make -j"$JOBS"
      make install
    )
  else
    echo "==== [$abi] c-ares 已缓存，跳过 ===="
  fi

  # --- sqlite3 (optional) ---
  if [[ "$ENABLE_SQLITE3" == "1" && ! -f "$prefix/lib/libsqlite3.a" ]]; then
    echo "==== [$abi] sqlite3 $SQLITE_VER ===="
    extract_to "sqlite-autoconf-$SQLITE_VER.tar.gz" "$workdir/sqlite"
    (
      cd "$workdir/sqlite"
      ./configure --host="$HOST" --prefix="$prefix" \
        --disable-shared --enable-static
      make -j"$JOBS"
      make install
    )
  fi

  # --- aria2 ---
  # 始终重编 aria2 本体（带上本地 patches），重用上面依赖产物。
  echo "==== [$abi] aria2 (本地子模块, 含 patches) ===="
  rm -rf "$workdir/aria2"
  # 用 rsync 排除 .git 子目录避免 worktree 冲突；这里 cp -a 更便携且子模块 .git 是文件而非目录，OK。
  cp -a "$ARIA2_SRC" "$workdir/aria2"
  (
    cd "$workdir/aria2"
    PATCH_FILE="$ROOT/patches/third_party-aria2/android-openssl-drbg-and-ssl-guards.patch"
    if [[ -f "$PATCH_FILE" ]]; then
      # -N：已打过则跳过，便于增量重编。
      patch -p1 -N < "$PATCH_FILE"
    else
      echo "警告：未找到 $PATCH_FILE，将使用未打补丁的上游 aria2" >&2
    fi
    if [[ ! -f configure ]]; then
      autoreconf -i
    fi
    local sqlite_flag="--without-sqlite3"
    [[ "$ENABLE_SQLITE3" == "1" ]] && sqlite_flag="--with-sqlite3"

    # 通过 OPENSSL_CFLAGS / LIBS 等显式注入我们刚编出来的静态库，
    # 完全绕开 pkg-config 在 macOS 上找系统库的尴尬。
    ./configure --host="$HOST" \
      --prefix="$prefix/aria2" \
      --enable-libaria2 --enable-static --disable-shared \
      --without-libxml2 --without-libgmp --without-libgcrypt \
      --without-libnettle --without-gnutls --with-openssl \
      --with-libssh2=no --without-libuv \
      $sqlite_flag \
      ARIA2_STATIC=yes \
      OPENSSL_CFLAGS="-I$prefix/include" \
      OPENSSL_LIBS="-L$prefix/lib -lssl -lcrypto" \
      ZLIB_CFLAGS="-I$prefix/include" \
      ZLIB_LIBS="-L$prefix/lib -lz" \
      EXPAT_CFLAGS="-I$prefix/include" \
      EXPAT_LIBS="-L$prefix/lib -lexpat" \
      LIBCARES_CFLAGS="-I$prefix/include" \
      LIBCARES_LIBS="-L$prefix/lib -lcares"
    # 只编静态库 libaria2.la；不编 aria2c 可执行文件——Android Bionic 没有
    # 独立的 libpthread / librt，aria2c 链接会因 -lpthread/-lrt 失败，而我们
    # 只需要 FFI 链接用的 libaria2.a。先编 deps/（wslay 等内嵌依赖），再编 src 里的库。
    make -j"$JOBS" -C deps
    make -j"$JOBS" -C src libaria2.la
  )

  # --- 拷贝产物到 prebuilt/<abi>/ ---
  local out="$PREBUILT_ROOT/$abi"
  mkdir -p "$out/include/aria2" "$out/deps"
  # libtool 把真正的静态库放在 .libs/ 下；外层 libaria2.la 只是描述文件。
  cp -f "$workdir/aria2/src/.libs/libaria2.a"           "$out/libaria2.a"
  cp -f "$workdir/aria2/src/includes/aria2/aria2.h"     "$out/include/aria2/aria2.h"
  cp -f "$prefix/lib/libssl.a"     "$out/deps/libssl.a"
  cp -f "$prefix/lib/libcrypto.a"  "$out/deps/libcrypto.a"
  cp -f "$prefix/lib/libz.a"       "$out/deps/libz.a"
  cp -f "$prefix/lib/libexpat.a"   "$out/deps/libexpat.a"
  cp -f "$prefix/lib/libcares.a"   "$out/deps/libcares.a"
  if [[ "$ENABLE_SQLITE3" == "1" ]]; then
    cp -f "$prefix/lib/libsqlite3.a" "$out/deps/libsqlite3.a"
  fi

  echo "[OK]  Android $abi → $out"
}

for abi in "${ABIS[@]}"; do
  build_abi "$abi"
done

echo
echo "全部完成。产物概览："
for abi in "${ABIS[@]}"; do
  size=$(stat -f '%z' "$PREBUILT_ROOT/$abi/libaria2.a" 2>/dev/null || echo 0)
  printf "  %-15s libaria2.a = %10d bytes\n" "$abi" "$size"
done
