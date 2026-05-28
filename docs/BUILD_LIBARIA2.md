# 构建 libaria2 静态库（Phase 6 / ADR-007）

本文档说明如何为 aria2down 各平台构建 libaria2 静态库 + 依赖，并落入
`packages/aria2_native/prebuilt/<platform>/<arch>/`，以启用 **内嵌库** 默认引擎。

> 不在此放产物时，FFI 插件会编译为 **stub-only**，应用启动会自动回退到
> aria2c 子进程（前提是 `AppSettings.fallbackToSubprocess == true`）。

## 通用约定

| 路径 | 内容 |
| --- | --- |
| `packages/aria2_native/prebuilt/<platform>/<arch>/libaria2.a` | libaria2 静态库 |
| `packages/aria2_native/prebuilt/<platform>/<arch>/include/aria2/aria2.h` | 公共头文件 |
| `packages/aria2_native/prebuilt/<platform>/<arch>/deps/*.a` | 依赖静态库（OpenSSL、c-ares、sqlite3 等） |

CMake / Podspec 自动检测以上路径并在存在时定义 `ARIA2_FFI_WITH_LIBARIA2=1`。

## 通用 configure 选项

各脚本均使用以下 configure 模板：

```
--enable-libaria2 --enable-static --disable-shared
--without-libxml2 --without-libgmp --without-libgcrypt --without-libnettle
--without-gnutls --with-openssl --with-libssh2=no --without-libuv
ARIA2_STATIC=yes
```

## macOS / iOS

```bash
brew install autoconf automake libtool pkg-config openssl@3 c-ares sqlite3
./scripts/build_libaria2_macos.sh           # universal (arm64 + x86_64)
./scripts/build_libaria2_ios.sh             # device + simulator
```

