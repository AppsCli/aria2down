# 变更日志

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 约定，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 修复（Android：HTTPS 握手仍报 `unable to get local issuer certificate`——OpenSSL 3 的 hash 查找看不到 Android 用的旧 hash CA 文件）

用户反馈："上一版补丁（commit `7e4692c`）虽然路径接对了，但 HTTPS 仍然 `unable to get local issuer certificate`。"

调试时复现到底层 OpenSSL：调用 `SSL_CTX_load_verify_locations(ctx, NULL, "/system/etc/security/cacerts")` **返回 1（成功）**，但握手时仍然找不到根 CA。根因：

- Android 系统 CA 目录里的文件是 hash-named PEM——比如 `00673b5b.0`、`a3f1333d.0`——文件名是**证书 subject 的 hash**，OpenSSL 在握手期 by-hash 查找信任锚时直接 `open(<dir>/<hash>.0)`，不读目录索引。
- 这个 hash 算法在 OpenSSL 0.9.8 时改过一次：旧实现是 `X509_NAME_hash_old`，新实现是 `X509_NAME_hash`。Android 平台为了兼容 4.0 时代的 BoringSSL，**目录里的文件名仍然用旧算法生成**；而 OpenSSL 3.0 默认查找时用的是**新算法**。
- 结果：`SSL_CTX_load_verify_locations` 把目录登记进 store 但实际验证一张证书都对不上 hash 名，X509_STORE 看似有路径但实质为空，验证报 `unable to get local issuer certificate`。

**修复（用 NDK 标准 POSIX 直接遍历目录加载，绕开 hash 查找）**：[`patches/third_party-aria2/android-openssl-drbg-and-ssl-guards.patch`](patches/third_party-aria2/android-openssl-drbg-and-ssl-guards.patch) 重写 [`OpenSSLTLSContext::addSystemTrustedCACerts`](third_party/aria2/src/LibsslTLSContext.cc) 的 `__ANDROID__` 分支：

1. 用 NDK 自带的 `<dirent.h>` `opendir` / `readdir` / `closedir` 遍历两条 Android CA 目录（按通用性递减：`/apex/com.android.conscrypt/cacerts/` → `/system/etc/security/cacerts/`），命中第一条加载成功（`loadedHere > 0`）的目录就停。
2. 对每个 directory entry 用 `stat()` 过滤掉非普通文件（防 `.` / `..` / 符号链接误判）；然后 `BIO_new_file` 打开 PEM 文件 → 内层 `while (PEM_read_bio_X509(...))` 循环读所有证书（罕见但合法的多证书 PEM 也能覆盖）→ `X509_STORE_add_cert(SSL_CTX_get_cert_store(ctx), cert)` 直接塞进 store。
3. 每个文件读完后 / 每次 add_cert 后无条件 `ERR_clear_error()`：`PEM_read_bio_X509` 到 EOF 时会 push `PEM_R_NO_START_LINE`，`X509_STORE_add_cert` 在 cert 已在 store 时 push `X509_R_CERT_ALREADY_IN_HASH_TABLE`，两者都不是错误，但留在 error queue 会污染后续 `SSL_get_error`。
4. 通过 `__android_log_print` + `A2_LOG_INFO` 上报实际加载数量与目录：`Loaded %d Android system CAs from %s`。两条目录都加载不到时上报 `No Android system CA loadable from /apex or /system; HTTPS verification will fail. Try --check-certificate=false as workaround.` 并 fallback 到上游 `SSL_CTX_set_default_verify_paths`（虽然在 Android 上几乎肯定也失败，但保留语义、不致命）。

通过把 cert 直接 add 进 X509_STORE，OpenSSL 验证时按线性 STACK 遍历找 issuer，**完全不走 hash 文件名查找**——Android 旧 hash 与 OpenSSL 3 新 hash 的差异问题被绕过。

**为何不用 JNI 取 Android KeyStore**：那需要 native 拿到 JNIEnv（aria2 worker isolate 上下文不持有 JNI ref，要往 plugin 抽线缆 + ART 注入，复杂度过高），且 JNI 调用每个 cert 都要跨 ART 边界。POSIX `readdir` + `BIO_new_file` 没有 JNI 开销，且 SELinux 策略上 untrusted_app 域对 `/system/etc/security/cacerts/`、`/apex/com.android.conscrypt/cacerts/` 都有 `r_file_perms`，普通 App 进程可直读。

**验证**：

- `./scripts/build_libaria2_android_macos.sh` 重编三 ABI：`libaria2.a` 每个 ABI 比上一轮大 ~1.4 KB（对应 readdir 循环的 native code）。三 ABI 各 9 个 unique extern 符号引用（`opendir` / `readdir` / `closedir` / `stat` 来自 NDK Bionic；`PEM_read_bio_X509` / `X509_STORE_add_cert` / `SSL_CTX_get_cert_store` / `BIO_new_file` / `BIO_free` 来自 OpenSSL），4 条新诊断字面量（`Loaded %d Android system CAs from %s` / `opendir(%s) failed: %d` / fallback warning + info）+ 两条目录路径全部就位。
- `flutter build apk --debug --target-platform android-arm64`：链接通过，`lib/arm64-v8a/libaria2_native.so` 8.0 M，含全部 4 条 CA-related 字面量。
- 子模块工作树 clean（脚本 trap revert 正常）。

**用户后续操作**：拉 commit → 重跑 `./scripts/build_libaria2_android_macos.sh`（OpenSSL/deps cache 保留，只 aria2 重链接，<1 分钟）→ `flutter clean` + `flutter run -d <android>`。设备上 `adb logcat -s aria2down` 应该看到一行：

```
I/aria2down: Loaded 152 Android system CAs from /apex/com.android.conscrypt/cacerts
```

（具体数字依设备 Android 版本而定，通常 100~200）。HTTPS 下载应该可用了。若 logcat 显示 `0 CAs` 或 fallback warning，请贴 logcat 全文（特别是 `opendir(...) failed: %d`，错误码非 2 / 13 的情况下能指向具体问题）。

### 修复（Android：HTTPS 握手报 `SSL/TLS handshake failure: unable to get local issuer certificate`，OpenSSL 不识别 Android 系统 CA）

用户反馈："拉了上一轮 `SSL initialization failed:` 修复后的 prebuilt 重新打包，初始化不再失败了，但 HTTPS 下载握手期间报 `SSL/TLS handshake failure: unable to get local issuer certificate`。"

`unable to get local issuer certificate` 是 OpenSSL 标准的证书链验证错误：握手期间服务器发回的证书链能解析，但 OpenSSL 找不到颁发它的根 CA，所以拒绝信任。aria2 在 `--check-certificate=true`（默认开启）时会调 [`OpenSSLTLSContext::addSystemTrustedCACerts`](third_party/aria2/src/LibsslTLSContext.cc) 加载系统 CA，上游实现走 `SSL_CTX_set_default_verify_paths(sslCtx_)`——这查找的是 OpenSSL **编译时**烤进 libcrypto.a 的 `OPENSSLDIR/certs/`。

跑 `strings packages/aria2_native/prebuilt/android/arm64-v8a/deps/libcrypto.a | grep OPENSSLDIR` 看到：

```
OPENSSLDIR: "/Users/iotserv/git/aria2down/build/libaria2/android-native/arm64-v8a/install/ssl"
```

也就是交叉编译机（macOS）的本地路径——Android 设备上根本不存在。`SSL_CTX_set_default_verify_paths` 加载零个根 CA，trust store 实际是空的，任何公网 HTTPS 链路都通不过验证。

Android **本身**有完整的系统 CA：

| 路径 | 适用版本 | 说明 |
| --- | --- | --- |
| `/apex/com.android.conscrypt/cacerts/` | Android 14 / API 34+ | Conscrypt APEX 模块下的真实存储位置 |
| `/system/etc/security/cacerts/` | Android 6+ / API 23+ | 通用路径；API 34+ 上是符号链接到 conscrypt APEX |

两条都是 hash-named PEM 目录（文件名形如 `00673b5b.0`、`a3f1333d.0`），格式上 OpenSSL `SSL_CTX_load_verify_locations(ctx, NULL, dir_path)` 直接可识别。

**修复**：[`patches/third_party-aria2/android-openssl-drbg-and-ssl-guards.patch`](patches/third_party-aria2/android-openssl-drbg-and-ssl-guards.patch) 给 `OpenSSLTLSContext::addSystemTrustedCACerts` 加 `__ANDROID__` 分支：按上表顺序尝试 `SSL_CTX_load_verify_locations(sslCtx_, nullptr, *p)`，命中第一条就返回 true，并经 `__android_log_print` + `A2_LOG_INFO` 上报具体使用的目录（`adb logcat -s aria2down` 能看到 `Loaded Android system CA dir: /apex/com.android.conscrypt/cacerts`）。每次 `SSL_CTX_load_verify_locations` 失败时立刻 `ERR_clear_error()` 清掉 error queue，避免污染下一条路径或后续 `SSL_get_error`。两条都不可达时仍 fallback 到原 `SSL_CTX_set_default_verify_paths`（保留上游语义），并各级日志都有提示。

不进入此路径的两种情况保持原语义：

- 用户显式 `--ca-certificate=<file>` → 走 `addTrustedCACertFile`（已工作正常）；
- 用户显式 `--check-certificate=false` → 完全跳过验证（不推荐，但可作为应急手段）。

**验证**：

- `./scripts/build_libaria2_android_macos.sh` 全新重编三 ABI（NDK r27 / API 24）：libaria2.a 每个 ABI 比上一轮大约多 ~1 KB（对应新增 Android CA 分支代码），三 ABI 的 `strings libaria2.a` 各含两条字面量 `/apex/com.android.conscrypt/cacerts` + `/system/etc/security/cacerts` + 日志模板 `Loaded Android system CA dir: %s`。
- `flutter build apk --debug --target-platform android-arm64` 链接通过；`lib/arm64-v8a/libaria2_native.so` 内同时含上述 3 个 CA 相关字面量 + 之前几轮补丁的所有字面量。
- 子模块工作树 clean（脚本 trap 起效）。

**用户后续操作**：拉到此 commit → 重跑 `./scripts/build_libaria2_android_macos.sh`（OpenSSL/deps 缓存可保留，只 aria2 重链接，约 30 秒）→ `flutter clean && flutter run -d <android>`。HTTPS 下载应当可正常完成；设备上 `adb logcat -s aria2down` 应能看到一行 `Loaded Android system CA dir: /apex/com.android.conscrypt/cacerts` 或 `/system/etc/security/cacerts`。如仍失败请贴这条日志的下一行（fallback 警告）+ 报错完整信息。

### 修复（Android：HTTPS 下载报 `SSL initialization failed:`，OpenSSL 3.0 静态库 + DRBG 路径多重隐患）

用户反馈："Android 上拿 commit `5daf895` 的 prebuilt 跑，HTTPS 下载报错 `SSL initialization failed:`。"

`SSL initialization failed:` 由 [SocketCore::tlsConnect](third_party/aria2/src/SocketCore.cc) 在 `tlsSession_->init()` 失败时抛出（仅 OpenSSL TLS 后端，即 Android / Linux / 走 OpenSSL 的 iOS；macOS 走 AppleTLS、Windows 走 WinTLS 不会到这条路径）。沿着调用链回溯：[OpenSSLTLSSession::init](third_party/aria2/src/LibsslTLSSession.cc) `SSL_new(ctx->getSSLCtx())` 返回 NULL → `getSSLCtx()` 自身是 NULL → 上一级 `OpenSSLTLSContext` 构造时 `SSL_CTX_new(SSLv23_method())` 已返回 NULL（aria2down 旧补丁加了 null guard 让 daemon 不再立刻 segfault，但 HTTPS 也就全军覆没）。

根因有**两层**叠加：

1. **OpenSSL 静态库被 macOS 编译机的 DSO 路径污染。** [`packages/aria2_native/prebuilt/android/<abi>/deps/libcrypto.a`](packages/aria2_native/prebuilt/android/) 内 `strings` 能看到 `MODULESDIR: "/Users/iotserv/git/aria2down/build/.../install/lib/ossl-modules"` 和 `OPENSSLDIR: "/Users/iotserv/git/aria2down/build/.../install/ssl"`——这是交叉编译时 OpenSSL `./Configure` 留下的字面量，并不会在 Android 设备上存在。OpenSSL 3.0 的 `OSSL_PROVIDER_load(NULL, "default")` 即便 default provider 是 builtin，仍然先把 `<modulesdir>/default.so` dlopen 一遍，dlopen 失败把 `error:12800067:DSO support routines::could not load the shared library` 推到 OpenSSL error queue。后续 `SSL_CTX_new` 看见非空 error queue 直接放弃。
2. **OpenSSL 3.0 的 EVP_RAND DRBG 仍可能走 getrandom syscall。** 上一版 patch 的 `RAND_set_rand_method(&devurandom_method)` 只覆盖 deprecated 的 `RAND_bytes` 调用链；OpenSSL 3.0 内部 `SSL_CTX_new_ex` 调的 `RAND_priv_bytes_ex(libctx, ...)`，在 libctx ≠ NULL 时会转发到 default provider 的 EVP_RAND，绕过 method hook。在 MIUI / 类似 SECCOMP 拦截 ROM 上 DRBG 实例化失败，连锁导致 `cookie_hmac_key` 生成失败 → `SSL_CTX_new` 返回 NULL。

同时上一版 patch 还有**两个用户可见的盲区**：

- `OpenSSLTLSSession::init` 在 `ssl_=NULL` 时 `rv_=1` 没改，[`getLastErrorString()`](third_party/aria2/src/LibsslTLSSession.cc) 走 `else return "";` → 用户看到的 `SSL initialization failed:` 后面是空字符串，根本不知道是哪一步失败的；
- `LibsslTLSContext` 构造时 `ERR_get_error()` 已经把 SSL_CTX_new 失败的错误从 queue 里**消费**掉了，即使想后取也取不到。

**修复（三件套）**：

1. **剔除 OpenSSL DSO 路径**：[`scripts/build_libaria2_android_macos.sh`](scripts/build_libaria2_android_macos.sh) 的 OpenSSL `./Configure` 加 `no-module no-dynamic-engine`。前者让 `OSSL_PROVIDER_load` 完全走 builtin 注册路径不再 dlopen，后者剔除 dynamic engine 框架，杜绝 DSO 错误污染 error queue。`no-deprecated` 不加（aria2down 的 `RAND_set_rand_method` hook 是 deprecated API，加了会编译失败）。同步在 [`scripts/build_libaria2_android.sh`](scripts/build_libaria2_android.sh) / [`scripts/build_libaria2_ios.sh`](scripts/build_libaria2_ios.sh) 加注释，要求外部 / Docker 构建路径也带这两个 flag。
2. **主动喂 DRBG**：[`patches/third_party-aria2/android-openssl-drbg-and-ssl-guards.patch`](patches/third_party-aria2/android-openssl-drbg-and-ssl-guards.patch) 在 `Platform::setUp` 的 Android 分支里，`RAND_set_rand_method(&devurandom_method)` 之后立刻：(a) 用 `devurandom_bytes_impl` 直读 256 字节 `/dev/urandom`，(b) `RAND_seed(buf, 256)` 喂给 default DRBG，(c) `RAND_priv_bytes(test, 16)` 自检一次。这样即使 EVP_RAND DRBG 绕过了 method hook，DRBG 也已经被预先实例化，`SSL_CTX_new` 内部 `RAND_priv_bytes_ex(libctx, ...)` 直接命中 cached state 即可。`OPENSSL_init_crypto` 同时补上 `ADD_ALL_CIPHERS | ADD_ALL_DIGESTS`（在 3.0 上是 NOOP，但保证未来如果链接到 1.1.1 也能 fire 完整初始化）。三件 logcat 输出 (`adb logcat -s aria2down`) 把所有自检结果挂上去。
3. **诊断信息穿透到用户层**：补丁给 [`LibsslTLSContext.cc`](third_party/aria2/src/LibsslTLSContext.cc) 加一个 `aria2::g_aria2down_lastSslCtxNewError` 全局字符串，在 `SSL_CTX_new` 失败时把 `ERR_error_string` 复制一份。配套 [`LibsslTLSSession.cc`](third_party/aria2/src/LibsslTLSSession.cc) 改 `getLastErrorString()`：检测到 `ssl_=NULL`（即 `SSL_new(NULL)` 失败的链头）就回退到 `g_aria2down_lastSslCtxNewError`，用户层 throw 的 `SSL initialization failed: <真实 cause>` 不再是空冒号。

**验证**：

- `scripts/build_libaria2_android_macos.sh` 重新生成 armeabi-v7a / arm64-v8a / x86_64 三套 prebuilt：`nm libcrypto.a` 仍含 DSO 框架的 dead code（OpenSSL 静态库内部统一编译），但 default/legacy provider 是 builtin（`init_function != NULL`），运行时 `provider_init` 跳过整个 DSO 加载块；libaria2.a 内 `strings` 命中 4 个新诊断字面量（`OPENSSL_init_crypto(...,add-all)`、`RAND_seed(... from /dev/urandom)`、`RAND_priv_bytes self-test`、`TLS context is not initialized`）。
- `flutter build apk --debug --target-platform android-arm64,android-arm,android-x64`：链接通过，三 ABI 的 `lib/<abi>/libaria2_native.so` 内同时含 capability 字面量（功能受限红条消失）和上述新诊断字面量。

**用户后续操作**：拉到此 commit + 重跑 `./scripts/build_libaria2_android_macos.sh` 刷新 prebuilt → `flutter build apk` 重打包。设备上 `adb logcat -s aria2down` 可以观察四行自检（`OPENSSL_init_crypto(...) -> 1` / `RAND_set_rand_method -> 1` / `RAND_seed(256 bytes from /dev/urandom) OK` / `RAND_priv_bytes self-test -> 1`）。如果**仍然**报 `SSL initialization failed:`，错误字符串后面现在一定有具体 cause（OpenSSL error 文本），把它和 logcat `aria2down` 一并贴出便于继续诊断。

### 修复（设置页：「库引擎运行在功能受限模式」红条挥之不去，因 aria2 公开 API 扩展补丁文件被遗漏）

用户反馈："macOS 应用启动后设置页一直挂着一条红色 banner 提示『库引擎运行在功能受限模式』，缺四项能力（`removeDownloadResult` / `listReserved` / `listDownloadResults` / `downloadHandleExt`）。"

