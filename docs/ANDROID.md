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
- 窄屏沿用底栏；任务列表支持搜索、历史 Tab、下拉刷新、滑动操作与添加 FAB。
- 设置页底部固定保存按钮；首次安装默认本机内嵌引擎（可改远程 RPC）。
- 应用进入后台时任务轮询间隔延长至 60s，恢复前台时立即刷新。

## 权限

| 权限 / 配置 | 用途 |
| --- | --- |
| `INTERNET` | 下载与远程 RPC |
| `ACCESS_NETWORK_STATE` | 网络状态 |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC` | 本机引擎前台保活（Android 14+ 类型） |
| `POST_NOTIFICATIONS` | Android 13+ 前台服务通知；`MainActivity` 在启动保活前请求 |
| `WAKE_LOCK` | 保活辅助 |
| `res/xml/network_security_config.xml` | 允许用户配置的 HTTP RPC（如局域网 NAS） |
| 存储 | 默认使用应用私有目录；自选目录走 SAF / `file_selector`，无需 `READ/WRITE_EXTERNAL_STORAGE` |
| Torrent / Metalink | `file_picker` 使用 `withData: true`，避免 Android 上 `path == null` |
