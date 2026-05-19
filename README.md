# aria2down

基于 [aria2](https://github.com/aria2/aria2) 引擎的跨平台下载客户端，使用 Flutter 构建。

> 一份代码，覆盖 **Windows / macOS / Linux / Android / iOS** 五大平台。

---

## 项目状态

🚧 **活跃开发** —— **Phase 3（MVP）收尾中** + **Phase 5 部分已落地**：除任务列表、新建、详情外，已支持 **远程 RPC**、**设置导入/导出**、**托盘/开机自启**、**全局限速与并发** 等。整体进度见 [PLAN.md](PLAN.md)。

**首个面向用户的版本**拟为 **v0.1.0**（与 `pubspec.yaml` 中 `0.1.0` 对齐）；变更摘要见 [CHANGELOG.md](CHANGELOG.md)，打标签与发版自查见 [docs/RELEASE.md](docs/RELEASE.md)。

## 文档

| 文档 | 内容 |
| --- | --- |
| [PLAN.md](PLAN.md) | **项目规划与进度跟踪**（持续更新） |
| [CHANGELOG.md](CHANGELOG.md) | **版本变更记录**（Keep a Changelog） |
| [docs/RELEASE.md](docs/RELEASE.md) | **发版检查清单**（v0.1.0+） |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 系统架构、模块设计、关键流程 |
| [docs/REFERENCES.md](docs/REFERENCES.md) | 参考项目、官方文档、技术资料 |
| [docs/BUILD.md](docs/BUILD.md) | 从源码构建 `aria2c`（各平台） |
| [docs/IOS.md](docs/IOS.md) | **iOS 可行性**（推荐远程 RPC 模式） |
| [docs/ANDROID.md](docs/ANDROID.md) | **Android** 内嵌 aria2 与后台方案 |
| [docs/IPA.md](docs/IPA.md) | **iOS** IPA 构建说明 |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | **开发约定**与常用命令 |
| [docs/BUILD_ARIA2.md](docs/BUILD_ARIA2.md) | 从子模块编译 **aria2c** |
| [docs/MSIX.md](docs/MSIX.md) | **Windows MSIX** 打包 |
| [docs/DESKTOP.md](docs/DESKTOP.md) | 桌面端快速参考 |
| [docs/WINDOWS.md](docs/WINDOWS.md) | **Windows** 内嵌 aria2c / MSIX |
| [docs/DEEPLINKS.md](docs/DEEPLINKS.md) | 应用内 `/add?uri=` 深链 |
| [docs/QA.md](docs/QA.md) | **发版前手动 QA** 清单 |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | 贡献指南 |
| [extensions/README.md](extensions/README.md) | 浏览器扩展 |
| [docs/EXTENSIONS.md](docs/EXTENSIONS.md) | 扩展与桌面端协作 |

## CI 预构建（Linux）

在 GitHub Actions 流水线通过后，可从 **`linux-release-bundle`** 作业下载 artifact **`aria2down-linux-amd64-bundle`**（内含与主程序同目录的 **`aria2c`**，便于内测）。说明见 [docs/BUILD.md](docs/BUILD.md) 与 [docs/RELEASE.md](docs/RELEASE.md)。

## 项目结构

```
aria2down/
├── bin/
│   └── cli_demo.dart     # 命令行：addUri + 轮询 tellStatus（需本机 aria2c）
├── lib/
│   ├── app/              # 主题、路由、主壳（底栏/侧栏）
│   ├── aria2/            # aria2 集成（守护进程、RPC、配置）
│   ├── data/             # 设置模型与持久化
│   ├── features/         # 任务列表、新建、设置等页面
│   ├── l10n/             # ARB 与生成的 `AppLocalizations`
│   └── providers/        # Riverpod providers
├── l10n.yaml             # 代码生成配置
├── third_party/aria2/    # aria2 内核（git submodule）
├── docs/
├── CHANGELOG.md
├── PLAN.md
└── README.md
```

## 快速开始

### 克隆项目（包含子模块）

```bash
git clone --recurse-submodules <repo-url>
cd aria2down
```

如果克隆时未带 `--recurse-submodules`，可在仓库内执行：

```bash
git submodule update --init --recursive
```

### 安装依赖

```bash
flutter pub get
```

修改 `lib/l10n/*.arb` 后执行：`flutter gen-l10n`（或依赖 `flutter pub get` 触发的代码生成）。

### 命令行演示（可选）

本机已安装 `aria2c` 且可在 `PATH` 中找到时：

```bash
dart run bin/cli_demo.dart
# 或指定 URL：
dart run bin/cli_demo.dart https://example.com/file.zip
```

### 运行（开发阶段）

```bash
flutter run -d macos      # macOS
flutter run -d windows    # Windows
flutter run -d linux      # Linux
flutter run -d <android>  # Android
```

> 桌面调试需本机已安装 **aria2**（`aria2c` 在 `PATH` 中）。构建方法见 [docs/BUILD.md](docs/BUILD.md)。

## 技术栈

- **UI**：Flutter (Dart 3.8.1+)，Material 3
- **下载内核**：aria2 1.37.0（git submodule）
- **通信**：JSON-RPC 2.0 over WebSocket / HTTP
- **状态管理**：Riverpod
- **目标平台**：Windows / macOS / Linux / Android / iOS

详细技术选型与架构见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 贡献

1. 阅读 [PLAN.md](PLAN.md) 了解整体规划。
2. 阅读 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 了解架构。
3. 在 WBS 中选择一个 `☐ 待办` 任务；用户可见行为变更请同步 [CHANGELOG.md](CHANGELOG.md) 的 **`[Unreleased]`**。
4. 完成后更新 PLAN.md 中对应任务状态与「项目进度日志」。

## 许可证

本项目静态/动态依赖 [aria2](https://github.com/aria2/aria2)（GPLv2+），因此本项目同样采用 **GPLv2+** 许可证发布。
