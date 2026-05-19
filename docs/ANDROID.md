# Android 集成指南

> 对应规划 **P4-01**～**P4-03**。最后更新：2026-05-19。

## 当前实现（脚手架）

- `AndroidBinaryExtractor`：从 `assets/android/<abi>/aria2c` 释放到应用私有目录并 `chmod 755`。
- `BinaryResolver`：在 Android 上优先使用已释放的二进制。
- `scripts/stage_android_aria2.sh`：将 NDK 构建产物拷入 `assets/`。
- 未内嵌二进制时：请使用 **设置 → 远程 RPC**，或在 Termux 等环境自行运行 aria2。

## 构建 aria2c（NDK）

参考上游 `third_party/aria2/Dockerfile.android` 与 [docs/BUILD.md](BUILD.md)。

```bash
# 示例：在具备 Android NDK 的环境交叉编译后
./scripts/stage_android_aria2.sh arm64-v8a /path/to/out/aria2c
flutter build apk --release
```

## 后台保活（P4-03 ◐）

已实现 **前台 Service 骨架**：

- `Aria2KeepAliveService` + `cloud.iothub.aria2down/keep_alive` MethodChannel
- 本机 `LocalDaemon` 启动/停止时由 Dart 调用 `AndroidKeepAlive.start()` / `stop()`
- 通知渠道 `aria2down_daemon`（低优先级、ongoing）

完整保活（与 NDK 内嵌 `aria2c`、电池优化白名单联动）仍待 P4-01 二进制就绪后验证。

## UI（P4-04）

- 已使用 `SafeArea` 包裹主导航内容。
- 窄屏沿用底栏；任务列表支持搜索、历史 Tab 与下拉刷新。

## 权限

在 `AndroidManifest.xml` 中按需声明网络、存储（若支持用户自选下载目录）等权限；具体以发版前清单为准。
