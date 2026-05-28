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
  # fetch <archive-file> <url1> [url2] [url3] ...
  #
  # 依赖 tarball 的"多源 fallback"下载：依次尝试每个 URL，命中第一个能拉到
  # 200 + 完整体积的就保存。已存在则跳过。本机所有平台、各种 GFW / 公司
  # 代理场景下都能覆盖：海外开发者首选 GitHub direct（最快），CN 用户
  # github.com 不通则自动 fall 到 ghproxy.net 等反代镜像，再退到上游
  # 官方源（如 www.openssl.org / zlib.net）。
  #
  # 超时策略：connect 8s + total 600s，retry 1 次。单 URL 失败最坏 ~20s
  # 即 fall 到下一个，三个 URL 全跑完最差也就 ~60s 才报失败。
  #
  # 想跳过网络？手动 `cp <tarball> build/libaria2/android-native/cache/`
  # 后重跑脚本即可——下面的 if-cached 短路会直接复用。
  local file="$1"; shift
  local target="$CACHE_DIR/$file"
  if [[ -f "$target" ]]; then
    echo "[fetch] $file (cached, $(stat -f %z "$target" 2>/dev/null || stat -c %s "$target") bytes)"
    return 0
  fi
  local url
  for url in "$@"; do
    echo "[fetch] $file <- $url"
    if curl --fail --silent --show-error --location \
         --retry 1 --retry-delay 2 \
         --connect-timeout 8 --max-time 600 \
         -o "$target.part" "$url"; then
      mv "$target.part" "$target"
      return 0
    fi
    rm -f "$target.part"
    echo "[fetch]   failed, trying next mirror..." >&2
  done
  echo "[fetch] all sources exhausted for $file" >&2
  echo "[fetch] tip: 把 $file 手动放到 $CACHE_DIR/ 后重跑脚本可跳过网络" >&2
  return 1
}

extract_to() {
  # extract_to <archive-file-in-cache> <destination-dir>
  #
  # 加一道完整性 retry：macOS 的 BSD tar 偶发会在 tar -xf 跑了一半静默
  # 退出，留下只有目录骨架的 0-byte 解压树（实测在并行 build 多 ABI 时
  # 触发率不算低）。重解后通常就能完整。空目录-> 再试一次，仍然失败
  # 才把命令抛错让外层 set -e 中断。
  local file="$1"
  local dest="$2"
  local attempt
  for attempt in 1 2 3; do
    rm -rf "$dest"
    mkdir -p "$dest"
    if tar -xf "$CACHE_DIR/$file" -C "$dest" --strip-components=1 \
         && [[ -n "$(ls -A "$dest" 2>/dev/null)" ]] \
         && [[ "$(find "$dest" -type f -size +0c 2>/dev/null | head -1)" != "" ]]; then
      return 0
    fi
    echo "[extract] $file → $dest attempt $attempt incomplete, retrying..." >&2
  done
  echo "[extract] $file → $dest failed after 3 attempts" >&2
  return 1
}

# -----------------------------------------------------------------------------
# 预下载（所有 ABI 共用同一份 tarball 缓存）
# -----------------------------------------------------------------------------
# OpenSSL：官网首发，GitHub release 镜像 + ghproxy.net 反代兜底。
# 注：www.openssl.org 在某些 ISP 上偶发 HTTP/2 framing 错误（curl: 16），
# 因此放在第三位作为 last resort。
fetch "openssl-$OPENSSL_VER.tar.gz" \
  "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz" \
  "https://ghproxy.net/https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz" \
  "https://www.openssl.org/source/openssl-$OPENSSL_VER.tar.gz"

# zlib：作者 GitHub release 是最稳的，zlib.net/fossils 留作兜底（被 GFW
# 拦截相对少）。
fetch "zlib-$ZLIB_VER.tar.gz" \
  "https://github.com/madler/zlib/releases/download/v$ZLIB_VER/zlib-$ZLIB_VER.tar.gz" \
  "https://ghproxy.net/https://github.com/madler/zlib/releases/download/v$ZLIB_VER/zlib-$ZLIB_VER.tar.gz" \
  "https://zlib.net/fossils/zlib-$ZLIB_VER.tar.gz"

# expat / c-ares：上游只在 GitHub release 发布；CN 必须走 ghproxy.net。
fetch "expat-$EXPAT_VER.tar.bz2" \
  "https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VER//./_}/expat-$EXPAT_VER.tar.bz2" \
  "https://ghproxy.net/https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VER//./_}/expat-$EXPAT_VER.tar.bz2"

fetch "c-ares-$CARES_VER.tar.gz" \
  "https://github.com/c-ares/c-ares/releases/download/cares-${CARES_VER//./_}/c-ares-$CARES_VER.tar.gz" \
  "https://ghproxy.net/https://github.com/c-ares/c-ares/releases/download/cares-${CARES_VER//./_}/c-ares-$CARES_VER.tar.gz"

if [[ "$ENABLE_SQLITE3" == "1" ]]; then
  # sqlite.org 通常可直连；备用源可由用户手动放进 cache。
  fetch "sqlite-autoconf-$SQLITE_VER.tar.gz" \
    "https://www.sqlite.org/2024/sqlite-autoconf-$SQLITE_VER.tar.gz"
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
      # no-module / no-dynamic-engine: 关键！OpenSSL 3.0 的 OSSL_PROVIDER_load
      # 即便 default/legacy provider 是 builtin，仍会先尝试 dlopen
      # `<modulesdir>/<name>.so`。Android 设备上 modulesdir 是交叉编译机的
      # macOS 路径（嵌进 libcrypto.a 的 MODULESDIR 字面量），dlopen 必失败
      # 并把 `error:12800067:DSO support routines::could not load the shared
      # library` 推到 OpenSSL error queue。下游 SSL_CTX_new 看到非空 error
      # queue 直接返回 NULL，最终冒到 Dart 侧表现为
      # `SSL initialization failed:`，HTTPS 全军覆没。加 no-module 让
      # OSSL_PROVIDER_load 完全走 builtin 注册路径，跳过 dlopen。
      # no-deprecated 不能加：aria2down 的 RAND_set_rand_method hook 是
      # deprecated API，加了会编译失败。
      ./Configure no-shared no-tests no-engine no-module no-dynamic-engine \
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
    # 两个补丁都必须应用：
    #   1) android-openssl-drbg-and-ssl-guards.patch  Android SECCOMP/DRBG 兜底
    #   2) aria2-public-api-extensions.patch          ARIA2DOWN_HAS_* 公开 API
    # FFI shim 编译时按宏决定走 native fast path 还是 Dart 软降级。后者缺失
    # 会让设置页一直显示「库引擎运行在功能受限模式」红条。
    for PATCH_FILE in \
      "$ROOT/patches/third_party-aria2/android-openssl-drbg-and-ssl-guards.patch" \
      "$ROOT/patches/third_party-aria2/aria2-public-api-extensions.patch"; do
      if [[ -f "$PATCH_FILE" ]]; then
        # -N：已打过则跳过，便于增量重编。
        patch -p1 -N < "$PATCH_FILE"
      else
        echo "警告：未找到 $PATCH_FILE，将使用未打补丁的上游 aria2" >&2
      fi
    done
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