- **根因**：[`patches/third_party-aria2/`](patches/third_party-aria2/) 目录在最近一次重构中**只保留了 `android-openssl-drbg-and-ssl-guards.patch`**，而 aria2down 维护的「公开 API 扩展」补丁——即在 aria2 的 [`src/includes/aria2/aria2.h`](third_party/aria2/src/includes/aria2/aria2.h) 暴露 `aria2::removeDownloadResult` / `purgeDownloadResult` / `getReservedDownload` / `getDownloadResults` 公共 API，并给 `DownloadHandle` 增加 5 个扩展 getter（`getErrorMessage` / `getNumSeeders` / `isSeeder` / `getVerifiedLength` / `isVerifyIntegrityPending`），以及 4 个 `ARIA2DOWN_HAS_*` 特性宏——这份补丁文件**从未实际落盘**。结果：`scripts/build_libaria2_*.sh` 全部走未打补丁的上游源码编译，`aria2_ffi.cc` 编译期 `#ifdef ARIA2DOWN_HAS_*` 全部走 `#else` 软降级路径，`aria2_ffi_get_capabilities` 返回空 JSON 数组，[`libraryCapabilitiesProvider`](lib/providers/library_capabilities_provider.dart) 把所有 4 项 capability 标记缺失，UI 弹红条不退。
- **修复**：
  1. 在 [`patches/third_party-aria2/aria2-public-api-extensions.patch`](patches/third_party-aria2/aria2-public-api-extensions.patch) 重建该补丁（280 行 unified diff，触达 `src/aria2api.cc` + `src/includes/aria2/aria2.h` 两份文件）。
     - 头文件加 4 个 `ARIA2DOWN_HAS_*` 宏 + `DownloadHandle` 5 个 pure-virtual getter + 4 个新公开函数签名；
     - 实现文件给 `RequestGroupDH` 注入 `DownloadEngine*` 并实现 5 个 getter（`getNumSeeders` 走 `BtRegistry::get()->peerStorage->getUsedPeers()` + `countSeeder`，`getVerifiedLength` / `isVerifyIntegrityPending` 走 `CheckIntegrityMan::isPicked/isQueued`，镜像 [`RpcMethodImpl::gatherProgress*`](third_party/aria2/src/RpcMethodImpl.cc) 的逻辑）；`DownloadResultDH` 给停止任务的 5 个 getter 返回安全默认值；4 个公开 API 是 `RequestGroupMan` 现成方法的薄包装。
  2. 在所有 5 份 `scripts/build_libaria2_*.sh` 里加上「`configure` 前 `patch -p1 -N` + 退出时 trap `git checkout` 还原子模块工作树」段落，保证 `third_party/aria2` 始终干净，且补丁幂等可重跑。
  3. [`patches/third_party-aria2/README.md`](patches/third_party-aria2/README.md) 与 [`docs/BUILD_LIBARIA2.md`](docs/BUILD_LIBARIA2.md) 同步登记新补丁与新流程。
- **验证**：`patch -p1 --dry-run -N` 两个补丁可独立 + 组合干净应用到当前子模块 commit；prebuilt 重建一次（`./scripts/build_libaria2_macos.sh` 或对应平台脚本）即生效。
- **后续操作（用户侧）**：重新跑一次 `./scripts/build_libaria2_<platform>.sh` 刷新 `packages/aria2_native/prebuilt/<platform>/<arch>/{libaria2.a, include/aria2/aria2.h}`，然后 `flutter clean && flutter run` 即可看到红条消失、四项能力全部启用。

### 修复（Android：在 MIUI / 类似沙盒上启动即崩溃，aria2 daemon 起不来）

在部分 Android 设备（已知 **MIUI 12+ / Redmi K30 5G** 等机型）上，首次进入「本机引擎」模式会触发两段连环 native crash，App 还没显示首屏就被 Bionic 杀掉：

| # | 信号 | 位置 | 含义 |
| --- | --- | --- | --- |
| 1 | SIGABRT | `SimpleRandomizer.cc:121: assert(1 == rv) failed` | OpenSSL `RAND_bytes()` 返回 0；aria2 peer-id 生成 abort |
| 2 | SIGSEGV (fault `0x28`) | `SSL_CTX_set_default_verify_paths(NULL)` ← `OpenSSLTLSContext::addSystemTrustedCACerts` ← `MultiUrlRequestInfo::prepare` | `SSL_CTX_new()` 返回 NULL（内部走 `RAND_priv_bytes_ex` 生成 session-ticket 密钥失败），调用方没做空指针检查直接 deref |

**根因（同一个 SECCOMP 拦截）**：

