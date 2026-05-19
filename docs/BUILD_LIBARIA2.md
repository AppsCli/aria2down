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

## Android (NDK via Docker)

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
