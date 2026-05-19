# 贡献指南

感谢关注 **aria2down**。本项目为 Flutter GUI + 内嵌/远程 **aria2**，许可证 **GPLv2+**（与 aria2 兼容）。

## 开发环境

1. [Flutter](https://docs.flutter.dev/get-started/install) stable（Dart 3.8+）
2. 可选：本机 `aria2`（跑集成测试与本地调试）
3. 克隆含子模块：`git clone --recurse-submodules <repo>`

详见 [DEVELOPMENT.md](DEVELOPMENT.md)。

## 提交前检查

```bash
flutter pub get
dart format lib test bin
flutter analyze
flutter test
```

## 规划与任务状态

功能范围与 WBS 见根目录 [PLAN.md](../PLAN.md)。完成用户可见功能时请同步：

- 对应任务状态（`☐` / `◐` / `✅`）
- [CHANGELOG.md](../CHANGELOG.md) `[Unreleased]`
- 必要时补充 `docs/` 与 l10n（`lib/l10n/app_*.arb`）

## 代码风格

- 遵循现有目录：`lib/features/*`、`lib/aria2/*`、`lib/providers/*`
- 新 UI 字符串走 ARB，运行 `flutter gen-l10n`
- 保持 diff 最小，避免无关重构

## 发布

维护者流程见 [RELEASE.md](RELEASE.md) 与 `scripts/prepare_release.sh`。