OpenSSL 3.0 的 DRBG 首次取熵时按顺序尝试 `getentropy()`（弱符号绑定到 Bionic）→ `__NR_getrandom` syscall → `/dev/urandom`。MIUI 等 ROM 给应用沙盒下发的 SECCOMP 过滤器把 `getrandom(2)` 直接拒掉，Bionic 的 `getentropy()` 把 `EPERM` 透传出来；OpenSSL [`rand_unix.c::syscall_random`](https://github.com/openssl/openssl/blob/openssl-3.0.15/providers/implementations/rands/seeding/rand_unix.c) 看到 `errno != ENOSYS` 直接 `return -1`，**不会**进入下一段直 syscall 兜底，DRBG 永远停留在未实例化错误状态，下游所有 `RAND_bytes() / RAND_priv_bytes_ex()` 都返回 0，依赖它们的 `SSL_CTX_new` / aria2 peer-id / metalink nonce 等组件全部跟着崩。

**修复（多层防御 + null guard）**：

1. **[`third_party/aria2/src/Platform.cc`](third_party/aria2/src/Platform.cc) — 主路径**：在 `Platform::setUp()` 里、加载 `OSSL_PROVIDER_load("default")` 之前注册一个仅在 `__ANDROID__` 编译目标生效的自定义 [`RAND_METHOD`](https://docs.openssl.org/3.0/man3/RAND_set_rand_method/) `devurandom_method`。它的 `bytes()` 钩子直接走 `syscall(SYS_getrandom)` → `read("/dev/urandom")` 双兜底，完全绕过 OpenSSL 的 DRBG 实例化流程。

   关键点：OpenSSL 3.0 的 `RAND_bytes_ex` **和** `RAND_priv_bytes_ex` 都会先 `RAND_get_rand_method() != RAND_OpenSSL()` 然后直接派发给我们的钩子（[crypto/rand/rand_lib.c#L325, L354](https://github.com/openssl/openssl/blob/openssl-3.0.15/crypto/rand/rand_lib.c#L325)），所以单点 hook 同时治 SSL_CTX_new、SimpleRandomizer、BT MSE 全部内部消费者。

   同时显式调 `OPENSSL_init_crypto(OPENSSL_INIT_NO_LOAD_CONFIG | OPENSSL_INIT_NO_ATEXIT | ADD_ALL_CIPHERS | ADD_ALL_DIGESTS)` 抢在 SSL 路径前 fire 一次 RUN_ONCE，避免后续 `SSL_CTX_new` 隐式 `OPENSSL_init_ssl()` 触发 `openssl.cnf` 加载（`--openssldir` 是宿主机的交叉编译路径，设备上根本不存在），以及 atexit 注册（在 Android 进程结束时不安全）。这两个调用的返回值都通过 `__android_log_print(ANDROID_LOG_INFO, "aria2down", ...)` 写入 logcat，方便用户通过 `adb logcat -s aria2down` 一眼确认 hook 是否生效。

2. **[`third_party/aria2/src/SimpleRandomizer.cc`](third_party/aria2/src/SimpleRandomizer.cc) — 副线保险**：在 OpenSSL 分支保留一份 `RAND_bytes() != 1 → fallback_random_bytes` 的本地兜底，逻辑同主路径。理论上 #1 生效后这条路径不会再触发，留作万一被上游升级覆盖时不至于 abort 的最后防线。

3. **[`third_party/aria2/src/LibsslTLSContext.cc`](third_party/aria2/src/LibsslTLSContext.cc) — null guard**：原 aria2 在 `addSystemTrustedCACerts` / `addCredentialFile` / `addTrustedCACertFile` / 析构里裸 deref `sslCtx_`，一旦 `SSL_CTX_new()` 因 RAND 失败返回 NULL 必 SIGSEGV。新增空指针检查：sslCtx_ 为 NULL 时早返回 false（带 `__android_log_print` 警告 + `A2_LOG_ERROR`），让 aria2 daemon 至少能起来跑明文下载，TLS 静默降级而非整个进程挂掉。

4. **[`packages/aria2_native/src/CMakeLists.txt`](packages/aria2_native/src/CMakeLists.txt)**：Android 链接列表新增 `log`，让 `__android_log_print` 能解析到 Bionic 的 `liblog.so`。

补丁仅触达 aria2 子模块三份文件（`Platform.cc` / `SimpleRandomizer.cc` / `LibsslTLSContext.cc`），**不需要** patch OpenSSL 本身、不改 `libcrypto.a` 构建脚本。其他平台 / TLS 后端的代码路径全部用 `#if defined(__ANDROID__)` 排除：macOS / iOS 走 `SecRandomCopyBytes`，Windows 走 `CryptGenRandom`，桌面 Linux 走 OpenSSL 默认 DRBG，全部维持原行为；null guard 在所有平台都跑（修原本就是的 aria2 上游 bug，但不带任何性能开销）。

操作：本仓库已用 `scripts/build_libaria2_android_macos.sh` 重建三 ABI（`armeabi-v7a / arm64-v8a / x86_64`）的 `libaria2.a` 并落到 `packages/aria2_native/prebuilt/android/`，用户拉取后 `flutter build apk` 直接生效。其他平台（macOS / iOS / Linux / Windows）prebuilt 不受影响，无需重建。

**已知遗留**：在受 SECCOMP 拦截的设备上，HTTPS 下载会因 `SSL_CTX_new` 持续返回 NULL 而无法工作（明文 HTTP / BT / Magnet 仍正常）。logcat 有 `I/aria2down: SSL_CTX_new failed: err=... cause=error:12800067:DSO support routines::could not load the shared library` 提示。后续若需要恢复 HTTPS，可考虑：(a) 切换到 GnuTLS 后端，(b) 重新编 OpenSSL 时添加 `no-engine no-dynamic-engine no-module no-deprecated -DOPENSSL_USE_NODELETE` 彻底剔除 DSO 路径，(c) 远程 RPC 模式（依赖外部 aria2c）作为 fallback。

性能影响：`/dev/urandom` 是内核 CSPRNG，单次读 6–48 字节微秒级；本应用大部分场景每个种子任务 < 1 KB 熵消耗，相比 OpenSSL DRBG 的额外重新抽取微不足道。该 hook 仅 `__ANDROID__`，桌面端 / iOS 不会因这次改动产生任何回归。

### 工程（macOS 本机交叉编译 Android libaria2，告别 Docker）

之前为 Android 打包必须先跑 [`scripts/build_libaria2_android.sh`](scripts/build_libaria2_android.sh)，
该脚本基于上游 [`Dockerfile.android`](third_party/aria2/Dockerfile.android) 在 Docker
容器里跑 NDK + OpenSSL + c-ares 等依赖的交叉编译。Docker 工作流问题不少：

- 镜像首次构建 7–15 分钟，且每次升级依赖都要重建；
- macOS 上 Docker Desktop 体积大、占内存，CI runner 上还经常拿不到 daemon；
- 容器内 `make install` 与 host 之间的卷挂载在 macOS 上 IO 严重退化；
- 想临时调依赖版本要改 Dockerfile，rebuild 整个镜像。

但实际上多数 Flutter 开发者本机就已经装了 Android Studio + NDK，完全可以直接
用本机 NDK + clang 交叉编译。新脚本
[`scripts/build_libaria2_android_macos.sh`](scripts/build_libaria2_android_macos.sh)
正是为此而生：

- **自动探测 NDK**：`$ANDROID_NDK_HOME` / `$ANDROID_NDK_ROOT` / `$NDK_HOME` →
  `$ANDROID_HOME/ndk/<最新>` → `$ANDROID_SDK_ROOT/ndk/<最新>` →
  `~/Library/Android/sdk/ndk/<最新>` 依次回退；同时支持 Apple Silicon
  (`darwin-arm64`) / Intel (`darwin-x86_64`) prebuilt toolchain。
- **依赖即时编译**：脚本会下载并缓存 OpenSSL 3.0.x LTS、zlib 1.3.1、
  expat 2.5.0、c-ares 1.21.0，分别针对每个 ABI 独立交叉编译为静态库，
  落在 `build/libaria2/android-native/install-<abi>/` 中。源码 tarball 缓存到
  `cache/` 子目录，重复运行只走 incremental（依赖已建则跳过）。sqlite3 默认
  关闭（aria2 仅用其读 Firefox `cookies.sqlite`，移动端无意义，且 `sqlite.org`
  在 CN-mainland 网络下经常超时）；需要时用 `ENABLE_SQLITE3=1` 显式打开。
- **三 ABI 覆盖**：默认 `armeabi-v7a arm64-v8a x86_64`，可在命令行单独指定；
  `ANDROID_API` 环境变量调整最低 SDK（默认 21，跟 `flutter.minSdkVersion` 对齐）。
- **复用既有 prebuilt 结构**：产物按
  `packages/aria2_native/prebuilt/android/<abi>/{libaria2.a, include/, deps/*.a}`
  落盘。
- **修复 [packages/aria2_native/src/CMakeLists.txt](packages/aria2_native/src/CMakeLists.txt)
  的 Android 链接错误**：之前对 `UNIX AND NOT APPLE` 分支统一 `target_link_libraries
  pthread dl m`，但 Android Bionic 把 `libpthread` / `librt` 都合并进 `libc`，
  `ld.lld: error: unable to find library -lpthread` 会让所有用了 aria2_native 的 APK
  打不出。新增 `if(ANDROID)` 分支只链 `dl m`，桌面 Linux 保持原样。
- **修复 [android/app/build.gradle.kts](android/app/build.gradle.kts) 的 NDK / minSdk
  配置**：Flutter 3.32 默认 `flutter.ndkVersion = 26.3.11579264`，但多个插件
  （`aria2_native` / `app_links` / `file_picker` / …）已经要求 NDK 27.0.12077973，
  默认配置下整个 build 会被 Gradle 用 NDK 26 强行兜底导致警告 + 链接路径错位。
  显式 `ndkVersion = "27.0.12077973"` 与 macOS 编译脚本对齐。另外
  aria2 在 NDK 27 32-bit ARM 上需要 LFS `fseeko/ftello`（仅 API ≥ 24 暴露），
  把 `minSdk` 改成 `maxOf(24, flutter.minSdkVersion)`。
- **zlib `-fPIC` 修正**：脚本里 zlib 的 `./configure --static` 默认不开 PIC，
  导致后续 aria2_native shared library 链接时报
  `R_AARCH64_ADR_PREL_PG_HI21 cannot be used against symbol 'z_errmsg'`。显式
  `CFLAGS="-O2 -fPIC"` 注入。OpenSSL（`no-shared` 自动 PIC）/ expat / c-ares
  原本就已带 `-fPIC`，未改动。
- **aria2 configure 选项与 Docker 版保持一致**：`--enable-libaria2 --enable-static
  --disable-shared --with-openssl --with-libexpat --with-libcares --with-libz
  --without-sqlite3 --with-libssh2=no`；`libssh2` / `libuv` / `libxml2` 在桌面端
  也是关的，保持三平台口径统一。
- **文档同步**：[docs/BUILD_LIBARIA2.md](docs/BUILD_LIBARIA2.md) Android 章节改写为
  「推荐：macOS 本机交叉编译（无 Docker）」+「备选：Docker」两小节，列出依赖版本表，
  并保留旧脚本作为「没装 NDK 时的兜底」。
- **未触及**：Docker 版脚本 / `Dockerfile.android` / CI workflow / FFI binding 一概
  未动，老的 CI 流程仍然有效，可以无缝切换。

典型耗时（M1 Pro / 32G）：首次冷启动 3 ABI 全编 ≈ 7 分钟；保留 install 目录后只
跑 `make` 增量 ≈ 90 秒 / ABI。

### 修改（设置页改即生效，移除显式「保存」按钮）

之前所有设置变更都缓存在 `_SettingsForm` 的本地状态里，必须点底部 / 桌面右侧的 **保存** 按钮才会写入 SharedPreferences + 重启 aria2 / 重连远程 RPC。换语言、改主题、切托盘行为这种「应该是立刻反馈」的小操作要先点击三次（改 → 保存 → 看效果），心智成本高；离开设置页忘了点保存改动就丢，新用户反复踩坑。

本次把设置页改成「改即生效」模型——任何控件触发都直接持久化并实时应用，不再有专门的保存动作：

- **新建 [`AppSettingsNotifier`](lib/providers/app_settings_provider.dart)**：把原 `FutureProvider<AppSettings>` 改成 `AsyncNotifierProvider`，对外暴露 `set(AppSettings)` / `mutate((s) => s.copyWith(...))` / `resetToDefaults()`。先 `state = AsyncData(next)` 让 UI 立刻看到新值（主题、语言、托盘 binding 等订阅者瞬间响应），再异步写盘；磁盘写入失败时回滚到旧值并把 `AsyncError` 暴露给监听方，保证用户能感知（而不是默默把改动吞掉）。命名上避开父类 `AsyncNotifier.update` 的固定签名（`Future<T> Function(T) → onError`），用 `set` 表达「整体替换」语义。
- **[`aria2DaemonProvider`](lib/providers/aria2_daemon_provider.dart) 改用 `selectAsync` 只盯连接相关字段**：以前 daemon 依赖整份 `AppSettings`，theme / locale / 种子色变了也会重启 aria2——在新的「改即生效」模型下这会导致用户每按一下主题段就把下载中断一次。现在抽出一个 `_DaemonInputs` Dart record（受当前 `ConnectionMode` 影响动态裁剪：remote 模式只放 endpoint / secret，local 模式只放下载目录 + 4 个调优参数）作为 selector 返回值，Riverpod 用 record 的值相等判定，只有真正影响 daemon 行为的字段变了才重建 daemon。
- **[`SettingsPage`](lib/features/settings/settings_page.dart) 全面重写**：
  - 移除 `key: ValueKey(s)`——之前每次设置变化都会让整个表单 unmount / remount，焦点 / 光标 / 滚动位置全丢；现在表单常驻，靠 provider watch 自然响应。
  - 移除 `_save()` 方法、桌面端 `FilledButton` 与移动端 `bottomNavigationBar` 里的「保存」按钮。
  - 开关 / SegmentedButton / Dropdown / 主题色挑选 / 下载目录 picker / `askDownloadDirEachTime` switch 等「即时型」交互直接调 `notifier.mutate((s) => s.copyWith(...))` 落盘。下载目录在落盘后还会顺手 `changeGlobalOption({'dir': ...})` 推给正在跑的 daemon（沿用旧 `_save` 行为）。
  - 文本框（远程端点 / Secret / 并发数 / 单 server 连接数 / 上下行限速）走 **失焦提交** 模式：每个 `TextField` 绑一个 `FocusNode`，监听器统一调 `_commitTextFields()`——这样在用户按一个键就重启 aria2 / 重连 RPC 之间留出缓冲，避免「输入 192.168.1.100:6800 重连了 17 次」的灾难。同时支持 `onSubmitted`（按 Enter）提交，键盘党不必依赖失焦事件。
  - 「应用到运行中」按钮（`_applyRuntimeLimits`）保留——它是「即时把当前限速 RPC 推给正在跑的 aria2」的快捷方式，不依赖 daemon 重启。该按钮现在先 `_commitTextFields()` 再 RPC，保证盘上 / 内存 / aria2 三处状态一致。
  - 导入 / 重置走 `notifier.set(imported)` / `notifier.resetToDefaults()` 后再同步本地文本控制器，让用户即刻看到字段被重写为新值（同时也避免抢正在编辑的字段焦点：`_syncControllersFrom` 仅在 `FocusNode.hasFocus == false` 时改写控件 text）。
- **[`DaemonErrorScreen.daemonErrorSwitchRemote`](lib/app/daemon_error_screen.dart) 也迁移到 notifier**：之前是 `SettingsRepository.save(...) + ref.invalidate(appSettingsProvider) + ref.invalidate(aria2DaemonProvider)` 三步；现在一行 `notifier.mutate((s) => s.copyWith(connectionMode: remote))` 完成，daemon provider 通过 selectAsync 自动重建，不需要手动 invalidate。
- **l10n**：[`settingsImportApplied`](lib/l10n/app_en.arb#L314) 文案从「Settings loaded. Tap Save to persist, or edit first.」改为「Settings imported and applied.」，中文从「已载入设置，请点击「保存」或继续编辑后保存。」改为「已导入并即时应用设置。」；其它语言 fallback 到英文新文案。
- **测试**（[`test/widget_test.dart`](test/widget_test.dart)）：
  - 新增「不再渲染独立的「保存」按钮」widget 测试，回归保护。
  - 新增「切换主题偏好后立刻写盘」端到端测试：用 `ProviderContainer` 旁路 widget tree 拿 notifier，点 `深色` 段后断言 ① provider 内存状态变 `dark`、② `SettingsRepository.load()` 从 SharedPreferences 读回来也是 `dark`——证明同一次点击同时驱动了 UI 与磁盘。
- **跨场景一致性**：原本会显式 `ref.invalidate(appSettingsProvider) + ref.invalidate(aria2DaemonProvider)` 的两处调用点（`SettingsPage._confirmResetSettings` / `SettingsPage._confirmShutdownAria2`）保留对 daemon 的显式 invalidate（重置 / shutdown 后用户预期 daemon 重建），其余路径不再需要——`AsyncNotifier` + `selectAsync` 让 daemon 的重启严格对应到「连接关键字段真的变了」。
- **未触及**：`SettingsRepository` 的存储格式 / 字段 / 历史遗留键清理逻辑全部保持不变，所以本变更不影响升级路径——已有用户的 SharedPreferences 内容直接被 `SettingsRepository.load()` 读出来塞进 notifier 即可。

### 修复（macOS：Finder 双击 `.torrent` / `.metalink` 不触发下载）

之前在 macOS Finder 里双击 `.torrent` / `.metalink`，或用「打开方式 → aria2down」打开种子文件，应用确实会被唤起，但**既不会进入新建任务页，也不会弹种子文件选择对话框**——什么都不发生。

根因：[app_links](https://pub.dev/packages/app_links) 的 macOS 实现只通过 `NSAppleEventManager` 订阅了自定义 URL Scheme（`kAEGetURL`，对应 `aria2down://` / `magnet:` 这一类），**没有实现 `application(_:open urls:)` / `handleOpenURLs:`**，所以 Finder 打开文件投递的 `kAEOpenDocuments` Apple Event → `application(_:open urls:)` 回调链路上，`file://` URL 被静默丢弃，Dart 侧 [`IncomingLinkListener`](lib/app/incoming_link_listener.dart) 永远收不到。

修复：

- **[macos/Runner/AppDelegate.swift](macos/Runner/AppDelegate.swift)**：重写 `application(_:open urls:)`，把传入的所有 `URL`（含 `file://`）通过 `import app_links` + `AppLinks.shared.handleLink(...)` 注入到 app_links 的统一管道。冷启动场景下即便 Flutter 还没起来，URL 也会被 `AppLinks` 的单例缓存到 `initialLink`，待 Dart 侧 `getInitialLink()` 时取出；热启动场景下直接通过 `eventSink` 推到 `uriLinkStream`。**对自定义 URL Scheme 无副作用**——`aria2down://` / `magnet:` 仍走 `kAEGetURL` Apple Event 优先派发，不进 `application(_:open urls:)`。
- **[lib/core/incoming_link.dart](lib/core/incoming_link.dart)**：收紧 `parseIncomingLink` 对 `file://` URI 的兜底逻辑——只接受 `.torrent` / `.metalink` / `.meta4` / `.metalink4`；未知扩展名（含无扩展名）回退 `IncomingUnknown`，避免把任意桌面文件盲投到 `aria2.addTorrent`。Android `content://` SAF 投递常见没扩展名的情况仍保持「按 torrent 兜底」行为。
- **[lib/app/incoming_link_listener.dart](lib/app/incoming_link_listener.dart)**：bytes 读取失败时增加 debug 日志，方便排查（沙盒权限被回收 / 文件不在 / 损坏等场景）。
- **测试**：[`test/core/incoming_link_test.dart`](test/core/incoming_link_test.dart) 新增两条用例覆盖 `file://` 未知扩展名 / 无扩展名都回退到 `IncomingUnknown`。

> **平台范围说明**：本次只动了 macOS native 入口。Linux `.desktop` 关联走 GApplication `HANDLES_OPEN`，由 `app_links_linux` 自己处理；Windows MSIX `file_extension` 把文件路径作为 `argv[1]` 透传给 `app_links` 的 `GetLink()` 解析。这两个平台是否同样存在「双击文件不下载」的回归仍待用户场景验证（Windows path 不带 URL scheme，正则匹配会落空，理论上同样需要在 `windows/runner/main.cpp` 里把 path 转 `file:///` 后再投递——本次先不动，等 issue 反馈再追）。

### 工程（GitHub Actions 全平台打包与 Tag-Release 流程完善）

之前 CI 只验证 build 能过 + 上传 bundle 目录；本次升级为全平台**单文件可分发安装包**直接 attach 到 Actions artifact + GitHub Release，覆盖 Windows MSIX、macOS DMG、Linux tar.gz、Android per-ABI APK。

- **[`flutter.yml`](.github/workflows/flutter.yml) (push/PR CI)**：
  - **Windows**：build 之后追加 `Compress-Archive` 产 ZIP + `dart run msix:create` 产 MSIX（用现有 [`pubspec.yaml`](pubspec.yaml) 的 `msix_config:`：display_name / publisher / identity / capabilities=internetClient / protocol_activation=aria2down,magnet / file_extension=.torrent,.metalink,.meta4）。MSIX 步骤 `continue-on-error: true` 避免 PR 被偶尔的 msix 工具问题阻塞；ZIP 始终上传作为兜底（解压即用，不需要 Sideload）。
  - **macOS**：build 之后追加 `hdiutil create -format UDZO` 产 DMG（unsigned，用户首次打开需要在系统设置里允许；release 流程后续接入 Apple Notarization）。
  - **Linux**：build 之后追加 `tar -czf` 把 release bundle 打包成 tar.gz。
  - **Android**：增加 `actions/setup-java@v4` (temurin 17)，同时跑 `flutter build apk --split-per-abi`（arm64-v8a / armeabi-v7a / x86_64 各 ~30MB）+ universal APK 兜底，命名 `Aria2Down-android-<abi>-<ver>.apk`。
  - 所有 artifact 命名带 pubspec 版本号（如 `Aria2Down-windows-x64-0.1.0-msix`），方便维护者直接从 Actions 下载验证。
- **[`release.yml`](.github/workflows/release.yml) (tag-triggered release)**：
  - 触发方式从 `workflow_dispatch` 改为 `push: tags: ['v*']`（推 tag 自动产 release）+ 保留 `workflow_dispatch` 兜底（接受 `tag` 参数或留空走 dry-run）。
  - `resolve-tag` job 解析 tag → version；下游 4 个平台 job (linux / macos / windows / android) 并行打包；最后 `publish` job 下载所有 `release-*` artifact + 用 `softprops/action-gh-release@v2` 创建 / 更新 GitHub Release，自动 attach DMG + MSIX + ZIP + tar.gz + APKs。
  - 单平台 build 失败用 `continue-on-error: true` 解耦——其它平台仍按计划上传（之前是瀑布失败，一个 OS 挂全 release 缺资产）。
  - Release notes 优先从 [`scripts/print_release_notes.sh`](scripts/print_release_notes.sh) 提取 [Unreleased] 段落；脚本不可用时落到简短通用文案。
  - tag 含 `-`（如 `v0.2.0-rc1`）自动标记为 prerelease。
  - `permissions: contents: write` 让 GITHUB_TOKEN 能创建 / 更新 release。
- **`flutter.yml` 旧入口保留**：每次 push/PR 仍会跑 analyze + format + test（不变），所有桌面/移动平台都产出 artifact 方便手动下载验收。
- **行为细节**：
  - **MSIX 未签名**：用户首次安装需要先启用 Windows Sideload (`Settings → Privacy & Security → For Developers → Developer Mode`) 或自行 `signtool sign`。这是 CI 上的合理默认；生产签名应交给 release 维护者本地用 `signtool` + 证书完成（CI secret 暴露签名证书风险高）。
  - **DMG 未 Notarize**：macOS Gatekeeper 首次打开会拦截，用户需在系统设置里允许。
  - **iOS smoke 保留**：`flutter build ios --release --no-codesign` 只验证编译，IPA / TestFlight 上传仍走本机签名流程（CI 上跑需要 Apple Developer 证书 + provisioning profile，超出本次范围）。
- **验证**：本地 `flutter analyze` 通过；3 个 workflow YAML 用 ruby YAML 解析器 round-trip 验证合法；push 后 GitHub Actions 实际跑全平台 → artifact 下载验证 MSIX / DMG / tar.gz / APK 都能产出。

### 修改（统一应用显示名为 `Aria2Down`）

之前各平台用户可见的应用名是 `aria2down`（Android）/ `Aria2down`（iOS）/ `aria2down`（macOS / Windows / Linux），大小写不一致。本次把**用户可见的应用名**全部统一为大写驼峰 `Aria2Down`；**技术标识符**（binary filename / package id / Dart package name / URL scheme / MethodChannel name / 文件系统状态目录）刻意保持原 lowercase，避免破坏升级路径与平台命名约定。

- **Android**：[`AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml) 全部 9 处 `android:label="aria2down"` → `Aria2Down`（应用图标下方 launcher 标签 + 所有 intent-filter 的可见 label）。`applicationId / package` 与 `cloud.iothub.aria2down` MethodChannel 名不动。
- **iOS**：[`ios/Runner/Info.plist`](ios/Runner/Info.plist) `CFBundleDisplayName: Aria2down` → `Aria2Down`；`CFBundleName: aria2down` → `Aria2Down`；`NSLocalNetworkUsageDescription` 中的应用名同步大写。URL scheme `aria2down://` 与 bundle id `cloud.iothub.aria2down` 不动。
- **macOS**：[`AppInfo.xcconfig`](macos/Runner/Configs/AppInfo.xcconfig) `PRODUCT_NAME = aria2down` → `Aria2Down`。Dock / Finder / 关于本应用窗口显示的全是 `Aria2Down`；`.app` 包名跟随变为 `Aria2Down.app`。`PRODUCT_BUNDLE_IDENTIFIER = cloud.iothub.aria2down` 不动（entitlements / TLS app group / launch services 注册都靠这个稳定 id）。
- **Windows**：[`Runner.rc`](windows/runner/Runner.rc) `FileDescription` / `ProductName` 改为 `Aria2Down`（资源管理器 → 文件属性 → 详情 + PE 信息工具显示）；`InternalName` / `OriginalFilename` 保持 `aria2down` / `aria2down.exe`（与 `BINARY_NAME = aria2down` 对齐，不破坏 installer / 关联注册脚本）。[`main.cpp`](windows/runner/main.cpp) 初始 `window.Create(L"Aria2Down", ...)` 让 Flutter 接管前的闪屏标题就是大写驼峰；`SendAppLinkToInstance(L"aria2down")` 是单实例检测的 mutex 名，保持小写避免老进程跨升级找不到匹配。
- **Linux**：[`my_application.cc`](linux/runner/my_application.cc) `gtk_header_bar_set_title` + `gtk_window_set_title` 都改 `Aria2Down`；[`aria2down.desktop`](linux/aria2down.desktop) 的 `Name=` 字段同步。`BINARY_NAME = aria2down` / `Exec=aria2down %U` / `TryExec=aria2down` / `Icon=aria2down` 不动（.deb / AppImage 命名约定都是 lowercase）。
- **Flutter 层**：[`app.dart`](lib/app/app.dart) 三个 `MaterialApp.title: 'Aria2Down'`（影响桌面端任务栏 / Android task switcher 卡片标题）+ `_DaemonLoadingScreen` 启动闪屏中的 `'Aria2Down'` 字面量。
- **l10n（自动同步到 13 种语言）**：[`app_en.arb`](lib/l10n/app_en.arb) / [`app_zh.arb`](lib/l10n/app_zh.arb) 中包含应用名的 7 个 key 全部改大写驼峰：`appTitle` / `aboutTitle` / `welcomeRemoteTitle` / `keepAliveTitle` / `trayToolTip` / `trayToolTipStats` / `trayToolTipOffline` / `launchAtStartupDesc`。`flutter gen-l10n` 自动同步到全部 13 个 `app_localizations_<locale>.dart`（未翻译 locale fallback 到英文模板，里面已经是大写）。
- **保留的技术标识符**（user-invisible）：
  - `package:aria2down/...` Dart import 路径 / `name: aria2down` pubspec —— Dart package 名必须 lowercase + underscore
  - `kAriaScheme = 'aria2down'` + `aria2down://` URL scheme —— 浏览器与系统已注册的 deep link scheme，改动会让 v0.x 安装的设备失去现有快捷方式
  - `MethodChannel('cloud.iothub.aria2down/keep_alive')` —— Android native 端硬编码的 channel id
  - `Directory(p.join(base.path, 'aria2down'))` 状态目录 —— 改名后老用户的 aria2.session / 历史 JSON / 日志全找不到
- **测试**：所有 155 个用例（含 13 种 locale round-trip + 主题色 + 历史删除 + GID hex 等）继续通过。`flutter analyze` 无 issue；`dart format` 通过。

### 新增（10 种主流国际化语言支持：日 / 韩 / 繁中 / 西 / 法 / 德 / 俄 / 葡 / 阿 / 越）

之前应用只支持英文与简体中文。本次新增 10 种主流国际化语言，覆盖东亚 / 欧洲 / 中东 / 东南亚四个主要语言区：

| 语言 | 代码 | 备注 |
|---|---|---|
| 日本語 | `ja` | |
| 한국어 | `ko` | |
| 繁體中文 | `zh_TW` | Flutter 用 `Locale('zh', 'TW')` 双段匹配 |
| Español | `es` | |
| Français | `fr` | |
| Deutsch | `de` | |
| Русский | `ru` | |
| Português | `pt` | |
| العربية | `ar` | **RTL** 语言，Flutter 自动从 Locale 推导文字方向 |
| Tiếng Việt | `vi` | |

- **[`AppLocalePreference`](lib/data/app_settings.dart) 增加 10 个 enum 值**：`zhTw / ja / ko / es / fr / de / ru / pt / ar / vi`。`localeOrNull` 在 switch 表里逐一映射，繁体中文走 `Locale('zh', 'TW')` 双段。Flutter `LocalizationsDelegate.isSupported` 会做 languageCode + countryCode 匹配。
- **10 个新 `.arb` 文件**：[`lib/l10n/app_<locale>.arb`](lib/l10n/) 每个翻译约 41 个高频核心 key——导航 (`navTasks / navAdd / navSettings`)、5 个 Tab (`tabActive / tabWaiting / tabCompleted / tabStopped / tabHistory`)、4 个状态 (`statusPaused / statusComplete / statusError / statusRemoved`)、5 个空状态、操作按钮 (`addButton / pasteFromClipboard / pasteAndAdd / pickTorrent / pickMetalink / refreshTasks / save / retry / delete / openFolder / dialogCancel / dialogConfirm`)、设置主标题 (`appearance / theme / themeSystem / themeLight / themeDark / language / langSystem / settingsConnection / connectionLocal / connectionRemote`)。未翻译的 key 会**自动 fallback 到模板英文**（Flutter `gen-l10n` 行为）——意味着 UI 大部分文字是本地化的，少量长说明仍走英文，方便后续贡献者按需补全。
- **新增 11 个语言 label key**（中英 template）：`langChineseSimplified / langChineseTraditional / langJapanese / langKorean / langSpanish / langFrench / langGerman / langRussian / langPortuguese / langArabic / langVietnamese`。各语言名按本地命名（"日本語" 而非 "Japanese"），让用户在不切换语言之前就能识别选项；删除老的 `langChinese`（被 `langChineseSimplified` 取代）。
- **[SettingsPage](lib/features/settings/settings_page.dart) 语言选择从 SegmentedButton 改 `DropdownButtonFormField`**：13 个语言水平 SegmentedButton 装不下，下拉框排版更合理；保留「跟随系统」在顶部分组。
- **RTL 自动适配**：阿拉伯语 `ar` Flutter 框架会从 `Locale('ar')` 自动推导 `TextDirection.rtl`，AppBar、抽屉、列表等控件都会按 RTL 镜像，无需额外代码。
- **测试**：
  - [`test/data/app_locale_preference_test.dart`](test/data/app_locale_preference_test.dart) **15 个用例**：1 个守护 `localeOrNull` 全覆盖（防御性 length check 保证未来新增 enum 值时漏改测试会立即报错）+ 13 个 SettingsExport round-trip（system / en / zh / 新增 10 种各 1 个）+ 1 个 system → null。
  - 全套 `flutter test` 155 通过、1 个无关 skip。
- **CI/分析**：`flutter analyze` 无 issue；`dart format` 通过。`flutter gen-l10n` 报「`vi/zh_TW` 等 297 untranslated message(s)」是预警（Flutter 内置 fallback 到 template 行为），不影响构建。
- **后续完善**：贡献者可以单独翻译某种语言的完整 arb（覆盖剩余 ~280 个 key 比如错误提示、设置长说明等），无需修改路由 / enum / UI 代码。

### 新增（主题色设置：8 个预设色板 + 自定义十六进制）

之前应用主题只有「跟随系统 / 浅色 / 深色」三选一，主色固定为品牌默认蓝 `#1565C0`。这次给用户开放完整的种子色控制——Material 3 的 `ColorScheme.fromSeed` 会以该色为基础推导整套 light / dark 调色板，所有 Card / 进度条 / FAB / 选中态等都会跟着变。

- **[`buildAria2downTheme`](lib/app/theme.dart) 加 `seedColor` 参数**：默认导出 `kDefaultSeedColor = Color(0xFF1565C0)`（之前内联在代码里的"品牌蓝"）；不传参数 = 用品牌默认。[`app.dart`](lib/app/app.dart) 在 `Aria2downApp.build` 中把 `settings.seedColorArgb` 一次解析成 `Color?`，三个 MaterialApp 分支（daemon loading / error / data）共用。
- **[`AppSettings.seedColorArgb`](lib/data/app_settings.dart) (`int?`)**：`null` = 跟随品牌默认。持久化为 ARGB int 而非 hex 字符串，避免 SharedPreferences / JSON 中出现大小写差异和 `#` 前缀解析歧义。`copyWith` 新增 `clearSeedColor` flag 让设置页能"还原默认"。
- **[`SettingsRepository`](lib/data/settings_repository.dart)**：新增 SharedPreferences key `settings.theme_seed_color_argb`，复用现有 `_setIntOrRemove`；`resetToDefaults` 同步把该 key 列入清单。
- **[`SettingsExport`](lib/data/settings_export.dart)**：JSON 中新增 `seedColorArgb` 字段。`_intOrNull` 兼容 `int` / `num` / `String` 三种形态——老 export 可能直接存 int，手编 JSON 可能存字符串，浮点形式（`4.28e9`）也兼容；非法输入静默退化到 `null` 不破坏整次导入。
- **[SettingsPage 主题色选区](lib/features/settings/settings_page.dart)**：紧跟「主题模式」SegmentedButton 之后，新增 [`_SeedColorPicker`](lib/features/settings/settings_page.dart) 圆点网格：第 1 个是「默认」（refresh 图标）、中间 8 个手挑的种子色（红 / 粉 / 紫 / 品牌蓝 / 青绿 / 森林绿 / 橄榄黄 / 暖橙，按色相环排）、最后一个是「自定义...」（colorize 图标）弹对话框收 `#RRGGBB` / `#AARRGGBB`。选中态用边框圈 + 中心 ✓ 双重高亮；自定义对话框带 `FilteringTextInputFormatter` 仅允许 hex 字符 + 输入校验。
- **l10n**：新增 `themeSeedColor` / `themeSeedColorBody` / `themeSeedColorDefault` / `themeSeedColorCustomTitle` / `themeSeedColorCustomBody` / `themeSeedColorCustomInvalid` / `dialogConfirm` 共 7 个 key（中英）。
- **测试**：
  - [`test/app/theme_seed_color_test.dart`](test/app/theme_seed_color_test.dart) 新增 3 个用例覆盖「不传 seed 等价 kDefaultSeedColor」「不同 seed 产出不同 primary」「同 seed light/dark 各自适配亮度」。
  - [`test/data/settings_export_test.dart`](test/data/settings_export_test.dart) 新增 3 个用例覆盖 seedColorArgb round-trip / int|num|String 三种形态兼容 / 无效字符串退化到 null。
- **验证**：`flutter analyze` 无 issue；`flutter test` 全 140 通过、1 无关 skip；`dart format` 通过。

### 重大变更（ADR-010：移除 aria2c 子进程引擎）

ADR-007 把内嵌 libaria2 设为默认后，本次彻底移除作为兜底的 aria2c 子进程引擎。本机模式现在唯一选项是 `LibraryDaemon`（FFI 内嵌 libaria2），外部 aria2c 改用「远程 RPC」连接。详细决策见 [docs/ARCHITECTURE.md ADR-010](docs/ARCHITECTURE.md#adr-010移除-aria2c-子进程引擎)。

- **删除的代码**：[`lib/aria2/daemon/local_daemon.dart`](lib/aria2/daemon/local_daemon.dart)、`lib/aria2/daemon/local_daemon_paths.dart`、`lib/aria2/binary/binary_resolver.dart`、`lib/aria2/binary/android_binary_extractor.dart`、`lib/aria2/config/aria2_config_builder.dart`、`lib/core/local_rpc_credentials.dart`、`lib/core/add_uri_via_local_rpc.dart`、`bin/native_messaging_host.dart`、`bin/rpc_add_uri.dart`、`bin/cli_demo.dart`；[`Aria2BinaryNotFoundException`](lib/aria2/client/aria2_exceptions.dart) 异常类型；`ActiveEngine.subprocess` 枚举；`platform_hints.supportsSubprocessLocalEngine`。
- **删除的设置字段**：[`AppSettings.localEngine`](lib/data/app_settings.dart) / `fallbackToSubprocess` / `aria2BinaryPath` 与对应 SharedPreferences key（`settings.local_engine` / `settings.fallback_to_subprocess` / `settings.aria2_binary_path`）。`settings_export.dart` 静默忽略历史 JSON 中的这些字段以保留旧备份的可导入性；`SettingsRepository.save()` 主动 `remove` 老 key 完成迁移。
- **SettingsPage UI**：删除引擎二选一 SegmentedButton、aria2c 路径输入框、`fallbackToSubprocess` switch。`ConnectionMode.local` 下只展示「内嵌库（libaria2）」说明。「复制 RPC 配置给浏览器扩展」改为仅在远程模式下露出，直接用用户填的 endpoint + secret 生成扩展 JSON（不再依赖 `rpc.secret` 文件）。
- **删除的 assets / scripts**：`assets/android/`（含 README + binary placeholder）、`scripts/build_aria2.sh`、`scripts/build_android_aria2_docker.sh`、`scripts/build_bundle_with_aria2.sh`、`scripts/stage_android_aria2.sh`、`scripts/stage_aria2c.sh`、`scripts/stage_windows_aria2.ps1`、`scripts/install_native_messaging_host.sh`、`extensions/native-messaging/` 整目录。`pubspec.yaml` 同步剔除 `assets/android/README.md` 引用。
- **CI**：[`.github/workflows/build-aria2.yml`](.github/workflows/build-aria2.yml) 中所有 `*-aria2c` job 删除并改名为「Build libaria2」；[`.github/workflows/flutter.yml`](.github/workflows/flutter.yml)、[`.github/workflows/release.yml`](.github/workflows/release.yml) 不再下载 / 编译 / 拷贝 `aria2c` 到产物 bundle，改为只编 libaria2 prebuilt（编不出来时 daemon 直接抛错引导改用远程 RPC）。
- **i18n**：删除 11 个 key（中英）：`engineSubprocess` / `engineSubprocessDesc` / `engineSubprocessShort` / `engineFallbackToSubprocess(Desc)` / `engineUnavailableBanner` / `engineInitFailed` / `aria2BinaryPath` / `aria2BinaryHint` / `restartAria2Hint` / `daemonErrorBinaryNotFound`；`engineLibraryDesc` / `copyRpcConfigSubtitle` / `daemonErrorWebLocal` 重写以反映新语义。
- **删除的测试**：`test/aria2/binary_resolver_test.dart`、`test/aria2/aria2_config_builder_test.dart`、`test/integration/aria2_e2e_subprocess_test.dart`、`test/widget/settings_engine_select_test.dart`、`test/core/local_rpc_credentials_test.dart`。
- **docs**：[`AGENTS.md`](AGENTS.md) 删去 `LocalDaemon` 与 native messaging 描述；[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) 总览图 / 模块树 / 启动时序 / 跨平台差异 / ADR 表全部同步；新增 ADR-010 详细记录；[`docs/BUILD_ARIA2.md`](docs/BUILD_ARIA2.md) 改为弃用 banner 指向 `BUILD_LIBARIA2.md`。
- **替代路径**：需要在外部运行 aria2c（远程 NAS、Docker 容器内的下载机、自定义参数的 aria2c）的用户改用「远程 RPC」连接模式，输入 endpoint + secret 即可，体验与之前的子进程模式完全等价。
- **prebuilt 不可用时**：`LibraryDaemon.create` 内部检测 prebuilt libaria2 缺失会直接抛 `Aria2NativeUnavailableException`；设置页有「库引擎运行在功能受限模式」红条引导重编 prebuilt，daemon 错误屏明确提示改用远程 RPC。
- **验证**：`flutter analyze` 仅 2 个无关 transitive dependency info；`flutter test` 全 134 通过、1 个无关 skip；`dart format` 通过。

### 新增（任务列表拆出独立「已完成」Tab）

用户反馈："已完成的下载塞在「已停止」Tab 里跟一堆 .torrent 解析失败、加错链接的报错混在一起，找上次下完的电影要往下翻一长串失败记录。"

- **TabController 长度 4→5**：[`task_list_page.dart`](lib/features/tasks/task_list_page.dart) 现在的 Tab 顺序为 **active / waiting / completed (new) / stopped / history**，符合时间流向（进行中 → 等待 → 已完成 → 失败或被取消 → 本地历史）。
- **共享数据源、UI 分流**：`_stopped` 字段仍是 aria2 `tellStopped` 的原始返回（complete + error + removed 混合），通过 [`task_list_split.dart`](lib/core/task_list_split.dart) 的两个互补 helper 拆成两个视图——`_completedView`（`status == 'complete'`）与 `_stoppedView`（其余 status，包含未来未知 status 以避免任务隐身）。paged 加载（`tellStopped` num 翻倍）、`TaskHistoryRecorder.onStoppedList` 历史落库、batch action（清空 stopped 结果 / 强制移除 stopped 任务）仍走完整 `_stopped`，没有额外 RPC。
- **底部「加载更多」footer 在 completed / stopped 两个 Tab 都展示**：两个 Tab 共享同一份 paged 数据，只挂在 stopped 会让用户在 completed Tab 误以为已经看到了全部。
- **AppBar 与 PopupMenu 索引漂移**：History 专属的「清空全部历史」红按钮 + 「导出 / 导入历史」菜单项原本绑 `_tabs.index == 3`，拆 Tab 后漂到 `index == 4`——避免在新插入的 Completed Tab 误触发本地历史清空（误触发会一次性删光所有持久化记录，不可恢复）。
- **l10n**：新增 `tabCompleted` / `emptyCompleted` 两组 key（中英）。
- **测试**：[`test/core/task_list_split_test.dart`](test/core/task_list_split_test.dart) 新增 6 个用例覆盖 `filterCompletedTasks` / `filterStoppedTasks` 的常规路径 + 空 status / 缺字段 / 未知 status / 两路互补不漏不重。`flutter analyze` 无 issue；`flutter test` 全部 144 通过、1 无关 skip；`dart format` 通过。

### 新增（每次下载都让用户选择保存位置，各平台沙箱权限对齐）

用户反馈："能不能每次开下载都让我选保存位置？iOS/Android 也得能用，别 SAF URI 又把 aria2 搞挂。"

实现按各平台沙箱模型做了差异化处理：

- **AppSettings 新增 `askDownloadDirEachTime`**：[`app_settings.dart`](lib/data/app_settings.dart) / [`settings_repository.dart`](lib/data/settings_repository.dart) / [`settings_export.dart`](lib/data/settings_export.dart) 全链路持久化，默认 `false`（老用户升级后不会突然被弹窗打断）。
- **新增 `lib/core/download_dir_picker.dart`**：跨平台目录选择统一入口 `pickDownloadDirectory(BuildContext, {initialDirectory})`：
  - **桌面（macOS / Win / Linux）**：直接调 [`file_selector.getDirectoryPath`](https://pub.dev/packages/file_selector) 弹原生目录选择器。**macOS sandbox** 已经声明 `com.apple.security.files.user-selected.read-write` + `com.apple.security.files.downloads.read-write`（见 [Release.entitlements](macos/Runner/Release.entitlements)），用户选中的目录与系统 Downloads 都能直接由 aria2 写入，无需额外书签。Win / Linux 无 sandbox 约束。
  - **移动端（Android / iOS）**：**不弹 SAF**——`content://com.android.externalstorage.documents/tree/...` 这种 tree URI 喂给 libaria2 会在文件分配阶段抛错（aria2 不识别 SAF URI）。取而代之弹 `_MobileDownloadDirSheet`，列出**沙箱内可写**候选目录 + 子目录建立 + 自定义路径输入：
    - Android: `getExternalStorageDirectory()`（应用专属外部存储 `/sdcard/Android/data/<pkg>/files`，**卸载时系统会清空**——UI 上明确提示）+ `getApplicationDocumentsDirectory()`
    - iOS: `getApplicationDocumentsDirectory()`（在「文件」App 中可见）+ `getApplicationSupportDirectory()`
- **`resolveDownloadDirForTask` 顶级 helper**：抽出"下次任务最终 `dir` 选项"的优先级解析（`overrideDir`（askEachTime 弹窗 / picker 按钮）> `manualField`（高级选项手填）> `globalDefault`（设置页全局默认））。trim 后空串视为"未设置"继续往下找，让用户在弹窗里点取消或留空都不会"显式覆盖"全局默认。
- **AddTaskPage 改造**：
  - 高级选项新增「下载到（本次任务）」TextField + suffix 文件夹按钮（`_pickDirForThisTask` 调跨平台 picker），仅当前任务生效。
  - 4 个提交入口（URL submit / paste-and-add / .torrent / .metalink / 外部 intent drain pending）统一在 `_buildRpcOptions` 前先 `await _maybeAskDownloadDir()`：用户已经在「本次下载目录」或「全局默认」里给了路径就 skip，否则在 `askDownloadDirEachTime == true` 时弹 picker；picker 取消 → 整次添加中止（而不是 silently 用默认目录）。
  - 三态 sentinel `_AskDirResult.{skip,cancel,pick(path)}` 把"无需询问 / 用户中止 / 用户选了"区分开，避免误用 null 当成"取消"。
- **SettingsPage 改造**：「下载目录」区下方新增 SwitchListTile「每次询问下载目录」，绑定 `_askDownloadDirEachTime` 并参与 `_buildSettings` / 设置导入回写。
- **l10n**：新增 18 个 key（中英）覆盖 AddTask 字段 / 设置 switch / 移动端 BottomSheet 标题 / 候选目录标签 / 子目录提示 / 沙箱卸载警告等。
- **测试**：
  - [`test/core/download_dir_picker_test.dart`](test/core/download_dir_picker_test.dart) 新增 6 个用例覆盖 `resolveDownloadDirForTask` 优先级（overrideDir > manualField > globalDefault）+ trim 空串跳过 + 全 null 返回 null + 返回值保持 trim。
  - [`test/data/settings_export_test.dart`](test/data/settings_export_test.dart) 新增 1 个用例 round-trip `askDownloadDirEachTime` + `downloadDirectoryOverride`；defaults 测试同步断言新字段默认 false。
  - `flutter analyze` 无 issue；`flutter test` 全部 138 通过、1 个无关 skip；`dart format` 通过。

### 新增（下载列表 / 历史 Tab / 任务详情页统一"打开下载位置"入口）

用户反馈："从下载列表能不能直接打开文件位置？长按菜单要找半天，历史 Tab 完全没有这个按钮，详情页也找不到。"

- **现状**：任务列表卡片本来有长按上下文菜单 + 右侧 `Icons.folder_open_outlined`，但历史 Tab 列表项 / 任务详情页 AppBar 都缺。最容易碰到的场景是：从「历史」Tab 看到一条已完成下载，想就近打开下载目录——只能先点开详情页（还得是历史快照模式因为 aria2 早就 purge 了），再返回任务列表才能找到打开位置入口。
- **抽出共享 UI 反馈函数**：[`lib/core/reveal_path.dart`](lib/core/reveal_path.dart) 新增顶级 `revealPathInUiWithFeedback(BuildContext, AppLocalizations, String?)`，把 `_TaskListPageState._openFolder` 里原本耦合的 snackbar 派发 + Web 复制路径 + 移动端 `_showMobilePathSheet` 全部抽出共享。任务列表 / 历史 Tab / 详情页三处调用点共用，行为完全一致：null 路径 → `openFolderFailed` toast；Web → 复制路径 + `openFolderWebCopied` toast；桌面 → 调 `revealPathInFileManager` 失败时 toast；移动端目录场景 → 弹复制路径 BottomSheet（系统文件管理器无 intent 打开本地目录）。
- **历史 Tab 加按钮**：[`task_history_tab.dart`](lib/features/tasks/task_history_tab.dart) 在「重试」按钮左侧插入 `Icons.folder_open_outlined`，条件 `entry.dir != null`（complete / error / removed 三种历史状态都可能保留 dir）。点击时拼 `p.join(entry.dir!, entry.name)` 让文件管理器精确选中文件，文件被移走时 `revealPathInFileManager` 自动回退到 `dirname` 打开目录。
- **任务详情页 AppBar 加按钮**：[`task_detail_page.dart`](lib/features/tasks/task_detail_page.dart) 在 `taskShare` 左侧插入「打开下载位置」IconButton，条件 `resolveRevealPath(_status) != null`。**历史快照模式下同样可用**——`TaskHistoryEntry.toDetailShape` 已经把 `files[0].path` 改成完整路径（见下条），所以 `firstDownloadedPath` 走的是真实文件路径而不是 basename。
- **修复 `toDetailShape` 伪相对路径**：[`task_history_entry.dart`](lib/data/models/task_history_entry.dart) 之前把 `files[0].path = name`（basename），导致历史快照详情页的「打开下载位置」让 macOS 的 `open -R` 拿不到正确路径。现在 `files[0].path = p.join(dir, name)`：dir + name 齐全时拼完整路径；缺 dir 时退回 name（保留向后兼容老历史记录）；缺 name 时退回空串（顶层 `dir` 仍保留，detail page 的 `resolveRevealPath` 会优先文件路径但因为空所以走 dir）。AppBar 标题继续走 `pickTaskName(path)` 的 basename 提取，显示效果不受影响。
- **测试**：[`task_history_entry_test.dart`](test/data/task_history_entry_test.dart) 更新原 `toDetailShape` 用例的 path 断言（`movie.mkv` → `/Downloads/movie.mkv`），并新增 2 个用例覆盖「缺 dir 退回 name」「缺 name 只暴露 dir」两种边界。`flutter analyze` 仅有 2 个上轮残留 info 级 transitive 依赖提示（与本次无关）；`flutter test` 全部 131 通过；`dart format` 通过。
- **体验**：历史 Tab 每条任务现在都有「打开下载位置」按钮，无需再走详情页；任务详情页 AppBar 也支持，包括 aria2 已 purge 走历史快照的场景；任务列表卡片的现有入口不变。

### 修复（macOS prebuilt libaria2 重编：从「功能受限模式」恢复到全能力）

用户反馈："设置页常驻一条『库引擎运行在功能受限模式』红条，缺四项能力（删除已完成任务 / 枚举等待中任务 / 枚举已停止任务 / 任务级扩展字段）。"

- **根因**：[`packages/aria2_native/prebuilt/macos/universal/libaria2.a`](packages/aria2_native/prebuilt/macos/universal/libaria2.a) 是 2026-05-19 编出的旧产物，不带 [`third_party/aria2`](third_party/aria2) 当前子模块里 aria2down 维护的本地补丁（公开 `aria2::removeDownloadResult` / `purgeDownloadResult` / `getReservedDownload` / `getDownloadResults` + `DownloadHandle` 扩展 getter）。`nm libaria2.a` 仅看到 `RequestGroupMan::removeDownloadResult` 这个内部符号，缺所有 `aria2::*` 公开符号；头文件也没有 4 个 `ARIA2DOWN_HAS_*` 宏。`aria2_ffi.cc` 编译时所有补丁条件分支走 `#else` 软无效路径，`aria2_ffi_get_capabilities` 返回空数组，`LibraryDaemon` 把全部 4 项 capability 标记缺失。
- **修复**：跑 [`./scripts/build_libaria2_macos.sh`](scripts/build_libaria2_macos.sh) 重新双架构（arm64 + x86_64）+ lipo 编译并落 prebuilt。产物：`libaria2.a` 从 7.4 MB → 15.1 MB（包含 4 项补丁导出的 C++ 公开符号），`aria2.h` 同步更新 4 个 `ARIA2DOWN_HAS_*` 宏；`deps/libcares.a` + `deps/libsqlite3.a` 一并刷新到 brew 当前版本。
- **链接验证**：`flutter build macos --debug` 通过；`build/.../aria2_native.framework` 5 MB，`strings` 能看到 `downloadHandleExt` / `listDownloadResults` / `listReserved` / `removeDownloadResult` 四个 capability 字面量；`nm` 能看到 `_aria2_ffi_get_capabilities` / `_aria2_ffi_remove_download_result` / `_aria2_ffi_tell_waiting` / `_aria2_ffi_tell_stopped` 等关键 FFI 符号。
- **效果**：用户**冷启** Flutter（停掉当前 `flutter run` 后重新 `flutter run -d macos`）即可看到设置页的「功能受限模式」红条消失。相关副作用：
  - 「删除已完成任务」可直接软成功改硬清除，`removeDownloadResult` 真正生效；
  - 「等待中 / 已停止」Tab 不再退化到 Dart 模拟逻辑，`getReservedDownload` / `getDownloadResults` 在 FFI 层一次拿全；
  - BT 任务详情页可见 `errorMessage` / `numSeeders` / `seeder` / `verifiedLength` / `verifyIntegrityPending` 顶层字段。
- **关于 ld 警告**：链接日志里大量 `was built for newer 'macOS' version (26.0) than being linked (11.0)` 来自 brew 默认编译的 `libcares.a` / `libsqlite3.a`——这是 brew 走当前 SDK 编译的特性，与本次改动无关，链接结果有效，最低部署版本仍为 11.0。

### 修复（历史 Tab「下载历史删不掉」+ 详情页历史快照支持删除）

用户反馈："从历史 Tab 点进一条已被 aria2 purge 的旧任务，详情页只能看不能删；回到历史 Tab 也找不到删除按钮，只能整个清空。"

- **根因**：历史 Tab 每条只挂了「重试」按钮（`onRetry`），单条删除入口缺失；详情页的历史快照模式（`_fromHistorySnapshot==true`）下底部 `TaskDetailActionBar` 被隐藏（pause/unpause/remove 都会以 -1006 失败），但 banner 上也没有补一个本地删除按钮。aria2 内部对应任务往往已经被 `purgeDownloadResult` 清空，用户走任何 RPC 删除都只会拿到 -1006，自然「删不掉」。
- **修复 1 — 本地仓库新增 `deleteByGid`**：[`TaskHistoryRepository.deleteByGid(String gid)`](lib/data/task_history_repository.dart) 直接擦掉 JSON 中匹配 gid 的条目，重写文件并 `chmod 600`（非 Windows）。`gid==''` 直接返回 false，不读盘；条目不存在返回 false（不写盘）；正常删除返回 true。这是**纯本地**动作——不动 aria2 session，不删磁盘文件，专门对付「-1006 + 用户仍想从视图里清掉」的场景。
- **修复 2 — 历史 Tab 每条加垃圾桶按钮**：[`task_history_tab.dart`](lib/features/tasks/task_history_tab.dart) 在 retry 按钮旁挂 `Icons.delete_outline`，点击弹 [`confirmDeleteHistoryEntry`](lib/features/tasks/task_history_tab.dart) 确认对话框 → `deleteByGid` + `invalidate(taskHistoryProvider)` + SnackBar 提示。新增的 `confirmDeleteHistoryEntry` 同时被详情页复用。
- **修复 3 — 详情页历史快照 banner 加删除按钮**：[`_HistorySnapshotBanner`](lib/features/tasks/task_detail_page.dart) 从 `StatelessWidget` 改为 `ConsumerWidget`，接收 gid，在「返回任务列表」旁插入 `Icons.delete_outline` 按钮，确认后调 `confirmDeleteHistoryEntry`；删除成功自动 `Navigator.maybePop()` 回上一页，避免用户对着一个已被擦掉的快照发呆。
- **本地化**：新增 5 个 key（中英）：`historyDeleteTooltip` / `historyDeleteTitle` / `historyDeleteMessage`（明确"不影响 aria2 队列、不删磁盘文件"）/ `historyDeleteConfirm` / `historyDeleteSnack`。
- **测试**：[`task_history_repository_test.dart`](test/data/task_history_repository_test.dart) 引入 `_TempPathProvider`（基于 `path_provider_platform_interface` 的 `MockPlatformInterfaceMixin`）把 ApplicationSupportDirectory 重定向到 `Directory.systemTemp` 临时目录，新增 4 个用例覆盖 `deleteByGid`：删除存在的 gid 返回 true / 删除不存在的 gid 返回 false / 空 gid 不读盘 / 删除最后一条后仍可继续 upsert（防止文件残留破坏后续读写）。`flutter analyze` 无 issue；`flutter test` 全部 129 通过。
- **体验**：现在从历史 Tab 直接点垃圾桶 → 确认 → 这条立刻从列表消失；详情页历史快照模式也能一键删除并自动回退到上一页。

### 优化（任务不在 session 时的日志降噪：从 8 行栈降到 1 行简讯）

用户反馈："从历史 Tab 点进一个已被 aria2 purge 的任务，终端会刷 `[aria2:library] aria2.tellStatus code=-1006 → ...` + 完整 Dart 栈 + `[task_detail] tellStatus(...) failed: ...` + 又一遍栈，明明已经成功 fallback 到历史快照，日志里却像出大事了。"

这不是 bug——`task_detail_page` 已经判定为「任务不在 session」并切到本地历史快照（最后一行 `gid=... not in session; showing local history snapshot.` 即为证），但 `Aria2LoggingTransport` + `_scheduleLoad` 的 catch 块都各自打了完整堆栈，把可恢复的"任务已被 purge"误认为异常。

- **修复 1 — RPC 层软失败简讯**：[`Aria2LoggingTransport`](lib/aria2/client/logging_transport.dart) 新增 `_isExpectedSoftFailure(e)` 判定：`Aria2RpcException.code == -1006` 或消息含 `no such download` / `not found` 时改为单行 `[aria2:label] method code=-1006 → ...  (soft failure)`，**不**展开 params、**不**调 `debugPrintStack`。普通错误（鉴权失败、网络错误、未知异常）保持原行为：完整 params 摘要 + 栈。
- **修复 2 — 详情页不再二次重复打栈**：[`task_detail_page._scheduleLoad`](lib/features/tasks/task_detail_page.dart) 提前判 `_isTaskNotFoundError(e)`，命中时跳过本层的 `debugPrint(tellStatus failed)` + `debugPrintStack`，只保留 fallback 命中后的 `gid=... not in session; showing local history snapshot.` 单行。非软失败（鉴权 / 网络）仍按既有路径打完整栈。
- **测试**：[`logging_transport_test.dart`](test/aria2/logging_transport_test.dart) 新增 3 个用例覆盖「code=-1006 仅一行简讯不打栈不展 params」「"No such download" 文本同样降级」「非软失败仍打栈 + params」；保留已有 6 个用例不变以防误降级。`flutter test` 全部 125 通过。
- **体验对比**：之前一次 not-found 触发 8 行（method 摘要 + 5 行栈 + 详情页 debugPrint + 详情页栈），现在只剩 2 行（RPC 层 1 行 soft failure + 详情页 1 行 fallback 命中），真正的异常（譬如远程 aria2 鉴权失败）仍能在终端立刻看到完整栈。

### 修复（库引擎事件 GID 高位为 1 时 tellStatus 全报 -1006）

用户反馈："启动后控制台疯狂刷 `aria2.tellStatus code=-1006 → Aria2RpcException(..., aria2_ffi_tell_status) params=["-21cdbea35eeb7710", ...]`，TaskHistoryRecorder 与任务详情页对部分任务持续失败。"

- **根因**：libaria2 事件回调把 `A2Gid`（`uint64_t`）传给 Dart NativeCallable，Dart 侧 `int` 是 64 位有符号。`Aria2NativeEvent._fromCodes` 之前直接 `gid.toRadixString(16).padLeft(16, '0')`，当 GID 高位为 1（aria2 自动生成的 GID 经常如此）时输出形如 `-21cdbea35eeb7710` 的带负号字符串。该串塞回 `aria2_ffi_tell_status` 后：C 侧 `aria2::hexToGid` 拒收符号→退到 `std::stoull` 解析出截断后的随机 GID→`getDownloadHandle` 找不到→统一返回 `ARIA2_FFI_ERR_NOT_FOUND (-1006)`，恶性循环。
- **修复**：[`packages/aria2_native/lib/src/session.dart`](packages/aria2_native/lib/src/session.dart) 抽出 `formatGidAsUnsignedHex16(int)`，用无符号右移 + 低 32 位掩码拆成两段无符号 32 位整数再拼回 16 位 hex，与 aria2::gidToHex 在 RPC 中给客户端的形态完全一致。`Aria2NativeEvent._fromCodes` 改用该函数；所有依赖事件 gid 的链路（任务历史落库、详情页轮询、UI 通知聚合）即恢复正常。
- **验证**：新增 [`test/aria2/native_event_gid_test.dart`](test/aria2/native_event_gid_test.dart) 6 个用例覆盖零值/小正整数/高位为 1（旧实现会输出 `-…`）/`0x8000…0000`/全 1 与事件类型联动；`flutter analyze` / `flutter test test/aria2` 全部通过。

### 修复（任务详情页"三个 Tab 全部加载失败" + 全局错误日志可见性）

用户反馈："从任务列表 / 历史 Tab 进任务详情页，三个 Tab 都显示加载失败；UI 里看不到具体原因，终端也没有打印对应日志。" 这一组修复同时解决"看不到"与"恢复不了"两个问题。

- **根因**：`task_detail_page._scheduleLoad` 之前在 `tellStatus` 失败时把 `_status = null` 全清，body 走 `_error != null` 分支显示一个单一全屏「加载失败」页——但顶部 TabBar 仍在，切换 Tab 不变 body，用户体感"三个 Tab 都加载失败"。最典型触发场景：用户从「历史」Tab 点进一个 aria2 session 已不持有的旧任务（被 `purgeDownloadResult` 或库引擎重启清空 `downloadResults_`），`aria2_ffi_tell_status` 返回 `-1006 (ERR_NOT_FOUND)` / 远程 aria2 抛 `No such download for GID`。
- **修复 1 — 软失败 banner，保留 TabBarView**：[`task_detail_page.dart`](lib/features/tasks/task_detail_page.dart) tellStatus 失败时不再清空 `_status`。已加载过成功数据的会话继续展示旧数据 + 顶部 `_DetailErrorBanner`（红色 errorContainer 卡片，含 formatRpcError 摘要 + 「重试」按钮）；从未成功过的会话才落到全屏 `_DetailLoadingOrError`（80×80 圆形 errorContainer 图标 + 标题 + selectable 错误卡 + Retry 按钮）。
- **修复 2 — 本地历史快照 fallback**：当错误判定为「任务不在 aria2 session 中」（`Aria2RpcException.code == -1006` 或消息含 `no such download` / `not found`）时，自动从 `TaskHistoryRepository.findByGid(gid)` 读条目，用新加的 `TaskHistoryEntry.toDetailShape()` 合成 tellStatus 形状的 Map 当作只读快照——三个 Tab 立即恢复可用：Overview 看 gid/状态/总大小/已下载/dir/errorMessage，Files 看 uris，Torrent 看 infoHash + bittorrent.info.name。同时停掉轮询计时器（再调 tellStatus 也是同样错误），底部 ActionBar 隐藏（pause/unpause/delete 都会以 -1006 失败，没意义），TabBarView 上方挂一条 `_HistorySnapshotBanner`（tertiaryContainer 底色 + history 图标 + 文案 + 「返回任务列表」按钮）。新增 l10n key：`taskDetailHistorySnapshotBanner` / `taskDetailBackToList`（中英）；新增两个 [`task_history_entry_test.dart`](test/data/task_history_entry_test.dart) 用例覆盖 toDetailShape 的 tellStatus 兼容 shape 与 BT 任务的 infoHash 双重暴露。
- **修复 3 — 全局错误日志可见性**：之前所有 UI 层 catch 块都是 `catch (e) { ScaffoldMessenger.showSnackBar... }` 或更糟的 `catch (_) {}`，异常细节只到 SnackBar 文案就丢了——`Aria2LoggingTransport` 已经在 RPC 层打了完整堆栈，但 UI 层的「触发上下文」（哪个 gid、哪个用户动作）缺失。这次给 UI 层关键 catch 全部加了 `debugPrint` + `debugPrintStack`，统一格式 `[<module>] <action>(<context>) failed: <exception>`：
  - [`task_detail_page.dart`](lib/features/tasks/task_detail_page.dart)：tellStatus / getPeers / getOption / changeOption（包括之前的 `catch (_) {}`）。
  - [`task_list_page.dart`](lib/features/tasks/task_list_page.dart)：_runTick / _retryTask / _pasteAndQueueFromClipboard / _importHistoryFromClipboard / _batchAction / 单条按钮 _pauseTask / _unpauseTask / _removeTask / 批量删除中的逐条 catch。
  - [`add_task_page.dart`](lib/features/add/add_task_page.dart)：_addUris / parse torrent metainfo / pickTorrent / pickMetalink。
  - [`task_detail_actions.dart`](lib/features/tasks/task_detail_actions.dart)：底部操作栏的 `_run`。
  - 终端运行 `flutter run` / `adb logcat` / Xcode console 现在能直接看到「`[task_detail] tellStatus(deadbeef...) failed: Aria2RpcException(code: -1006, ...)`」这种带上下文的行，配合 `Aria2LoggingTransport` 已有的 `[aria2:library] aria2.tellStatus ...` 行即可完整复盘失败链路。
- **验证**：`flutter analyze` 无 issue；`flutter test` 全部 116 通过（新增 2 个 `toDetailShape` 测试）。

### 优化（界面美化 — Material 3 视觉刷新）

针对全应用界面做了一次系统性视觉升级，集中在主题 token、任务列表、启动 / 错误屏与历史 Tab。所有改动都不引入新依赖，纯 Flutter widget + theme 重排。

- **主题系统重构**：[`lib/app/theme.dart`](lib/app/theme.dart) 从 27 行扩展为完整的 token 体系——Card / Dialog / Button (Filled/Outlined/Text/Segmented) / FAB / InputDecoration / Chip / Divider / ListTile / ProgressIndicator / SnackBar / NavigationRail / NavigationBar / BottomSheet / PopupMenu / Tooltip 全部统一圆角与颜色：Card 16、Dialog 20、Button 12、Chip 8、FAB 18。AppBar 与 Rail/底栏共用 `surfaceContainerLow`，scrolledUnderElevation=0 去掉桌面端材质阴影杂讯。`SnackBar` 改为 `floating + inverseSurface`。新增 `Aria2downColors` ThemeExtension 集中维护状态色板（active / paused / complete / error / waiting）+ 下载/上传 accent。
- **任务列表顶部 — 全局速率横条**：从「一行密集文字 + version 角标」改为 [`_GlobalStatsBar`](lib/features/tasks/task_list_page.dart) 卡片：左半 ↓ 下载、右半 ↑ 上传，中间纵向分隔；数字部分用 `titleLarge + bold`，单位降至 `labelMedium`；卡片底部一行 chips 显示「活动 / 等待 / 已停止 + 数字」+ 右侧 `_ConnectionPill`（绿点 = WS 已连接 / 灰点 = 轮询）+ aria2 版本号。整卡可点击复制扩展文本（继承原行为）。chips 区域用 `SingleChildScrollView` 防止窄屏被挤出。
- **任务 tile — 状态色彩 + 卡片化布局**：[`_TaskListTile`](lib/features/tasks/task_list_page.dart) 从 `ListTile + 拥挤 subtitle` 改为自定义 InkWell 行：
  - 左侧 40×40 圆角彩色徽章（`_TaskStatusBadge`），状态色取自 `Aria2downColors`。
  - 标题加粗；右上角 `__%` 百分比与进度条同色。
  - 进度条圆角化、加高到 5px、用状态色填充。
  - 副信息行用 chips（`_StatusBadge` + `_MetaBadge`）展示「状态 · ↓ 速度 · ↑ 速度 · ⏱ ETA · # GID」，每个 chip 自带图标 + 色彩。
  - paused/removed 状态标题置灰，errorMessage 行加 `error_outline` 图标。
- **任务列表空状态**：[`_EmptyTasksState`](lib/features/tasks/task_list_page.dart) 取代朴素文字 + 按钮——88×88 圆形 `primaryContainer` 容器内放大号下载图标 + `titleMedium` 提示 + `FilledButton.icon` 行动按钮，更有"邀请添加任务"的视觉引导。
- **历史 Tab**：[`TaskHistoryTab`](lib/features/tasks/task_history_tab.dart) 同步升级——左侧 40×40 圆角徽章带状态图标（complete = ✓ 绿，error = ⚠ 红，removed = 🗑 灰，其他 = ⌚ 主色），进度条用对应状态色；空状态改为 80×80 `tertiaryContainer` 圆 + 大号 history 图标 + 标题。
- **启动 Loading 屏**：[`_DaemonLoadingScreen`](lib/app/app.dart) 替换裸 `CircularProgressIndicator + 一行文字`——居中卡片内 80×80 `primaryContainer` 圆形包裹 `cloud_download_outlined` 图标 + 外层圆环 + "aria2down" titleLarge 标题 + 副标题，首次启动更有仪式感。
- **DaemonErrorScreen**：[`lib/app/daemon_error_screen.dart`](lib/app/daemon_error_screen.dart) 从顶部对齐改为居中卡片化：80 圆形 error 容器图标 + 居中标题 + `errorContainer` 浅底色 selectable 错误卡片 + 整齐的按钮列（Filled 重试 / FilledTonal 切换远程 / Outlined 打开设置）。最大宽度 480 让桌面端不会过宽。
- **本地化**：新增 4 个 status 文案 key — `statusPaused` / `statusComplete` / `statusError` / `statusRemoved`（中英）。
- **验证**：`flutter analyze` 无 issue；`flutter test` 全部 114 通过；`dart format` 通过。

### 新增（任务列表分页 + 库引擎能力检测 — 第三轮补充）

- **#17 任务列表 stopped Tab 支持渐进加载**：之前固定 `tellStopped(num: 50)`，长期运行实例（已完成任务多）看不到 50 条之外的记录。改为 `_stoppedFetchLimit` 状态变量驱动，初始 200、步长 200、上限 2000；stopped Tab 末尾增加 `_StoppedTabFooter`，根据「本轮返回数量 < 请求量 || 已撞顶」展示「已加载全部（共 N 条）」灰字，否则展示 `OutlinedButton.icon(加载更多 (已加载 N 条))` 带 loading 旋钮。点击会同步抬高 limit 并触发 manual tick；其他 Tab 不受影响（`onLoadMoreStopped` null 时 footer 不渲染）。`_taskListSignature` 比对加入 `_stoppedReachedEnd` 防止 footer 状态变化被 unchanged 短路跳过。新增 l10n 文案 `loadMoreStopped` / `loadMoreStoppedWithCount` / `loadedAllStopped`（中英）。
- **#14 库引擎运行时 capability 检测 + UI 降级提示**：旧 `prebuilt/libaria2.a` 缺补丁时，`removeDownloadResult` / `purgeDownloadResult` 在 FFI 层走「软成功」分支，UI 看起来执行了但 stopped 列表仍在；其他几个补丁（`listReserved` / `listDownloadResults` / `downloadHandleExt`）也类似无声降级。修复链路：
  - **C++ 端**：[`packages/aria2_native/src/aria2_ffi.{h,cc}`](packages/aria2_native/src/aria2_ffi.cc) 新增 `aria2_ffi_get_capabilities()` 返回 JSON 字符串数组，元素与编译宏一一对应（`removeDownloadResult` / `listReserved` / `listDownloadResults` / `downloadHandleExt`）。该函数与 capabilities 解耦——即使本身的 `libaria2.a` 完全没打补丁，函数本身也存在（返回 `[]`），不需要重编 prebuilt。
  - **Dart 端 bindings**：[`packages/aria2_native/lib/src/bindings.dart`](packages/aria2_native/lib/src/bindings.dart) 用 `DynamicLibrary.providesSymbol('aria2_ffi_get_capabilities')` 探测，旧 `aria2_native.dylib/dll` 完全没编译过此符号时 getter 返回 null；worker 走 [`WorkerOp.getCapabilities`](packages/aria2_native/lib/src/worker.dart) 时探测到 null 上报 `[]`，等价于「零能力」。
  - **Daemon / Provider**：[`LibraryDaemon`](lib/aria2/daemon/library_daemon.dart) `start()` 后立即 `await _session!.getCapabilities()` 缓存到 `_capabilities` 字段，并把集合注入 [`Aria2InProcessTransport`](lib/aria2/client/in_process_transport.dart) 构造器（保留待未来 transport 层使用，目前 transport 层不强制报错以保留软成功兼容性）；新增 [`libraryCapabilitiesProvider`](lib/providers/library_capabilities_provider.dart) 与 [`LibraryCapability`](lib/providers/library_capabilities_provider.dart) 常量集合。子进程 / 远程 daemon 永远返回 [`LibraryCapability.all`](lib/providers/library_capabilities_provider.dart)（它们走真实 RPC，所有能力等价完整），所以 UI 永远不会对它们显示降级提示。
  - **UI**：[`SettingsPage`](lib/features/settings/settings_page.dart) 顶部连接状态卡片下方新增 `_LibraryCapabilitiesWarning` —— 仅当 `LibraryCapability.all.difference(caps).isNotEmpty` 时显示警告卡片，红色 `errorContainer` 背景 + warning 图标 + 缺失能力清单（本地化文案，按逗号分隔）+「请重新跑 `./scripts/build_libaria2_<platform>.sh` 刷新 prebuilt」提示。新增 l10n 文案 `libraryCapabilitiesDegradedTitle` / `libraryCapabilitiesDegradedBody({missing})` 与四个能力名翻译。
  - **测试**：[`test/providers/library_capabilities_provider_test.dart`](test/providers/library_capabilities_provider_test.dart) 覆盖三条路径：空集合（旧 prebuilt）/ 部分集合（差集计算正确）/ 非库引擎 daemon（永远返回完整集合）。`LibraryDaemon` 从 `final class` 改为 `base class`，仅为支持测试 `extends LibraryDaemon` 构造轻量 fake；外部仍禁止 implements。

### 修复（全应用逻辑问题专项审查 — 第三轮）

针对第三轮代码审查发现的 P0/P1/P2/P3 与若干次要问题做了进一步加固，全部为 Dart 改动，无需重新编译预编译产物。

- **P0：`LocalDaemon` 启动失败时 aria2c 子进程泄漏**：[`local_daemon.dart`](lib/aria2/daemon/local_daemon.dart) 的 `start()` 一旦 `_spawnProcess()` 已 spawn 但后续 `_waitForRpcReady()` 超时/失败就直接 rethrow，已 spawn 的 `aria2c` 进程不会被回收；同时 [`aria2_daemon_provider.dart`](lib/providers/aria2_daemon_provider.dart) 把 `ref.onDispose(daemon.stop)` 放在 `_startWithRetry` 成功之后，启动失败时 Provider 进入 error 状态也无清理钩子。现在 `start()` try/catch 包裹整个 spawn → waitReady → ws 链路，失败路径调 `_cleanupAfterStartFailure()` 强 SIGKILL 子进程、cancel stderr、清 ws/client、删除可能写出的 `rpc.secret`；Provider 改为创建 daemon 之后立即 `ref.onDispose`，保证 error 状态依然能 `stop()`。
- **P0：库引擎 worker RPC 无超时导致 UI 全局死锁**：[`packages/aria2_native/lib/src/worker.dart`](packages/aria2_native/lib/src/worker.dart) 的 `Aria2NativeWorker.send()` 之前只用裸 `Completer`，worker 因 native 异常未 `reply` 时 Future 永不完成；库模式所有 RPC 都串行经过这一个 worker，一条挂起即全局死锁（UI 轮询、入队、暂停全卡死）。新增 `defaultSendTimeout = 60s`，超时后 `_ReplyDemuxer.discard(id)` 摘除挂起 completer 并抛 `Aria2NativeCallException(code=-1007)`；迟到的 worker reply 静默丢弃（不再触发 "Future already completed"）。`close()` 共用相同机制（30s）。
- **P1：`LocalDaemon` auto-restart 后 WebSocket 推送/历史记录器失效**：子进程崩溃后 [`local_daemon.dart`](lib/aria2/daemon/local_daemon.dart) 的 `_scheduleAutoRestart` 原地替换 `_ws` 与 `_client`，但 daemon 对象本身没变；[`task_list_page.dart`](lib/features/tasks/task_list_page.dart) 用 `identical(_wsBoundDaemon, daemon)` 短路阻止重绑订阅 → 旧 `_wsSub` 指向已 `dispose` 的 stream，事件驱动刷新停止；`TaskHistoryRecorder` 因构造时快照 `daemon.client` 也变成持有过期 transport（连旧 loopback port），任务完成历史不再写入本地。修复：在 [`aria2_daemon.dart`](lib/aria2/daemon/aria2_daemon.dart) 抽象类新增 `ValueListenable<int> connectionGeneration`，`LocalDaemon` / `RemoteDaemon` 内部重建 client/WS 时自增；任务列表新增 `_onConnectionGenerationBumped` 监听器，在 generation 变化时通过 `_bindToDaemon` 重新订阅 WS 并以最新 `daemon.client` 重建 recorder。`LibraryDaemon` 永远停在 0（不会内部重建）。
- **P2：CLI/扩展与 UI 的多 URI 入队语义不一致**：[`add_uri_via_local_rpc.dart`](lib/core/add_uri_via_local_rpc.dart) 之前用 `client.addUri(uris)` 一次性把所有 URI 当**镜像**入队（单任务），而 UI 剪贴板路径走 `queueUrisToAria2` 是「每 URI 一个任务」。同一用户操作（粘贴 3 个独立链接）在 UI 与 `bin/rpc_add_uri.dart` / `bin/native_messaging_host.dart` 行为不同。改为循环单 URI 调 `addUri([uri])`，并新增 `PartialAddUrisException` 携带已成功 gid 与失败明细；CLI 在 stdout 输出成功 gid、stderr 列失败明细并以 1 退出；Native Messaging host 输出 `{ok, gid, gids, uris, errors}` 让浏览器扩展能展示部分成功状态。
- **P2：库引擎模式下陈旧 `rpc.secret` 误导扩展/CLI**：`rpc.secret` 仅由 [`LocalDaemon`](lib/aria2/daemon/local_daemon.dart) 写入；库模式（[`LibraryDaemon`](lib/aria2/daemon/library_daemon.dart)）从不更新该文件。默认库引擎 + 曾用过子进程模式时，文件可能残留旧 port/secret，扩展或 `bin/rpc_add_uri.dart` 会连一个早就下线的回环端口或鉴权失败。修复：`LibraryDaemon.start()` 立即删除残留 `rpc.secret`；`LocalDaemon.stop()` 也删除（守 daemon 关闭后不再有可用凭据）；启动失败回滚路径同样删除。
- **P3：`RemoteDaemon` 无运行时健康检查导致断线后永久失效**：[`remote_daemon.dart`](lib/aria2/daemon/remote_daemon.dart) 之前只在 `start()` 时一次性建连，运行中远程 aria2 重启/网络瞬断时 UI 持续报错直到用户手动 invalidate provider。新增 `_healthTimer`（30s）+ `_runHealthCheck`：HTTP `getVersion` 超时则 dispose WS 等下一轮再连；HTTP 通了但 WS 缺失时尝试重连，成功后 bump `connectionGeneration` 让 UI 自动重绑订阅，无需用户介入。
- **P3：`LocalDaemon` auto-restart 与 `stop()` 的竞态**：用户点退出与子进程崩溃几乎同时发生时，exit handler 已经 `_scheduleAutoRestart()` 而 `stop()` 设了 `_userStopped=true` 与 cancel timer——但 timer 与 stop 之间仍有窗口可能再次 spawn。新增 `_restartGen` token：每次 schedule 自增并快照，`stop()` 也自增让在途 Timer 触发时识别到自己已过期；auto-restart 完成前再次检查 generation/userStopped，若期间发生 stop 就 cleanup 刚 spawn 的进程。
- **P3：`TaskHistoryEntry.fromJson` 对数值字段类型假设过窄**：[`task_history_entry.dart`](lib/data/models/task_history_entry.dart) 用 `as int?` 强转 `totalLength`/`completedLength`；JSON 若来自旧版本（int）/手动编辑（字符串）/RPC 原样转储（字符串）会 TypeError 让整条历史无法反序列化。改用 `_parseInt` 统一接受 int / num / 字符串 / 空值，与 `fromTellStatus` 一致。新增 `test/data/task_history_entry_test.dart` 覆盖 int / 字符串 / num / 缺失 / roundtrip 五条路径。
- **P3：`LocalRpcCredentials.extensionConfigJson` 未对 secret 做 JSON 转义**：[`local_rpc_credentials.dart`](lib/core/local_rpc_credentials.dart) 之前直接字符串拼接 `"secret": "$secret"`，secret 含 `"` / `\` / 换行时会生成非法 JSON。改用 `JsonEncoder.withIndent('  ').convert(...)` 让 dart:convert 完成转义；新增测试覆盖含特殊字符 secret 的 roundtrip。
- **P3：`Aria2NativeWorker.close()` 超时后无 deinit 兜底**：（与上面 P0 同体修复）`close()` 改为立即设 `_closed=true`，避免超时窗口期间新 `send()` 还能进入 in-flight 状态；30s timeout 后仍 kill isolate，但其余 ReceivePort/StreamController 清理逻辑保留。
- **次要 #15：`Aria2Client` 多处对 null result 用 `r!`**：[`aria2_client.dart`](lib/aria2/client/aria2_client.dart) 之前 transport 返回 null 时抛 `Null check operator`/`TypeError`，文案不友好；新增 `_expectGid` 显式判类型并抛 `Aria2TransportException`，`formatRpcError` 能给出可读提示。
- **次要 #16：`HttpTransport` JSON-RPC error code 仅用 `as int?`**：[`http_transport.dart`](lib/aria2/client/http_transport.dart) 改用 `(err['code'] as num?)?.toInt()`，非标准 RPC 代理返回 `"code": 1.0` 时也能保留真实错误码。
- **次要 #18：托盘 `pauseAll` / `unpauseAll` 失败被静默吞掉**：[`tray_exit_binding.dart`](lib/app/tray_exit_binding.dart) `_safeRun` 从 `catch (_) {}` 改为带 `debugPrint` + `debugPrintStack`，daemon 未就绪/RPC 失败时点托盘菜单仍能在 console 留痕。
- **次要 #19：`LibraryDaemon` / `LocalDaemon` 在用户配置目录不存在时静默回退**：之前只 `await d.exists()` 判存在，缺失时落回默认 Downloads 而不提示。现在两者都尝试 `create(recursive: true)`，失败再回退，且明确尊重用户配置。
- **次要 #20：库模式 `pauseAll` 始终走 O(n) 模拟，未利用 native 批量 API**：[`in_process_transport.dart`](lib/aria2/client/in_process_transport.dart) 改为优先调 `session.pauseAll()` / `session.unpauseAll()`，仅在 native 失败（旧 prebuilt 不支持）才退化到逐条 pause。任务多时性能显著改善。已更新 `test/aria2/in_process_transport_test.dart` 同时覆盖 native 与 fallback 两条路径。
- **次要 #7/#8/#21：`queueUrisToAria2` 部分失败汇总 + URI 协议校验 + waiting 分页统一**：[`queue_uris.dart`](lib/core/queue_uris.dart) 改为 catch 单条 addUri 错误继续循环并收集进新的 `errors: List<QueueUrisFailure>` 字段（向后兼容 `r.added`/`r.skipped`）；新增 `_isAcceptableForAria2` 协议白名单过滤（http/https/ftp/sftp/magnet+btih），非法字符串不再传给 aria2 浪费 RPC；`tellWaiting` num 统一到 `kTaskListTellWaitingMax = 200`（之前 queue_uris 用 500、列表页用 200，超量时去重漏检）。任务列表与 Add Task 页面同步消费 `errors` 字段：全失败时展示首条 RPC 错误真实文案，部分成功时把 errors 数计入 skipped 摘要。新增三个回归测试。

### 修复（全应用逻辑问题专项审查 — 第二轮）

针对第二轮代码审查发现的 13 项潜在逻辑问题做了系统性修复。前 7 项纯 Dart 改动（无需重新编译预编译产物即可生效），后 4 项扩展了 libaria2 公共 API（需要重新跑 `./scripts/build_libaria2_<platform>.sh`），并在 Dart 侧加了无条件兜底，使旧预编译产物也能拿到正确语义。

- **库模式「等待」「已停止」标签页永远是空的**：[`packages/aria2_native/src/aria2_ffi.cc`](packages/aria2_native/src/aria2_ffi.cc) 的 `aria2_ffi_tell_waiting` / `aria2_ffi_tell_stopped` 之前直接返回 `[]`——上游 libaria2 1.37 的公开 API 只暴露 `getActiveDownload`（active），没有 reserved / downloadResults 的枚举接口。后果：等待中 / 已停止任务不显示；`queueUrisToAria2` 去重只能命中 active，导致重复入队；`TaskHistoryRecorder.onStoppedList` 喂空列表，重启后已完成但未发 WS 的任务全部丢历史。
  - **libaria2 patch**：在 [`third_party/aria2/src/aria2api.cc`](third_party/aria2/src/aria2api.cc) 与 [`includes/aria2/aria2.h`](third_party/aria2/src/includes/aria2/aria2.h) 新增 `aria2::getReservedDownload(Session*)` / `aria2::getDownloadResults(Session*)`，分别走 `RequestGroupMan::getReservedGroups()` / `getDownloadResults()`；通过 `ARIA2DOWN_HAS_LIST_RESERVED` / `ARIA2DOWN_HAS_LIST_DOWNLOAD_RESULTS` 特性宏对外标识。
  - **FFI shim**：`aria2_ffi_tell_waiting` / `aria2_ffi_tell_stopped` 现在用新引入的 `emit_status_array` 辅助函数统一处理 offset/num 分页（与 aria2 RPC 语义对齐：负 offset 从末尾计数，负 num 等价于到末尾）；宏存在时返回真实列表，宏不存在时仍兼容老预编译。
- **库模式「全部暂停」不暂停 waiting / 「全部继续」彻底 no-op**：`aria2_ffi_pause_all` 之前只迭代 `getActiveDownload`（active），跳过 reserved；`aria2_ffi_unpause_all` 直接 return OK 什么也不做。修复双管齐下：
  - **FFI shim**：`aria2_ffi_pause_all` 现在同时迭代 active + reserved；`aria2_ffi_unpause_all` 迭代 reserved 并 `unpauseDownload` 每条（需 `ARIA2DOWN_HAS_LIST_RESERVED`，单条 `cannot be unpaused now` 错误吞掉以免阻塞其他条）。
  - **Dart 兜底**：[`Aria2InProcessTransport`](lib/aria2/client/in_process_transport.dart) 不再透传 `pauseAll` / `unpauseAll` 到 `session.pauseAll()`，而是先 `tellActive` + `tellWaiting` 拿到全部 gid，再逐条 `pause` / `unpause`。这样即便用户跑在「未重新编译的旧预编译 libaria2.a」上，「全部暂停 / 全部继续」按钮也是真正生效的。新增 `test/aria2/in_process_transport_test.dart` 覆盖 pauseAll / forcePauseAll / unpauseAll 的录像-断言。
- **任务详情 Torrent Tab 的「种子数 / 本机做种 / VerifyIntegrity 进度 / errorMessage」永远为空**：libaria2 公开 `DownloadHandle` 不暴露 `errorMessage` / `numSeeders` / `seeder` / `verifiedLength` / `verifyIntegrityPending`，结果库模式下 `status_to_writer` silently 丢弃这些字段。修复：
  - **libaria2 patch**：扩展 `DownloadHandle` 抽象类（[aria2.h](third_party/aria2/src/includes/aria2/aria2.h)）增加 5 个 getter；`RequestGroupDH` 实现里走 `BtRegistry::get(gid)->peerStorage->getUsedPeers()` 数 seeder、`group->isSeeder()`、`CheckIntegrityMan::isPicked/isQueued` 镜像 RpcMethodImpl::gatherProgress 的逻辑；`DownloadResultDH::getErrorMessage` 映射 `DownloadResult::resultMessage`。`getDownloadHandle` 改成把 `DownloadEngine*` 透传给 `RequestGroupDH`，handle 生命周期仍是一次 `run_once` 内部。
  - **FFI shim**：`status_to_writer` 在宏 `ARIA2DOWN_HAS_DOWNLOAD_HANDLE_EXT` 存在时，按 keys 过滤逐字段输出，全部与 aria2 RPC 完全一致（`errorMessage`/`numSeeders` 仅非默认值时写、`seeder`/`verifyIntegrityPending` 仅 true 时写）。
- **「粘贴并入队」对同一 URL 出现多次仍创建多个任务**：[`queueUrisToAria2`](lib/core/queue_uris.dart) 上一轮改为 per-URI `addUri` 之后丢了「入参内部去重」——若用户在 Add Task 页面手输或粘贴里同一条 URL 出现两次，会创建两个相同任务（剪贴板路径走 `extractDownloadUrisFromText` 已自带去重，但 Add Task 页面文本框不走它）。现在循环开始前先做规范化（trim + toLowerCase）的 `LinkedHashSet` 去重，重复条目计入 `skipped`；新增 `test/core/queue_uris_test.dart` 三个回归用例（内部去重 / 空白条目 / 与现有任务双重比对）。
- **任务详情页「重试」按钮把镜像 URI 拆成 N 个独立任务**：[`task_detail_actions.dart`](lib/features/tasks/task_detail_actions.dart) 此前调 `queueUrisToAria2`，导致原任务 `files[].uris[]` 里的镜像 URL（如 metalink follow-by、aria2 自带的 mirror 列表）每条变成一个独立下载任务。「重试」语义应当是把原任务原样再跑一次，所有镜像继续是同一个任务的镜像。改为直接调 `client.addUri(uris, options: {dir})`，与列表页 `_retryTask` 保持一致。
- **`Aria2Client.removeTask` 把第一次 `forceRemove` 异常静默吞掉**：[`aria2_client.dart`](lib/aria2/client/aria2_client.dart) `removeTask` 在「未知 status 时先 forceRemove，失败再 removeDownloadResult」的 fallback 链里，第一次的异常被 `catch (_) {}` 吃掉。如果两次都失败，上层只能看到第二次（很可能是「GID 不在 downloadResults_ 中」这种次要错误），完全看不到第一次的真正根因（网络 / 鉴权 / 超时）。现在第一次失败时用 `debugPrint('[aria2] removeTask(gid) forceRemove failed, falling back...: <error>')` 落盘到调试日志，第二次失败时正常 rethrow；测试覆盖两路径。
- **任务详情 Overview / 历史记录的 `infoHash` 显示条件耦合到 `bittorrent` Map 必须存在**：[`task_detail_page.dart`](lib/features/tasks/task_detail_page.dart) 与 [`TaskHistoryEntry.fromTellStatus`](lib/data/models/task_history_entry.dart) 之前要求 `bittorrent is Map && infoHash isNotEmpty`。但 magnet 链刚加入还没拿到 metadata 时，aria2 已经能输出 `infoHash`（顶层字段），`bittorrent` 子结构却还是 null/空。解耦：只判 `infoHash isNotEmpty`，让早期阶段也能看到 InfoHash，历史持久化也提前包含。
- **托盘 tooltip 在 stat 流出错 / loading 时停留在上一份成功值**：[`tray_exit_binding.dart`](lib/app/tray_exit_binding.dart) 之前只在 `whenData` 路径里推 tooltip——远程网络断开 / daemon 重启时，托盘上显示的是「掉线前最后一刻」的速率与计数，用户无从感知断线。新增 `trayToolTipOffline` 文案（中英）与 `_pushOfflineToolTip`：error 走脱机文案；loading 仅在曾经显示过 stat 之后才转脱机（避免首帧 loading 把默认 tooltip 抹掉）。
- **`Aria2NativeWorker` 关闭顺序里 events ReceivePort listener 没显式 cancel**：之前 `replyReceive.listen(...)` / `events.listen(...)` 不保留 subscription；`close()` 直接关闭 ReceivePort，listener 只能靠 onDone 回收。在 isolate 已 kill 但 events port 还在排空消息的窗口里，listener 可能往已关闭的 controller 推数据（broadcast controller 静默忽略，但仍是 bad smell）。现在保留 `replyPortSub` / `eventPortSub`，关闭顺序：cancel listener → close ReceivePort → close StreamController。`eventController.add` 前加 `!isClosed` 双保险。
- **`LocalDaemon._waitForRpcReady` 启动期会被 logging transport 刷出几十条「连接被拒」错误栈**：[`local_daemon.dart`](lib/aria2/daemon/local_daemon.dart) 探活循环是「预期失败」（aria2c 子进程还没 listen，每 100ms retry 一次，至多 50 次），但每次失败都会触发 `[aria2:local] aria2.getVersion → Connection refused` + `debugPrintStack`。即便 Flutter 节流大部分，`adb logcat` / Xcode console 仍可见多条红字栈帧，给排查带来「daemon 启动失败」的视觉错觉。现在探活专用一个不带 logging 装饰器的临时 client，等就绪后再装上生产 client。
- **`SettingsPage._save` 触发 daemon invalidate 时把 SettingsPage 自己 unmount，「已保存」snackbar 看不到**：[`settings_page.dart`](lib/features/settings/settings_page.dart) `_save` 在 `invalidate(aria2DaemonProvider)` 后再 `if (mounted) showSnackBar`。但当 SettingsPage 是从 DaemonErrorScreen 上推出来的时候，invalidate 会触发上层 MaterialApp 整棵被替换，SettingsPage 一并 unmount → `mounted=false` → snackbar 永远不显示。把 snackbar 调用挪到 invalidate 之前；ScaffoldMessenger 已经接到消息，即便后续 widget tree 重建也不影响显示。

### 新增（可观测性）

- **统一 RPC 错误日志**：新增 [`Aria2LoggingTransport`](lib/aria2/client/logging_transport.dart) 装饰器，在所有 `Aria2Client` 构造处（[`LibraryDaemon`](lib/aria2/daemon/library_daemon.dart)/[`LocalDaemon`](lib/aria2/daemon/local_daemon.dart)/[`RemoteDaemon`](lib/aria2/daemon/remote_daemon.dart)、[`addUrisViaStoredCredentials`](lib/core/add_uri_via_local_rpc.dart)、[`probeRemoteRpc`](lib/core/remote_rpc_probe.dart)）包一层日志。任何 RPC 调用失败时按 `[aria2:<label>] <method> code=<n> → <exception>  params=<truncated>` 打到 `debugPrint`（`flutter run` 控制台 / `adb logcat` / Xcode console 均可见），并附带 `debugPrintStack` 栈帧。仅 rethrow 不改变控制流；params 摘要走「按元素逐个判定」的懒汇总——String 超过 160 字符替换成 `<String len=N>`、Map 替换成 `<Map keys=N>`、嵌套 List 递归同样处理，避免 `addTorrent` 失败时把数 MB 的 base64 种子先完整 toString 再 substring。新增 `test/aria2/logging_transport_test.dart` 三个回归（超长 String / 嵌套 List / Map 计数）。

### 修复（全应用功能性问题专项排查）

- **任务详情页删除按钮报 `aria2_ffi_remove code=-1004 params=[null]`**：症状是 App 重启后打开一条已不在库会话里的任务详情（例如 `downloadResults_` 被 trim，或重启后无 session 恢复），UI 仍渲染了底部操作栏并允许点击删除。根因有二：
  - FFI `aria2_ffi_tell_status` 在 `getDownloadHandle` 返回 null 时仍写出空 JSON 且返回 OK，Dart 侧解码成空 Map，[`TaskDetailPage`](lib/features/tasks/task_detail_page.dart) 误以为加载成功；[`TaskDetailActionBar`](lib/features/tasks/task_detail_actions.dart) 之前从 `status['gid']` 取 gid，`'${null}'` 被字符串插值成 `"null"`，点删除时 FFI 拿到非法 GID → `ARIA2_FFI_ERR_INVALID_ARGUMENT (-1004)`。
  - 修复 1：FFI `status_to_writer` 改为返回 `bool`，`aria2_ffi_tell_status` 在任务不存在时返回 `ARIA2_FFI_ERR_NOT_FOUND`，与远程 aria2 RPC（抛 "No such download for GID#…"）行为一致；任务详情页随即进入 `_error` 分支显示「加载失败」，不再渲染操作栏。
  - 修复 2：`TaskDetailActionBar` 现在显式接收 `gid` prop，由 [`TaskDetailPage`](lib/features/tasks/task_detail_page.dart) 从路由参数 `widget.gid` 传入，杜绝再从 status Map 取 gid 的反模式。
- **库模式删除已完成/失败任务报 `aria2_ffi_remove code=-1`**：已结束任务只存在于 `RequestGroupMan::downloadResults_`，`aria2.remove` / `aria2.forceRemove`（以及 libaria2 的 `removeDownload`）对它们返回 -1。修复分两层：
  - **Dart 侧**：新增 [`Aria2Client.removeTask`](lib/aria2/client/aria2_client.dart)，按 `status` 选择 RPC（`complete`/`error`/`removed` → `removeDownloadResult`，其它先 `forceRemove`、失败再 fallback）；任务详情、列表内按钮 / 滑动删除、批量删除已停止任务（[task_detail_actions.dart](lib/features/tasks/task_detail_actions.dart) / [task_list_page.dart](lib/features/tasks/task_list_page.dart)）均改用该方法。
  - **libaria2 公共 API 扩展**：上游 libaria2 1.37 的公开 C++ API 只能操作 active/waiting，stopped 任务一旦进入 `downloadResults_` 就无法清除。新增 `aria2::removeDownloadResult(Session*, A2Gid)` / `aria2::purgeDownloadResult(Session*)` 到 [`third_party/aria2/src/aria2api.cc`](third_party/aria2/src/aria2api.cc) 与 [`includes/aria2/aria2.h`](third_party/aria2/src/includes/aria2/aria2.h)，并在 `aria2.h` 暴露 `ARIA2DOWN_HAS_REMOVE_DOWNLOAD_RESULT` 特性宏。FFI shim（[packages/aria2_native/src/aria2_ffi.cc](packages/aria2_native/src/aria2_ffi.cc)）按宏分支：宏存在时调用新公共 API 真正清空 stopped 条目；宏不存在（旧的 `prebuilt/libaria2.a`）则软成功——Dart 侧不报错，stopped 条目随 `max-download-result` 自动裁剪。
  - **要点**：要获得真正的「删除立即生效」，请重新跑一次 `./scripts/build_libaria2_<platform>.sh` 刷新 `packages/aria2_native/prebuilt/<platform>/<arch>/{libaria2.a, include/aria2/aria2.h}`；该脚本会把更新过的 `aria2.h` 一并拷过去，下一次 `flutter build` 自动启用完整路径。
- **任务详情概览 Tab 在 BT 任务下报「Aria2RpcException code: -1005 Unexpected extension byte」**：上一轮把 `infoHash` 加进 `kTaskDetailTellKeys` 之后，库模式（内嵌 libaria2）的 FFI 路径暴露了一个已存在的 bug——`packages/aria2_native/src/aria2_ffi.cc` 的 `status_to_writer` 直接把 `aria2::DownloadHandle::getInfoHash()` 返回的 **20 字节二进制 SHA-1** 塞进 JSON 字符串里。aria2 自带的 JSON-RPC 服务端（`RpcMethodImpl.cc::gatherProgressBitTorrent`）会先用 `util::toHex` 转 40 位小写十六进制，我们的 FFI shim 没有，结果 JSON 里出现非 UTF-8 字节序列；worker isolate 在 `_takeStringPtr` 调 `Pointer<Utf8>.toDartString()` 时被严格的 `Utf8Decoder` 拒绝，`FormatException` 被 catch 后只剩 code=-1005 的兜底语，整张概览 Tab 都打不开。修复双管齐下：(1) FFI shim 新增 `to_hex_lower` 并在 `infoHash` 字段输出处调用，与 aria2 自带 RPC 完全一致；(2) `worker.dart::_takeStringPtr` 改用 `Utf8Decoder(allowMalformed: true)`，让未来 libaria2 任何字段（如某些遗留编码 torrent 的 `info.name` / `comment`）泄露字节时退化为 U+FFFD 而不是整条 RPC 失败。
- **桌面托盘菜单文案不本地化**：`DesktopIntegration` 之前位于 `MaterialApp` 之上，调用 `AppLocalizations.of(context)` 永远返回 `null`，结果托盘菜单/tooltip 一直显示英文默认值，无视用户切换的 `AppLocalePreference`。现在把托盘文案同步迁移到 [`TrayExitBinding`](lib/app/tray_exit_binding.dart)（位于 `MaterialApp.builder` 内部，可访问 `AppLocalizations`），并在文案变化时才推送一次，避免重复 `setContextMenu` 抖动。`DesktopIntegration` 只保留与 l10n 无关的关闭/最小化/开机自启同步。
- **任务详情 Torrent Tab 的「InfoHash / 种子数 / 本机做种」一直为空**：`kTaskDetailTellKeys` / `kTaskHistoryTellKeys` 漏掉了 aria2 `tellStatus` 响应里**顶层**的 `infoHash` / `numSeeders` / `seeder` 字段（aria2 把它们放在响应根而不是 `bittorrent` 子结构里）。同时修正 [`task_detail_page.dart`](lib/features/tasks/task_detail_page.dart) Overview Tab 以及 [`TaskHistoryEntry.fromTellStatus`](lib/data/models/task_history_entry.dart) 错误读取 `bittorrent.infoHash` 的路径，改为 `status['infoHash']`，BT 任务详情和历史记录现在能正确显示 / 持久化 InfoHash。
- **「粘贴并入队」/「粘贴并添加」一次只创建 1 个下载**：[`queueUrisToAria2`](lib/core/queue_uris.dart) 之前把多条 URI 合并到单次 `aria2.addUri` 调用，而 aria2 的语义是「同一资源的多个镜像 URL」——N 条独立链接被当成 1 个任务的 N 个镜像。现在按每条 URI 单独发起一次 `addUri`，N 个 URL 严格对应 N 个独立任务；去重逻辑保留。新增针对多 URI / 去重场景的回归测试（`test/core/queue_uris_test.dart`）。
- **`DaemonErrorScreen` 的「打开设置」按钮在 daemon 启动失败时点了会崩溃**：当 aria2 启动失败，应用挂载的是裸 `MaterialApp(home: DaemonErrorScreen)`，没有任何 `GoRouter` scope，原代码 `context.go('/settings')` 会抛 `GoRouterScope not found`。改为 `Navigator.push(MaterialPageRoute(builder: (_) => const SettingsPage()))`，依赖 `MaterialApp` 自带的 `Navigator` 即可；用户可在 daemon 故障时仍打开设置页修改二进制路径或切到远程 RPC。
- **库模式（内嵌 libaria2）daemon 重启后任务列表丢失实时 WS 事件**：[`task_list_page.dart`](lib/features/tasks/task_list_page.dart) 之前用 `daemon.rpcPort` 判断是否需要重新订阅事件源；`LibraryDaemon.rpcPort` 恒为 0，当 daemon 被 `invalidate` 后新实例 `rpcPort` 仍是 0，相等判定让代码跳过重绑定，结果 `_wsSub` 还指向已 `dispose` 的旧 `_LibraryEventBridge`，所有 `onDownloadComplete` 等事件直到下一次定时轮询才被发现。改用 `identical(daemon, _wsBoundDaemon)` 通过实例身份判定，保证每个新 daemon 都正确接管事件流。
- **任务列表轮询计时器不响应前台/后台切换**：`_TaskListPageState._restartPollTimer` 之前只在 `initState` 和 daemon 重连时调用，移动端进入后台 / 返回前台时不会重新计算间隔，导致后台仍以 8s（无 WS）/30s（有 WS）轮询，与「移动端后台 60s」的设计意图不符。新增 `ref.listenManual<bool>(appInBackgroundProvider, …)`，前后台切换立即重启计时器。

### 新增

- **应用图标**：新增 `assets/icon/app_icon.png`（1024×1024，品牌色 `#1565C0`、下载箭头与 aria2「2」徽标）；通过 `flutter_launcher_icons` 为 Android / iOS / macOS / Windows / Linux 生成各尺寸启动图标；MSIX `logo_path` 与托盘 `tray.png` 同步更新。

### 新增（全平台后台能力强化）

- **桌面托盘扩展**：托盘菜单从「显示窗口 / 退出」扩展为「显示窗口 / 新建下载… / 全部暂停 / 全部继续 / 打开下载目录 / 退出」；托盘 tooltip 实时显示当前下载/上传速度与活跃/等待任务数；右键弹出菜单、双击/单击托盘图标恢复主窗口。
- **桌面静默启动**：新增 `AppSettings.startMinimized`，桌面端配合开机自启可在启动时直接最小化到托盘（[lib/main.dart](lib/main.dart) 在显示窗口之前读取 `SettingsRepository`，在 `initDesktopShell` 完成后立即 `hide`）。
- **Android 前台服务通知动态化**：[Aria2KeepAliveService.kt](android/app/src/main/kotlin/cloud/iothub/aria2down/Aria2KeepAliveService.kt) 支持 `start` / `update` 动作，通知正文实时显示 `↓ down ↑ up  活动 N · 等待 M`；通知按钮提供「显示 / 全部暂停 / 全部继续 / 退出」，点击通知体回到任务列表；活跃任务期间持有 `PARTIAL_WAKE_LOCK`，空闲后释放。
- **Android 控制信号流**：新增 `cloud.iothub.aria2down/keep_alive_control` EventChannel；通知按钮通过 `MainActivity` 转发 `pause_all` / `resume_all` / `show_window` 到 Flutter，由 [`MobileBackgroundBinding`](lib/app/mobile_background_binding.dart) 调用 `Aria2Client.pauseAll/unpauseAll` 或路由到任务列表。
- **iOS 后台时间**：[AppDelegate.swift](ios/Runner/AppDelegate.swift) 进入后台时调用 `beginBackgroundTask`，并注册 `BGAppRefreshTask` (`cloud.iothub.aria2down.bgrefresh`) / `BGProcessingTask` (`cloud.iothub.aria2down.bgprocessing`)；[`Info.plist`](ios/Runner/Info.plist) 声明 `UIBackgroundModes=fetch,processing` 与 `BGTaskSchedulerPermittedIdentifiers`。
- **统一全局统计 Provider**：[`globalStatStreamProvider`](lib/providers/global_stat_provider.dart)（独立 1s/5s 自适应轮询，前后台切换立即唤醒）作为桌面托盘 tooltip、Android 前台通知的唯一数据源，与任务列表页轮询解耦。
- **移动端后台保活开关**：新增 `AppSettings.keepAliveInBackground`（默认开启）；Android 关闭后立即 `stopService`，iOS 仍保留 BGTask 调度（系统决定是否执行）。
- **新 l10n 文案**：`trayNewTask / trayPauseAll / trayResumeAll / trayOpenDownloads / trayToolTipStats / startMinimized(+Desc) / keepAliveInBackground(+Desc) / keepAliveTitle / notifPauseAllDone / notifResumeAllDone`，同时修复 `app_zh.arb` 中 `speedGlobalExtended` 的重复 key。
- **结构变化**：`TrayExitBinding` 迁移到 router 之内并扩展为「桌面托盘所有命令中枢」；新增 [`MobileBackgroundBinding`](lib/app/mobile_background_binding.dart) 负责 Android 通知更新与控制信号订阅；`LibraryDaemon` / `LocalDaemon` 不再直接调 `AndroidKeepAlive`，统一由 binding 根据「daemon 已就绪 + 移动平台 + keepAlive 开关」三件事决策。

### 新增（关联完善 / Linux & Windows portable）

- **Linux 系统级安装脚本**：新增 [scripts/install_linux_associations.sh](scripts/install_linux_associations.sh) 与 [scripts/uninstall_linux_associations.sh](scripts/uninstall_linux_associations.sh)，把 `linux/aria2down.desktop`（含 `MimeType=`）和自定义 MIME XML 安装到 `/usr/share/`（系统级）或 `~/.local/share/`（用户级），并自动调 `update-desktop-database` / `update-mime-database`；可选 `--set-default` 一键把 aria2down 设为 `magnet:` / `.torrent` / `.metalink` / `aria2down://` 的默认处理器。
- **自定义 MIME 注册**：新增 [linux/aria2down-mime.xml](linux/aria2down-mime.xml)，显式声明 `application/metalink+xml`、`application/metalink4+xml`（部分发行版的 shared-mime-info 默认不带），含 `*.metalink` / `*.meta4` glob 与 XML magic 匹配，确保「双击 .metalink」一定能路由到 aria2down。
- **AppImage 关联保留**：[scripts/package_desktop.sh](scripts/package_desktop.sh) 的 AppImage 流程改为直接使用仓库内完整 `aria2down.desktop` + `aria2down-mime.xml`（之前 heredoc 生成的精简 desktop 会丢失 MimeType），配合 AppImageLauncher 安装后能自动注册全部关联。
- **Windows portable 注册表助手**：新增 [scripts/register_windows_associations.ps1](scripts/register_windows_associations.ps1)。MSIX 声明仅对 MSIX 安装包生效，对解压 zip 直接运行的 portable 版无能为力；本脚本以 ProgId 形式（`aria2down.torrent.1` / `.metalink.1` / `.meta4.1`）把 `.torrent` / `.metalink` / `.meta4` 与 `aria2down:` / `magnet:` 两个 URL Protocol 写入 `HKCU\Software\Classes`，无需管理员；文件扩展用 `OpenWithProgids` 不抢系统首选；支持 `-Unregister` 清理。
- **iOS Files App 集成**：`ios/Runner/Info.plist` 增加 `LSSupportsOpeningDocumentsInPlace=true` 与 `UIFileSharingEnabled=true`，从「文件」App / 邮件附件直接把 `.torrent` 用 aria2down 打开（in-place），同时让 aria2down 沙盒目录出现在「我的 iPhone」分组，便于跨 App 转移种子文件。
- **文档**：[docs/DEEPLINKS.md](docs/DEEPLINKS.md) 同步更新 Linux 安装脚本用法、Windows portable 关联注册方法与 iOS 「文件」集成说明。

### 新增（外部唤起 / 跨平台 deep link）

- **`aria2down://` 自定义 Scheme**：所有原生平台统一接口（`aria2down://add?uri=…&uris=…&url=…`、`aria2down://magnet?xt=…`），任意浏览器 / 扩展 / 桌面快捷方式均可唤起本应用并预填新建任务。
- **系统级处理器注册**：
  - **Android**：`intent-filter` 注册 `aria2down`、`magnet`、`.torrent`、`.metalink/.meta4` 与 `ACTION_SEND text/plain` 分享菜单；新增 `cloud.iothub.aria2down/incoming_link` MethodChannel 从 `content://` 读取 torrent 字节；按 app_links 要求关闭 Flutter 内建 deep linking。
  - **iOS / macOS**：`Info.plist` 增加 `CFBundleURLTypes`（`aria2down`、`magnet`）、`CFBundleDocumentTypes` 与 `UTImportedTypeDeclarations`（`.torrent` / `.metalink`，`LSHandlerRank=Alternate` 不抢默认）。
  - **Linux**：`linux/runner/my_application.cc` 改为单实例 + `G_APPLICATION_HANDLES_OPEN`，新增 `linux/aria2down.desktop` 模板，`MimeType=` 注册 `x-scheme-handler/aria2down`、`x-scheme-handler/magnet`、`application/x-bittorrent`、`application/metalink+xml`。
  - **Windows**：`windows/runner/main.cpp` 接入 app_links `SendAppLinkToInstance`，已存在窗口时把 deep link 转发给主实例；`msix_config` 增加 `protocol_activation: aria2down, magnet` 与 `file_extension: .torrent, .metalink, .meta4`。
- **Dart 派发链路**：
  - `lib/core/incoming_link.dart`：纯函数解析 URI / 分享文本，输出 `IncomingUris` / `IncomingFile` / `IncomingUnknown` 三态。
  - `lib/core/incoming_file_loader.dart`：兼容 `file://` 与 Android `content://`（通过 MethodChannel）读取本地字节。
  - `lib/providers/pending_payload_provider.dart`：缓冲未消费的 torrent / metalink 字节，AddTaskPage 首次构建时自动 `addTorrent` / `addMetalink`，多文件 torrent 沿用现有选择对话框。
  - `lib/app/incoming_link_listener.dart`：基于 `app_links` 的 `uriLinkStream` + `getInitialLink` 监听器，挂在 `MaterialApp.router` 之下；路由至 `/add?uri=…` 复用现有预填。
- **依赖**：`app_links: ^6.4.1`。
- **测试**：新增 `test/core/incoming_link_test.dart`（15 用例，覆盖 scheme / magnet / file / content / 分享文本 / 备选键 / 兜底）。
- **文档**：[docs/DEEPLINKS.md](docs/DEEPLINKS.md) 重写为「应用内深链 + 外部唤起」综合手册，含各平台配置、测试命令与浏览器扩展关系说明。

### 重大变更

- **默认下载引擎切换为内嵌 libaria2（ADR-007）**：macOS / Linux / Windows / Android / iOS 五个原生平台均通过 Dart FFI 在应用进程内运行 aria2，下载更快启动、不再依赖随包发布的 `aria2c` 二进制。
- **iOS 现在原生支持本机下载**（取代此前的仅远程模式），通过 `packages/aria2_native` 静态链接 libaria2。
- **设置 → 本机引擎**：新增 **内嵌库 / aria2c 子进程** 切换；默认开启「失败时自动回退到子进程」，确保旧版构建/未带 libaria2 产物的环境仍可工作。

### 变更

- **移动端体验**：首次安装默认本机内嵌引擎；设置页移动端说明卡片与底部保存栏；任务列表 FAB、滑动操作、紧凑统计；添加页 FAB；后台降低轮询频率；更新欢迎与横幅文案（本机下载 + 后台限制说明）；iOS 隐藏子进程引擎选项。

### 修复

- **界面操作延迟数百毫秒**：根因是 `Aria2InProcessTransport` / `LibraryDaemon`
  在主 isolate（Flutter UI 线程）上同步调用 `aria2_ffi_run_once`，进而触发
  libaria2 `DownloadEngine::run(RUN_ONCE)` → `eventPoll_->poll(refreshInterval=1s)`，
  每次都可能阻塞主线程最长 1 秒，与定时器 200ms~800ms 的 tick 叠加后
  几乎持续占用 UI 线程。修复方案：把所有 libaria2 FFI 调用搬到独立 worker
  isolate（`packages/aria2_native/lib/src/worker.dart`），主 isolate 仅通过
  SendPort 异步收发消息；事件回调亦在 worker 内由 `NativeCallable.listener`
  接收后转发回主 isolate。`Aria2NativeSession` 全部 API 改为 `Future<T>`，
  `Aria2InProcessTransport._dispatch` 相应 `await`。worker 自带自适应运行
  循环（活跃 80ms / 空闲 800ms）并在每次变更类 RPC 后立刻 kick 一次，
  无需主 isolate 维护任何 Timer。UI 线程不再因事件循环停顿。
- **macOS 沙盒 / iOS 下载报「Could not contact DNS servers」**：根因是
  aria2 默认使用 c-ares 异步 DNS，沙盒里 `/etc/resolv.conf` 只有 mDNSResponder
  的 loopback stub，c-ares 没有 XPC 通道无法解析。两条 daemon 路径
  （`Aria2ConfigBuilder` / `LibraryDaemon`）默认写入 `async-dns=false`，
  回退到系统 `getaddrinfo`；同时附带 `async-dns-server=1.1.1.1,8.8.8.8,223.5.5.5,119.29.29.29`
  作为用户重新开启异步 DNS 时的兜底。
- **跨平台权限与网络策略**：macOS 沙盒补充 `network.client`、`files.user-selected.read-write`、`files.downloads.read-write`；Android 增加 `network_security_config`、启动前台服务前请求 `POST_NOTIFICATIONS`；iOS 增加 ATS（本地/用户 RPC HTTP）与 `NSLocalNetworkUsageDescription`；Android torrent/metalink 选择使用 `withData` 避免 `path == null`。
- **macOS 启动闪退（io.flutter.ui 线程 SIGSEGV in `SSL_CTX_set_default_verify_paths`）**：根因是
  静态链接的 OpenSSL 3.x 在 macOS 下 `OSSL_PROVIDER_load("legacy")` 走 DSO 路径加载失败，
  aria2 `Platform::setUp` 抛异常但 `initialized_` 标志已置位，二次 `libraryInit` 假成功，
  随后 `SSL_CTX_new` 返回 NULL，aria2 的 `OpenSSLTLSContext` 未守护 NULL 直接 `addSystemTrustedCACerts`。
  改用 **AppleTLS (SecureTransport)** 作为 macOS 上的 TLS 后端，彻底摆脱 OpenSSL 静态 provider 困境。
- **macOS libaria2 链接**：podspec 现链 `Security/CFNetwork/CoreFoundation/SystemConfiguration` framework
  及系统 `expat/zlib/iconv`；不再依赖 OpenSSL 静态库。
- **FFI shim 编译**：将 `b64_decode` / `write_temp` 等返回 `std::string` 的辅助函数移出 `extern "C"` 块，避免 clang 在 macOS 下因 `-Wreturn-type-c-linkage` 报错。
- **`scripts/build_libaria2_macos.sh`**：
  - 切换到 `--without-openssl --with-appletls`，依赖只剩 c-ares / sqlite3；
  - 修复 `build_for_arch` 子函数的 `$(...)` 返回值被 configure/make stdout 污染的隐性 bug
    （所有构建日志显式重定向到 stderr）；
  - 容忍新版 macOS libtool 在 `make libaria2.la` 后处理时偶发的 "File name too long"
    （只要 `src/.libs/libaria2.a` 实际产出即视为成功）；
  - 输出前清理旧的 OpenSSL 残留产物 `deps/libssl.a`、`deps/libcrypto.a`。

### 新增

- **FFI 插件**：`packages/aria2_native` 提供 libaria2 的 C ABI shim + Dart 绑定 + `Aria2NativeSession`（事件流 / 选项 / 查询）。
- **`LibraryDaemon`**：实现 `Aria2Daemon` 抽象，通过 `Aria2InProcessTransport` 把 JSON-RPC 等价请求翻译为 libaria2 调用，使现有 `Aria2Client` / Repository / UI 零改动。
- **构建脚本**：`scripts/build_libaria2_macos.sh`、`_linux.sh`、`_windows.sh`、`_android.sh`、`_ios.sh`，产物落 `packages/aria2_native/prebuilt/<platform>/<arch>/`。
- **CI**：`.github/workflows/build-aria2.yml` 新增 5 套 libaria2 artifact（含 stub 兜底）。
- **文档**：新增 [docs/BUILD_LIBARIA2.md](docs/BUILD_LIBARIA2.md)；重写 [docs/IOS.md](docs/IOS.md)；ARCHITECTURE.md 增加 **ADR-007** 并标记 ADR-001/004 被替代。
- **任务**：长按菜单扩展为 **查看详情 / 打开目录 / 暂停·继续·强制暂停 / 分享**；列表行展示 **errorMessage**（红色提示）。
- **RPC 错误**：`formatRpcError` 识别超时；设置 **导入/远程测试** 失败提示统一友好文案。
- **任务**：长按 **快捷菜单**（GID / URI / 深链）；列表加载失败 **Banner + 重试**；详情展示 **errorMessage**。
- **设置**：保存时 **立即应用下载目录** 到运行中 aria2（`changeGlobalOption`）。
- **日志页**：搜索过滤、复制日志。
- **扩展**：选项页 **Test connection**（`getVersion`）；[docs/EXTENSIONS.md](docs/EXTENSIONS.md)。
- **脚本**：`check_submodule.sh`；CI **每周一** 定时构建。
- **导航**：进行中任务 **角标**（底栏/侧栏）。
- **任务列表**：**粘贴并入队**；批量 **清除已停止记录**（`removeDownloadResult`）；历史 **剪贴板导入**；宽屏 **最大宽度 960**。
- **全局选项**：**复制全部**键值；错误页统一 `formatRpcError`。
- **脚本/文档**：`stage_windows_aria2.ps1`；[docs/QA.md](docs/QA.md) 发版前清单。
- **核心**：`queueUrisToAria2` 统一入队与去重；`formatRpcError` 友好错误提示。
- **任务列表**：剪贴板 **一键跳转新建**；历史 Tab **导出 JSON**；设置 **复制 RPC 地址**。
- **扩展**：右键 **发送当前页面** 到 aria2；`removeDownloadResult` RPC 封装。
- **脚本**：`tag_release.sh`；`build-aria2.yml` 增加 macOS artifact（可选）。
- **任务详情**：按状态 **自适应轮询**（进行中 2s / 暂停 5s / 已结束 10s）。
- **全局选项页**：**搜索**过滤键值。
- **扩展**：共用 `aria2_rpc.js`；Chrome 添加成功/失败 **角标**反馈。
- **Native Messaging**：`install_native_messaging_host.sh` 安装脚本。
- **文档**： [docs/WINDOWS.md](docs/WINDOWS.md)；关于页 **桌面快捷键** 说明；设置 **复制示例深链**。
- **性能**：任务详情/历史 `tellStatus` 使用精简 `keys`；列表轮询 **缓存 aria2 版本**（仅首次/手动刷新拉取）。
- **性能**：任务列表轮询不再拉取 `bitfield` 等大字段；`tellWaiting` 上限 200；WS 事件 **400ms 防抖** + 进行中请求 **合并**，避免重叠 RPC 拖慢 UI。
- **性能**：内嵌库 `aria2_ffi_run_once` **自适应间隔**（活跃 200ms / 空闲 800ms），变更类 RPC 立即唤醒；任务列表 **签名 diff** 跳过无变化的整页重建；移除每行 `Consumer` 包装并将 Theme 与回调上提；任务详情 BT 选项首次后不再重拉、`getPeers` 仅在 Peers Tab 或每 5 轮拉一次。
- **任务列表**：搜索 **250ms 防抖**。
- **桌面快捷键**：⌘/Ctrl+N 打开新建任务。
- **任务详情**：复制 **应用内添加深链**（`/add?uri=`）；[docs/DEEPLINKS.md](docs/DEEPLINKS.md)。
- **新建任务**：宽屏 **双栏布局**（链接 | 操作与高级选项）。
- **Firefox 扩展**：选项页剪贴板导入 RPC JSON（与 Chrome 一致）。
- **CI**：`release.yml` 手动发版校验 + Linux bundle；`prepare_release.sh` 复用 `validate_release.sh`。
- **任务详情**：底部 **暂停 / 继续 / 强制暂停 / 删除 / 重试** 操作栏。
- **深链**：`/add?uri=`、`/add?uris=` 预填新建任务页。
- **RPC 优化**：任务列表 `tell*` 使用精简 `keys`（`task_list_keys.dart`）。
- **设置**：远程 RPC 地址 **快捷预设**（127.0.0.1 / localhost / 0.0.0.0）。
- **Chrome 扩展**：选项页 **从剪贴板导入** aria2down RPC JSON。
- **CI**：macOS 尝试子模块编译 aria2c；**iOS 无签名编译冒烟**。
- **脚本 / 文档**：`scripts/validate_release.sh`、`AGENTS.md`。
- **任务列表**：Tab **数量角标**、空列表 **新建任务** 按钮、长按复制 GID、点击统计条复制全局速度。
- **设置**：**aria2 全局选项** 只读页；本机模式 **复制扩展 RPC 配置**（`rpc.secret`）。
- **CLI / Native Messaging**：`bin/rpc_add_uri.dart`、`bin/native_messaging_host.dart`；`extensions/native-messaging/` 宿主草案。
- **文档**：[docs/DESKTOP.md](docs/DESKTOP.md) 桌面快速参考。
- **设置**：远程 RPC **测试连接**（版本 + WebSocket 探测）。
- **关于页**：显示当前 RPC 地址；本机模式可复制 **RPC Token**。
- **任务**：窄屏 **滑动** 暂停/继续/删除；详情页 **分享/复制** 任务文本。
- **应用**：从后台 **恢复时自动刷新** 任务列表。
- **设置导出**：JSON 含 `appVersion` 与 `exportedAt`。
- **构建/文档**：`build_android_aria2_docker.sh`、`create_github_release.sh`、[docs/IPA.md](docs/IPA.md)；CI Linux 尝试子模块编译 aria2c。
- **扩展**：Native Messaging 方案说明（`extensions/native-messaging/`）。
- **连接**：daemon 启动 **3 次重试**；错误页 **一键切换远程 RPC**；移动/Web **首次欢迎对话框**。
- **新建任务**：跳过队列中 **重复 URI** 并提示跳过数量。
- **设置**：本机日志路径无需启动 daemon（`LocalDaemonPaths`）。
- **构建**：`build_bundle_with_aria2.sh`（编译 + stage + 打包）；`package_msix.sh` + `msix_config`；CI **`build-aria2.yml`** 上传 Linux `aria2c` artifact。
- **扩展**：**Firefox** 草案（`extensions/firefox/`）。
- **任务列表**：WS 连接时轮询降至 30s；进行中按速度、已停止按完成时间排序；**强制全部暂停**、**导出任务快照**（剪贴板 JSON）。
- **设置**：本机模式 **aria2 日志**查看；移动/Web **首次安装默认远程 RPC**。
- **Android**：`Aria2KeepAliveService` 前台服务骨架（`LocalDaemon` 启停联动）。
- **Chrome 扩展草案**：右键链接 `aria2.addUri` + 选项页配置 RPC（`extensions/chrome/`）。
- **URI 智能提取**：从多行文本/剪贴板识别 HTTP(S)/FTP/磁力；**粘贴并添加**一键入队。
- **新建任务**默认使用设置中的下载目录。
- **设置**：**恢复默认**、**关闭 aria2**；全局统计条显示 **已停止** 任务数。
- **任务详情**：复制任务全部下载链接。
- **Web 远程模式**：浏览器端可连接远程 aria2 RPC（本机子进程仍不可用）。
- **连接失败页**：重试、跳转设置；移动/Web **平台提示**横幅。
- **设置**：**当前连接**状态卡片（RPC 地址、WS 是否可用）。
- **桌面快捷键**：⌘/Ctrl+R 刷新任务、⌘/Ctrl+, 打开设置。
- **批量**：删除全部已停止任务。
- **批量任务操作**：全部暂停/继续、清除 aria2 已停止记录；列表显示 **ETA** 与实时速度。
- **新建任务**：**从剪贴板粘贴** 链接。
- **设置**：**立即应用** 全局限速/并发到运行中的 aria2（`changeGlobalOption`）。
- **关于页**：版本、aria2 与 GPLv2 链接（`url_launcher`）。
- **Android 脚手架**：`AndroidBinaryExtractor` + `assets/android/<abi>/aria2c` + `docs/ANDROID.md`。
- **任务历史**：本地 JSON 持久化、任务列表 **「历史」** Tab、WS/轮询自动记录、清空与重试。
- **任务列表**：搜索过滤、下拉刷新、移动端路径复制面板。
- **任务详情**：分块/总体进度条、GID/路径/InfoHash **一键复制**。
- **本机 aria2**：进程异常退出后约 **3 秒自动重启**（保留 session）。
- **远程 RPC 模式**：`RemoteDaemon` + 设置页连接切换（`host:port` / URL + token）。
- **设置增强**：全局/并发限速写入本机 `aria2.conf`、关闭到托盘/最小化到托盘开关、**开机自启**（`launch_at_startup`）。
- **设置导入/导出**：JSON 备份（桌面可另存为文件，其它平台复制到剪贴板）。
- **桌面托盘**：菜单与提示文案接入 l10n；关闭行为可配置（关闭到托盘 vs 直接退出）。

### 变更

- `localDaemonProvider` 由 `aria2DaemonProvider` 统一本地/远程连接（旧名仍 export 兼容）。

### 文档 / 构建

- [docs/BUILD_ARIA2.md](docs/BUILD_ARIA2.md)、[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)；`scripts/print_release_notes.sh`。
- 新增 [docs/IOS.md](docs/IOS.md)（iOS 可行性：推荐远程模式）。
- Linux 打包可选 **AppImage**（`appimagetool`）；CI：**format check**、**macOS/Windows bundle** artifacts。
- `scripts/build_aria2.sh`、`scripts/stage_android_aria2.sh`；`extensions/README.md`（浏览器扩展使用说明）。

---

## [0.1.0] - 未发布

> 对应规划中的 **MVP（Phase 0～3）** 桌面优先版本；**尚未打 Git 标签** 时仍视为未发布。

### 新增

- 本机启动 **aria2c**（`LocalDaemon`）、**JSON-RPC HTTP** 客户端与可选 **WebSocket** 任务刷新。
- **任务列表**（进行中 / 等待 / 已停止）、**新建** HTTP(S)/磁力/.torrent/Metalink、**设置**（主题、语言、默认目录、aria2c 路径）。
- **任务详情**：概览、多文件选择、`tellStatus` BT 字段、**announce 分层**、**peers**、**getOption** 节选（DHT / LPD 等）。
- **国际化**：简体中文 / English。
- **桌面**：在文件管理器中打开下载位置；**Web**：将保存路径复制到剪贴板。
- **构建与 CI**：`scripts/build_desktop.sh`、`package_desktop.sh`、`stage_aria2c.sh`；GitHub Actions **`linux-release-bundle`** 产出带 **同目录 `aria2c`** 的 Linux bundle artifact。
- **命令行示例**：`bin/cli_demo.dart`（需本机 `aria2c`）。

### 说明

- 许可证：**GPLv2+**（与 aria2 一致）；分发二进制须遵守许可证并提供源码获取方式。
- 各平台 **aria2c** 的编译与嵌入策略见 [docs/BUILD.md](docs/BUILD.md)；发版检查清单见 [docs/RELEASE.md](docs/RELEASE.md)。
