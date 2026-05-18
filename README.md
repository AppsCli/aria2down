# aria2down

基于 [aria2](https://github.com/aria2/aria2) 引擎的跨平台下载客户端，使用 Flutter 构建。

> 一份代码，覆盖 **Windows / macOS / Linux / Android / iOS** 五大平台。

---

## 项目状态

🚧 **早期开发阶段** —— 当前处于 Phase 0（准备阶段）。详细进度见下方文档链接。

## 文档

| 文档 | 内容 |
| --- | --- |
| [PLAN.md](PLAN.md) | **项目规划与进度跟踪**（持续更新） |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 系统架构、模块设计、关键流程 |
| [docs/REFERENCES.md](docs/REFERENCES.md) | 参考项目、官方文档、技术资料 |

## 项目结构

```
aria2down/
├── lib/                  # Flutter 应用源码
├── third_party/aria2/    # aria2 内核（git submodule）
├── docs/                 # 详细文档
├── PLAN.md               # 项目规划与进度
└── README.md             # 你正在看的文件
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

### 运行（开发阶段）

```bash
flutter run -d macos      # macOS
flutter run -d windows    # Windows
flutter run -d linux      # Linux
flutter run -d <android>  # Android
```

> 当前阶段尚未集成 aria2 内核运行能力，仅可启动 UI 骨架。集成进度见 [PLAN.md](PLAN.md)。

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
3. 在 WBS 中选择一个 `☐ 待办` 任务。
4. 完成后更新 PLAN.md 中对应任务状态与「项目进度日志」。

## 许可证

本项目静态/动态依赖 [aria2](https://github.com/aria2/aria2)（GPLv2+），因此本项目同样采用 **GPLv2+** 许可证发布。
