# aria2down — Agent 指南

Flutter 跨平台 aria2 GUI。Dart 3.8+，Riverpod，`go_router`，Material 3。

## 常用命令

```bash
flutter pub get
flutter gen-l10n
dart format lib test bin
flutter analyze
flutter test
./scripts/validate_release.sh
```

## 架构要点

- **连接**：`lib/providers/aria2_daemon_provider.dart` 按 `LocalEngine` + `ConnectionMode` 选择 `LibraryDaemon`（默认）/ `LocalDaemon`（子进程兜底）/ `RemoteDaemon`。
- **库引擎**：`packages/aria2_native/` 是独立 FFI 插件（`src/aria2_ffi.{h,cc}` + Dart 绑定）；`lib/aria2/daemon/library_daemon.dart` + `lib/aria2/client/in_process_transport.dart` 桥接到 `Aria2Client`。
- **RPC**：`lib/aria2/client/aria2_client.dart`；列表轮询使用 `lib/core/task_list_keys.dart` 的 `keys` 减负。
- **入队**：`lib/core/queue_uris.dart`（去重 + `addUri`）；错误文案 `lib/core/rpc_error_message.dart`。
- **路由**：`lib/app/router.dart` — `/tasks`、`/add?uri=`、`/settings`；深链见 [docs/DEEPLINKS.md](docs/DEEPLINKS.md)。
- **规划**：`PLAN.md` WBS；用户可见变更同步 `CHANGELOG.md` [Unreleased]；架构决策见 `docs/ARCHITECTURE.md` ADR 表（当前最新 ADR-008）。

## 修改约定

- 新 UI 文案写入 `lib/l10n/app_en.arb` 与 `app_zh.arb`，避免重复 key。
- 设置页 **不要** 在 `build` 中 `watch(aria2DaemonProvider)`（会破坏 widget 测试）。
- 未经用户明确要求 **不要** `git commit` / `git push`。
- aria2 任务 URI 在 RPC 中为 `files[].uris[]` 或 `{'uri': '...'}` 结构，见 `lib/core/reveal_path.dart`。
- 修改 `packages/aria2_native/src/aria2_ffi.h` 时，请同步 `packages/aria2_native/lib/src/bindings.dart` 中的 lookupFunction 签名。

## 扩展

- Chrome：`extensions/chrome/` — 选项页可从剪贴板导入 aria2down 复制的 RPC JSON。
- Native Messaging 草案：`extensions/native-messaging/`、`bin/native_messaging_host.dart`。
