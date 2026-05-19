# iOS 平台可行性评估

> 对应规划 **P4-05** / **P4-06**。最后更新：2026-05-19。
> 自 ADR-007 起，iOS 默认引擎与桌面一致 —— **内嵌 libaria2（Dart FFI）**。

## 结论

| 方案 | 可行性 | 状态 |
| --- | --- | --- |
| 本机 `fork` / `exec` 启动 `aria2c` | **不可行** | App Store 与沙盒禁止任意子进程；在 iOS 上自动禁用 |
| **内嵌 libaria2 静态库 + Dart FFI** | **推荐 / 默认** | 见 ADR-007；通过 `packages/aria2_native` 提供 |
| 远程 RPC 模式 | 可行 | 设置中切换；NAS / Mac 上的 aria2 仍可作为替代 |

ADR-001/004 的「iOS 仅远程模式」结论已被 **ADR-007** 替代：iOS 现在直接在应用进程内运行 aria2，免去用户自建 RPC 的负担。

## 沙盒限制下的设计

1. **进程**：`Process.start` 仍被禁；本项目通过 FFI 把 libaria2 静态链接到 Runner，避免子进程。
2. **后台**：`SessionConfig.keepRunning=true` + Dart `Timer.periodic` 驱动 `run(RUN_ONCE)`；后台任务受 iOS 系统调度限制，长时间下载仍建议接入 `URLSession` 或后台任务 API（未来增强）。
3. **文件**：沙盒下载目录为 `Application Support/aria2down/state`，可通过文档选择器把成品挪到用户可见位置。

## 与 Android 的差异

| 项 | Android | iOS |
| --- | --- | --- |
| 引擎 | 默认内嵌 libaria2；子进程模式可作为兜底（NDK 二进制） | 默认内嵌 libaria2；**无子进程兜底** |
| 后台保活 | 前台 Service + 通知 | 系统调度严格；目前仅在前台稳定下载 |
| 打开下载目录 | 部分支持（已存在文件） | 复制路径为主 |

## 编译要点

`scripts/build_libaria2_ios.sh` 交叉编译：

- device(arm64) + simulator(arm64 + x86_64)，目标 SDK 14.0+；
- 依赖（OpenSSL / c-ares / sqlite3）需自行交叉编译或使用 OpenSSL-Universal 等 CocoaPod 静态产物；
- 产物落 `packages/aria2_native/prebuilt/ios/{arm64,sim}/{libaria2.a, deps/*.a}`；
- `ios/aria2_native.podspec` 自动按存在性切换 `ARIA2_FFI_WITH_LIBARIA2` 宏。

更详细的步骤见 [BUILD_LIBARIA2.md](BUILD_LIBARIA2.md)。

## 远程模式（仍可选）

在设置 → 连接方式中选择「远程 RPC」即可与桌面/NAS 上的 aria2 联动；具体配置流程与桌面一致。

- aria2 端：`enable-rpc=true`、`rpc-listen-all`（按需）、`rpc-secret`、`rpc-listen-port=6800`。
- 客户端：网络连通、HTTPS 推荐、ATS 例外（开发时）。

## 参考

- [PLAN.md](../PLAN.md) Phase 4 / Phase 6
- [docs/ARCHITECTURE.md](ARCHITECTURE.md) — ADR-007、`LibraryDaemon`
- [aria2 RPC](https://aria2.github.io/manual/en/html/aria2c.html#rpc-interface)
- [aria2 libaria2 头文件](../third_party/aria2/src/includes/aria2/aria2.h)