- macOS 直接使用 Homebrew 的 `.a`。
- iOS 通常需要为 `OpenSSL/c-ares` 单独交叉编译；推荐先用
  [OpenSSL-Universal](https://github.com/krzyzanowskim/OpenSSL) 的预编译版本，
  把对应 `.a` 拷贝到 `prebuilt/ios/<arm64|sim>/deps/`。
- 如果只想出 stub 包验证 UI，跳过即可。

## Linux

```bash
sudo apt install build-essential autoconf automake libtool pkg-config \
  libssl-dev libc-ares-dev libsqlite3-dev zlib1g-dev
./scripts/build_libaria2_linux.sh
```

CI 中 `.github/workflows/build-aria2.yml` 已加入 `linux-libaria2` 任务。

## Windows (mingw-w64 via Docker)

```bash
docker --version
./scripts/build_libaria2_windows.sh
```

依赖随 aria2 自带的 `Dockerfile.mingw` 一起被构建并暴露在容器内的
`/usr/x86_64-w64-mingw32/lib/*.a`。

## Android

### 推荐：macOS 本机交叉编译（无 Docker）

如果开发机已经装了 Android Studio / Android NDK（多数 Flutter 开发者都有），
直接使用本机 NDK 交叉编译，**不需要 Docker**，迭代速度更快：

```bash
brew install autoconf automake libtool pkg-config perl
./scripts/build_libaria2_android_macos.sh                       # 三 ABI
./scripts/build_libaria2_android_macos.sh arm64-v8a             # 只编 arm64
ANDROID_API=24 ./scripts/build_libaria2_android_macos.sh        # 调整 minSdk
NDK_HOME=/path/to/ndk ./scripts/build_libaria2_android_macos.sh # 显式指定 NDK
```

NDK 路径会按以下顺序自动探测：`$ANDROID_NDK_HOME` →
`$ANDROID_NDK_ROOT` → `$ANDROID_HOME/ndk/<最新>` →
`$ANDROID_SDK_ROOT/ndk/<最新>` → `~/Library/Android/sdk/ndk/<最新>`。

依赖会自动下载并就地交叉编译（缓存到 `build/libaria2/android-native/cache`，
重复运行只需几秒钟）：

| 依赖 | 版本 | 备注 |
| --- | --- | --- |
| OpenSSL | 3.0.x LTS | 静态 `libssl.a` / `libcrypto.a`，TLS 后端 |
| zlib | 1.3.1 | 静态 `libz.a` |
| expat | 2.5.0 | 静态 `libexpat.a`，aria2 BitTorrent / Metalink 解析 |
| c-ares | 1.21.0 | 静态 `libcares.a`，异步 DNS |
| sqlite3 | 3.46.x | （可选，默认关闭）aria2 仅用其读 Firefox `cookies.sqlite`，移动端基本无意义 |

默认与 [Dockerfile.android](../third_party/aria2/Dockerfile.android) 行为一致，
不带 sqlite3。需要打开请显式：

```bash
ENABLE_SQLITE3=1 ./scripts/build_libaria2_android_macos.sh
```

每个 ABI 的产物落在 `packages/aria2_native/prebuilt/android/<abi>/`，可直接
`flutter build apk` 链接。

### aria2 本地补丁（必带，非可选）

子模块 [`third_party/aria2/`](../third_party/aria2/) 保持指向上游干净提交；
所有 aria2down 维护的源码改动以 patch 形式存放在
[`patches/third_party-aria2/`](../patches/third_party-aria2/)，由所有
`scripts/build_libaria2_*.sh` 在 `configure` 前 `patch -p1 -N` 注入，并通过 trap 在脚本
退出时 `git checkout` 还原子模块工作树。

| 补丁 | 目的 |
| --- | --- |
| `android-openssl-drbg-and-ssl-guards.patch` | **Android OpenSSL DRBG 绕路**（`Platform.cc` / `SimpleRandomizer.cc`）+ `LibsslTLSContext` null guard；所有改动都在 `#ifdef __ANDROID__` 守护里，macOS / Linux / Windows 编译为 no-op |
| `aria2-public-api-extensions.patch` | 暴露 `aria2::removeDownloadResult` / `purgeDownloadResult` / `getReservedDownload` / `getDownloadResults` 公共 API + `DownloadHandle` 5 个扩展 getter（`errorMessage` / `numSeeders` / `seeder` / `verifiedLength` / `verifyIntegrityPending`），并在 `<aria2/aria2.h>` 声明 4 个 `ARIA2DOWN_HAS_*` 特性宏让 FFI shim 编译期探测。**不打这个补丁** → 设置页一直显示「库引擎运行在功能受限模式」红条 |

> 维护提示：升级 aria2 子模块后若 patch 冲突，在干净子模块上改好再
> `git -C third_party/aria2 diff > patches/third_party-aria2/….patch` 更新补丁文件。

### 备选：Docker

如果机器上没有 Android NDK，或想完全复用上游 `Dockerfile.android` 的环境：

```bash
./scripts/build_libaria2_android.sh
```

会依次为 `armeabi-v7a` / `arm64-v8a` / `x86_64` 三个 ABI 输出静态库，目标
最低 API 21。

## 验证

构建完成后：

```bash
flutter pub get
flutter run -d macos          # 或 windows / linux / ios / android
```

打开「设置 → 本机引擎」，应能看到「内嵌库（libaria2）」处于激活状态。
若 deps 缺失或链接失败：
1. 检查日志中 `aria2_native: prebuilt libaria2 NOT found`；
2. 临时禁用「失败时自动回退到子进程」可看到具体启动错误；
3. 如需重新触发 CMake 检测，重新执行 `flutter clean && flutter pub get`。

## 体积参考

| 平台 | 仅 libaria2.a | + deps（openssl/c-ares/sqlite3） | 进入应用包后 strip |
| --- | --- | --- | --- |
| macOS（universal） | ~9 MB | ~22 MB | ~8 MB |
| Linux（x86_64） | ~6 MB | ~17 MB | ~7 MB |
| Windows（x86_64） | ~7 MB | ~19 MB | ~8 MB |
| Android（arm64） | ~5 MB | ~14 MB | ~6 MB |
| iOS（device arm64） | ~6 MB | ~18 MB | ~7 MB |

> 数据来自上游 aria2 1.37 release-static 基线 + Homebrew openssl@3，按调优情况
> 可上下浮动 ±20%。

## 参考

- [PLAN.md](../PLAN.md) Phase 6
- [docs/ARCHITECTURE.md](ARCHITECTURE.md) — ADR-007
- aria2 上游 [doc/manual-src/en/libaria2.rst](../third_party/aria2/doc/manual-src/en/libaria2.rst)
- 上游 [Dockerfile.mingw](../third_party/aria2/Dockerfile.mingw)
  / [Dockerfile.android](../third_party/aria2/Dockerfile.android)
