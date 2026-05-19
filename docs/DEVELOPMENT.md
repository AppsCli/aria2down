# 开发约定

## 环境

- Flutter **stable**（Dart 3.8+）
- 桌面调试：本机 `aria2c` 在 `PATH` 中，或设置页指定路径
- Web 调试：仅 **远程 RPC**（`flutter run -d chrome` + 设置远程地址）

## 常用命令

```bash
flutter pub get
flutter gen-l10n    # 修改 lib/l10n/*.arb 后
flutter analyze
flutter test
flutter run -d macos
dart run bin/cli_demo.dart
```

## 架构要点

| 层 | 目录 |
| --- | --- |
| UI | `lib/features/` |
| aria2 | `lib/aria2/`（`LocalDaemon` / `RemoteDaemon`、`Aria2Client`） |
| 状态 | `lib/providers/`（Riverpod） |
| 持久化 | `lib/data/` |

- 任务刷新：WS 通知 + 8s 轮询；`taskRefreshSignalProvider` 供快捷键触发。
- 任务历史：`TaskHistoryRecorder` → `TaskHistoryRepository`（JSON）。

## 提交前

```bash
./scripts/prepare_release.sh   # 或至少 analyze + test
```

## 子模块

```bash
git submodule update --init --recursive
```

aria2 源码在 `third_party/aria2`；编译见 [BUILD.md](BUILD.md)。
