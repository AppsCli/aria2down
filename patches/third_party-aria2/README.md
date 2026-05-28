# aria2 本地补丁

上游子模块 [`third_party/aria2`](../../third_party/aria2) 保持干净（指向
`https://github.com/aria2/aria2`），aria2down 的本地修改以 patch 形式存放在此目录。

| 补丁 | 作用 |
| --- | --- |
| `android-openssl-drbg-and-ssl-guards.patch` | Android OpenSSL DRBG 绕路（`Platform.cc` / `SimpleRandomizer.cc`）+ `LibsslTLSContext` null guard；`#ifdef __ANDROID__` 守护，对 macOS / Linux / Windows 编译为 no-op |
| `aria2-public-api-extensions.patch` | 暴露 `aria2::removeDownloadResult` / `purgeDownloadResult` / `getReservedDownload` / `getDownloadResults` 公共 API + `DownloadHandle` 5 个扩展 getter（errorMessage / numSeeders / seeder / verifiedLength / verifyIntegrityPending），并在 `<aria2/aria2.h>` 顶部声明 4 个 `ARIA2DOWN_HAS_*` 特性宏让 FFI shim 编译期探测 |

`scripts/build_libaria2_*.sh` 在 configure 前对子模块工作树应用两个补丁
（`patch -p1 -N`，幂等），编译完成后由各脚本的 trap 自动 `git checkout` 还原，
始终保持 [`third_party/aria2`](../../third_party/aria2) 工作树干净。

升级 aria2 子模块后若 patch 冲突，请 `git -C third_party/aria2 pull` 后在本目录
用 `git diff` 重新生成补丁并更新此 README。
