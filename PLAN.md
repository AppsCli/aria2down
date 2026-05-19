# aria2down 项目规划文档

> 本文档为 `aria2down` 项目的总体规划与进度跟踪文档。
> **维护规则**：每完成一个任务/里程碑，请更新对应任务的状态（`☐ 待办` / `◐ 进行中` / `✅ 完成` / `⚠ 阻塞` / `✗ 取消`），并在「项目进度日志」中追加一条记录。
> 最后更新时间：2026-05-19

---

## 目录

1. [项目概述](#1-项目概述)
2. [目标与非目标](#2-目标与非目标)
3. [技术选型](#3-技术选型)
4. [系统架构](#4-系统架构)
5. [模块拆分](#5-模块拆分)
6. [功能需求清单](#6-功能需求清单)
7. [非功能需求](#7-非功能需求)
8. [开发里程碑与阶段计划](#8-开发里程碑与阶段计划)
9. [详细任务分解（WBS）](#9-详细任务分解wbs)
10. [测试策略](#10-测试策略)
11. [风险与缓解措施](#11-风险与缓解措施)
12. [发布计划](#12-发布计划)
13. [项目进度](#13-项目进度)
14. [项目进度日志](#14-项目进度日志)

---

## 1. 项目概述

### 1.1 项目名称

**aria2down** — 基于 aria2 引擎的跨平台下载客户端。

### 1.2 项目定位

`aria2down` 是一款使用 Flutter 构建的跨平台下载客户端 GUI（桌面 + 移动），底层下载内核直接复用 [aria2](https://github.com/aria2/aria2) 项目（以 Git 子模块的方式集成在 `third_party/aria2`）。

通过将 **强大的下载内核（aria2）** 与 **现代化的跨平台 UI（Flutter）** 结合，目标是打造一款：

- 支持 HTTP / HTTPS / FTP / SFTP / BitTorrent / Metalink 多协议
- 多线程、多源、断点续传
- 跨 Windows / macOS / Linux / Android / iOS 五个平台
- 美观、易用、性能优秀的下载工具

### 1.3 与现有项目对比

| 项目 | 平台 | UI 框架 | 与本项目差异 |
| --- | --- | --- | --- |
| Motrix | Win/Mac/Linux | Electron + Vue | 仅桌面，体积较大 |
| AriaNg | Web | AngularJS | 纯前端，需自行启动 aria2 |
| aria2android | Android | 原生 | 仅 Android |
| Downloader (chenmozhijin) | Android | Java/Kotlin | 仅 Android |
| **aria2down** | 全平台 | Flutter | 同一份代码覆盖桌面 + 移动 |

---

## 2. 目标与非目标

### 2.1 项目目标（MVP）

- ✅ 集成 aria2 作为下载内核
- ✅ 通过 JSON-RPC 与 aria2 进程通信
- ✅ 提供任务管理界面：新增 / 暂停 / 继续 / 删除 / 重试
- ✅ 支持 HTTP/HTTPS、磁力链、torrent 文件、Metalink
- ✅ 桌面平台优先（Windows / macOS / Linux），移动平台次之
- ✅ 一键启动 / 停止 aria2 后端（不需要用户手动配置）

### 2.2 长期目标

- 浏览器扩展捕获下载链接并发送到 aria2down
- 远程模式：连接到外部 aria2 服务器（NAS、RaspberryPi 等）
- 下载完成后挂载预览（图片、视频、音频）
- 自动分类目录（按文件类型、按域名）
- 多账号 / Cookie 管理（支持需要登录的下载源）
- 速度限制 / 计划任务 / 时段控制

### 2.3 非目标

- ❌ 不重新实现下载协议（继续依赖 aria2）
- ❌ 不做 P2P 文件分享（仅做下载客户端）
- ❌ 不在 MVP 阶段提供云端同步任务功能

---

## 3. 技术选型

### 3.1 客户端

| 类别 | 选型 | 理由 |
| --- | --- | --- |
| UI 框架 | Flutter (Dart 3.8.1+) | 一份代码 5 平台 |
| 状态管理 | `riverpod` 或 `provider` + `flutter_hooks` | Riverpod 更现代、可测试性更好 |
| 路由 | `go_router` | 官方推荐 |
| 持久化 | `shared_preferences` + `path_provider`，复杂结构使用 `isar` 或 `drift` | 任务历史、配置存储 |
| HTTP / RPC 客户端 | `dio` + `web_socket_channel` | aria2 JSON-RPC over HTTP / WebSocket |
| 国际化 | `flutter_localizations` + `intl` | 中英文双语 |
| 主题 | Material 3，支持暗色 | 美观一致 |
| 文件选择 | `file_selector` / `file_picker` | 选择保存目录、torrent 文件 |
| 系统集成 | `tray_manager`、`window_manager`、`launch_at_startup` | 桌面托盘、窗口、自启 |

### 3.2 下载内核

| 项 | 内容 |
| --- | --- |
| 内核 | aria2 1.37.0（或后续 release） |
| 集成方式 | Git 子模块 `third_party/aria2` |
| 通信方式 | JSON-RPC over HTTP/WebSocket（aria2c 启用 `--enable-rpc`） |
| 启动方式 | 桌面：随应用启动同目录下的 `aria2c` 进程；移动：内嵌二进制并通过 `Process.start` 启动 |

### 3.3 构建与编译

| 平台 | aria2 编译 | 备注 |
| --- | --- | --- |
| macOS | autotools + Homebrew 依赖（openssl/libssh2/c-ares）| 产出 `aria2c` 可执行 |
| Linux | autotools | 产出 `aria2c` |
| Windows | mingw-w64 / MSVC，参考 `Dockerfile.mingw` | 产出 `aria2c.exe` |
| Android | NDK + `Dockerfile.android` 提供的交叉编译方案 | 产出 ARM/ARM64/x86_64 |
| iOS | autotools + iOS toolchain（受限于沙盒，需评估可行性）| 可能需要降级为远程模式 |

> **注意**：iOS 沙盒限制 fork/exec，需要评估是否使用 aria2 作为静态库 + 直接调用 main()，或在 MVP 阶段仅支持远程连接外部 aria2 服务器。

---

## 4. 系统架构

### 4.1 架构图

```
┌──────────────────────────────────────────────────────────┐
│                     Flutter UI 层 (Dart)                 │
│  ┌────────────┐ ┌────────────┐ ┌────────────────────┐    │
│  │ 任务列表页 │ │  设置页    │ │ 新建任务 / 详情页  │    │
│  └────────────┘ └────────────┘ └────────────────────┘    │
└───────────────────────┬──────────────────────────────────┘
                        │ Riverpod / Provider
┌───────────────────────┴──────────────────────────────────┐
│                  应用服务层 (Dart)                       │
│  ┌─────────────┐ ┌─────────────┐ ┌────────────────────┐  │
│  │ TaskService │ │ConfigService│ │ DownloadHistoryRepo│  │
│  └─────────────┘ └─────────────┘ └────────────────────┘  │
└───────────────────────┬──────────────────────────────────┘
                        │
┌───────────────────────┴──────────────────────────────────┐
│              aria2 客户端层 (Aria2Client.dart)           │
│  - JSON-RPC 调用封装：addUri / tellStatus / pause / ...  │
│  - WebSocket 订阅推送                                    │
│  - 事件解析（onDownloadStart / Complete / Error ...）    │
└───────────────────────┬──────────────────────────────────┘
                        │ JSON-RPC over WS / HTTP
┌───────────────────────┴──────────────────────────────────┐
│            aria2 进程管理层 (Aria2Daemon.dart)           │
│  - 启动 / 停止 aria2c 子进程                             │
│  - 健康检查、自动重启                                    │
│  - 工作目录、配置文件、Token 生成                        │
└───────────────────────┬──────────────────────────────────┘
                        │ Process.start / kill
┌───────────────────────┴──────────────────────────────────┐
│            aria2c 二进制（third_party/aria2 编译产物）   │
│       --enable-rpc --rpc-listen-all=false ...           │
└──────────────────────────────────────────────────────────┘
```

### 4.2 关键设计决策

1. **进程隔离**：aria2c 作为独立子进程运行，崩溃不会影响 UI 进程。
2. **本地回环 + Token**：RPC 仅监听 `127.0.0.1`，使用随机生成的 secret token，避免本机其他进程嗅探。
3. **WebSocket 推送优先**：状态更新使用 aria2 的 WS 通知接口（`aria2.onDownloadStart` 等），减少轮询。
4. **配置外置**：`aria2.conf` 由应用动态生成到用户目录，避免污染二进制目录。
5. **远程模式扩展点**：`Aria2Daemon` 提供 `LocalDaemon` 与 `RemoteDaemon` 两种实现，便于未来连接外部 aria2 服务器。

详细架构说明见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

---

## 5. 模块拆分

```
lib/
├── main.dart                    # 应用入口
├── app/                         # MaterialApp / 主题 / 路由
│   ├── app.dart
│   ├── theme.dart
│   └── router.dart
├── core/                        # 通用工具
│   ├── constants.dart
│   ├── logger.dart
│   ├── utils/
│   └── platform/                # 平台相关辅助
├── data/                        # 数据层
│   ├── models/                  # 数据模型 (Task, GlobalStat, ...)
│   ├── repositories/
│   └── local/                   # 本地存储
├── aria2/                       # aria2 集成层（核心）
│   ├── client/                  # JSON-RPC 客户端
│   │   ├── aria2_client.dart
│   │   ├── rpc_methods.dart
│   │   ├── ws_listener.dart
│   │   └── http_transport.dart
│   ├── daemon/                  # 进程管理
│   │   ├── aria2_daemon.dart
│   │   ├── local_daemon.dart
│   │   └── remote_daemon.dart
│   ├── binary/                  # 二进制资源管理
│   │   └── binary_resolver.dart
│   └── config/                  # 配置生成
│       └── aria2_config_builder.dart
├── features/                    # 业务特性
│   ├── tasks/                   # 任务相关
│   │   ├── presentation/        # 页面 + Widget
│   │   ├── application/         # Riverpod controllers
│   │   └── domain/              # 实体/服务
│   ├── new_task/                # 新建任务（URL/磁力/torrent）
│   ├── settings/                # 设置页
│   └── about/                   # 关于页
└── l10n/                        # 国际化
```

```
third_party/
└── aria2/                       # aria2 git 子模块
```

```
build_resources/
├── ios/                         # iOS 编译脚本（占位）
├── android/                     # Android 编译脚本
├── macos/
├── windows/
└── linux/
```

```
docs/
├── ARCHITECTURE.md              # 架构详解
├── REFERENCES.md                # 参考项目与资料
├── BUILD.md                     # 各平台编译指南
└── DEVELOPMENT.md               # 开发约定
```

---

## 6. 功能需求清单

### 6.1 MVP（v0.1.0）

| 编号 | 功能 | 描述 |
| --- | --- | --- |
| F-01 | aria2 进程托管 | 应用启动时自动启动 aria2c，退出时自动停止 |
| F-02 | RPC 通信 | 实现核心 RPC：`addUri`、`addTorrent`、`addMetalink`、`tellActive`、`tellWaiting`、`tellStopped`、`pause`、`unpause`、`remove`、`getGlobalStat` |
| F-03 | 任务列表 | 三个 tab：进行中 / 等待中 / 已完成；展示进度条、速度、ETA |
| F-04 | 新建任务 | URL 输入框、批量粘贴、Torrent/Metalink 文件选择 |
| F-05 | 任务操作 | 暂停 / 继续 / 删除 / 重试 / 打开所在目录 |
| F-06 | 全局统计 | 顶部展示总下载/上传速度、活动数、等待数 |
| F-07 | 设置：基本 | 默认下载目录、最大并发、单任务连接数、限速 |
| F-08 | 设置：aria2 | RPC 端口、Token、临时目录 |
| F-09 | 主题 | 浅色 / 深色 / 跟随系统 |
| F-10 | 国际化 | 简体中文 + 英文 |

### 6.2 v0.2.0

| 编号 | 功能 |
| --- | --- |
| F-11 | 任务详情：分块、文件、Tracker 列表 |
| F-12 | BT 任务：选择文件 |
| F-13 | 系统托盘 + 关闭到托盘 |
| F-14 | 自启动 |
| F-15 | 配置导入/导出 |
| F-16 | 任务历史持久化（即使 aria2 重启也能看到记录） |

### 6.3 v0.3.0+

| 编号 | 功能 |
| --- | --- |
| F-20 | 远程模式（连接外部 aria2 服务器） |
| F-21 | 浏览器扩展 + native messaging |
| F-22 | 计划任务 / 时段限速 |
| F-23 | 多账号 Cookie 管理 |
| F-24 | 文件预览（图片/视频/音频） |

---

## 7. 非功能需求

| 维度 | 指标 |
| --- | --- |
| 性能 | 任务列表 1000 条以内滚动 60fps |
| 启动 | 冷启动 < 2s（不含 aria2 进程） |
| 体积 | 单平台安装包 < 60MB（含 aria2 二进制） |
| 稳定 | aria2 进程崩溃后 5s 内自动重启并恢复任务 |
| 可观测 | 完整日志（UI 操作、RPC 请求、aria2 stderr） |
| 兼容 | macOS 11+、Windows 10+、Ubuntu 20.04+、Android 7+、iOS 14+ |

---

## 8. 开发里程碑与阶段计划

> 时间均为相对周数（W1 = 第 1 周），实际进度以 [项目进度](#13-项目进度) 为准。

### Phase 0 — 准备（W1）

- 初始化 Git 仓库
- 添加 aria2 子模块
- 编写规划文档（PLAN / ARCHITECTURE / REFERENCES）
- 搭建 CI 骨架（lint + test）

### Phase 1 — 内核打通（W2 ~ W3）

- 在 macOS / Linux 上手动编译 aria2c
- 编写 `Aria2Daemon`：启动、停止、健康检查
- 编写 `Aria2Client`：JSON-RPC over HTTP / WebSocket
- 命令行 demo：通过 Dart 控制台触发 `addUri` 并打印进度

### Phase 2 — 基础 UI（W4 ~ W5）

- 主题、路由、Riverpod 骨架
- 任务列表页（三 tab）
- 新建任务页（URL）
- 全局统计条
- 设置页 v1

### Phase 3 — 完整功能 MVP（W6 ~ W7）

- Torrent / Metalink 任务
- 任务操作（暂停/继续/删除/重试/打开目录）
- 国际化、深色模式
- 桌面三平台打包脚本

### Phase 4 — 移动端（W8 ~ W10）

- Android：NDK 交叉编译 aria2、内嵌二进制、Process 启动
- 移动 UI 适配
- iOS：可行性评估（必要时降级为远程模式）

### Phase 5 — 增强功能（W11+）

- 任务详情、BT 文件选择
- 托盘 / 自启
- 远程模式
- 文档完善、首个 Release

### Phase 6 — libaria2 全平台库化（ADR-007，W12+）

- 在五个原生平台默认改用 Dart FFI 内嵌 `libaria2`
- `LocalDaemon`（aria2c 子进程）降级为兜底/调试通道
- iOS 真正支持本机下载（不再仅远程模式）
- 同步更新构建链、CI、文档

---

## 9. 详细任务分解（WBS）

> 状态约定：`☐ 待办` / `◐ 进行中` / `✅ 完成` / `⚠ 阻塞` / `✗ 取消`

### 9.0 准备（Phase 0）

| ID | 任务 | 状态 |
| --- | --- | --- |
| P0-01 | 初始化 git 仓库 | ✅ 完成 |
| P0-02 | 添加 aria2 子模块到 `third_party/aria2` | ✅ 完成 |
| P0-03 | 编写 `PLAN.md` | ✅ 完成 |
| P0-04 | 编写 `docs/ARCHITECTURE.md` | ✅ 完成 |
| P0-05 | 编写 `docs/REFERENCES.md` | ✅ 完成 |
| P0-06 | 编写 `docs/BUILD.md`（aria2 编译指南） | ✅ 完成 |
| P0-07 | 完善 `.gitignore`（构建产物、IDE 文件等） | ✅ 完成 |
| P0-08 | 提交首个 commit | ✅ 完成 |
| P0-09 | 配置 GitHub Actions：`flutter analyze` + `flutter test` | ✅ 完成 |
| P0-10 | 添加 LICENSE（GPLv2，与 aria2 兼容） | ✅ 完成 |

### 9.1 内核打通（Phase 1）

| ID | 任务 | 状态 |
| --- | --- | --- |
| P1-01 | 在 macOS 上编译 aria2c 1.37.0（autotools） | ◐ 进行中（`build-aria2.yml` **macos-aria2c** artifact；本地 `build_aria2.sh`） |
| P1-02 | 在 Linux 上编译 aria2c | ◐ 进行中（同上） |
| P1-03 | 设计 `Aria2Daemon` 抽象接口 | ✅ 完成 |
| P1-04 | 实现 `LocalDaemon`：`Process.start`、stdout/stderr 重定向、`kill` | ✅ 完成 |
| P1-05 | 配置生成器：动态生成 `aria2.conf` 写入用户目录 | ✅ 完成 |
| P1-06 | RPC Token 随机生成与持久化 | ✅ 完成 |
| P1-07 | `Aria2Client` HTTP 传输层（基于 `dio`） | ✅ 完成 |
| P1-08 | `Aria2Client` WebSocket 传输层 | ✅ 完成（WS **通知**已用于任务刷新；RPC  intentionally 保持 HTTP，设计见 ARCHITECTURE） |
| P1-09 | 封装 RPC 方法：`addUri/addTorrent/addMetalink` | ✅ 完成 |
| P1-10 | 封装 RPC 方法：`tellActive/tellWaiting/tellStopped/tellStatus` | ✅ 完成 |
| P1-11 | 封装 RPC 方法：`pause/unpause/remove/forceRemove` | ✅ 完成 |
| P1-12 | 封装 RPC 方法：`getGlobalStat/getOption/changeOption` | ✅ 完成 |
| P1-13 | WS 事件订阅：`onDownloadStart/Complete/Error/Pause/Stop` | ✅ 完成 |
| P1-14 | 单元测试：mock JSON-RPC server + Aria2Client | ✅ 完成 |
| P1-15 | 集成测试：使用真实 aria2c + 临时 HTTP server 完成下载 | ✅ 完成 |
| P1-16 | 命令行 demo：`bin/cli_demo.dart` 演示 addUri 并轮询打印进度 | ✅ 完成 |

### 9.2 基础 UI（Phase 2）

| ID | 任务 | 状态 |
| --- | --- | --- |
| P2-01 | 引入 `riverpod`、`go_router`、`dio`、`web_socket_channel` | ✅ 完成 |
| P2-02 | Material 3 主题 + 浅色/深色切换 | ✅ 完成 |
| P2-03 | 应用骨架：底栏 / 侧栏（桌面） | ✅ 完成 |
| P2-04 | 任务列表页：三 tab + 进度条 | ✅ 完成 |
| P2-05 | 任务列表自动刷新（订阅 WS） | ✅ 完成 |
| P2-06 | 新建任务页：URL 输入 + 高级选项（Header/Cookie/限速） | ✅ 完成 |
| P2-07 | 全局统计条（顶部） | ✅ 完成 |
| P2-08 | 设置页：基本 + aria2 配置 | ✅ 完成 |
| P2-09 | 国际化：zh / en | ✅ 完成 |
| P2-10 | 输入校验、错误提示、空态、加载态 | ✅ 完成 |
| P2-11 | Widget 测试：核心 widgets | ✅ 完成 |

### 9.3 完整 MVP（Phase 3）

| ID | 任务 | 状态 |
| --- | --- | --- |
| P3-01 | Torrent 文件添加 | ✅ 完成 |
| P3-02 | Metalink 文件添加 | ✅ 完成 |
| P3-03 | 任务操作：暂停/继续/删除/重试 | ✅ 完成 |
| P3-04 | 打开所在目录（各平台） | ✅ 完成（桌面文件管理器；移动/Web **复制路径** + 底部 sheet；系统限制下无法「仅打开空目录」已文档化） |
| P3-05 | 桌面打包：macOS（dmg）、Windows（msix/exe）、Linux（AppImage） | ◐ 进行中（dmg / tar.gz / zip / 可选 AppImage；**MSIX**：`msix_config` + `package_msix.sh` + [docs/MSIX.md](docs/MSIX.md)） |
| P3-06 | 安装包内嵌 aria2c 二进制 | ◐ 进行中（Linux/macOS CI **优先子模块 `build_aria2.sh`**；Windows **choco + [docs/WINDOWS.md](docs/WINDOWS.md)**；静态链接仍待） |
| P3-07 | 自动化构建脚本 | ✅ 完成（`scripts/build_desktop.sh`：analyze + test + `flutter build`） |
| P3-08 | v0.1.0 发布 | ◐ 进行中（`tag_release.sh`、`release.yml`；**Git tag / GitHub Release** 仍待维护者执行） |

### 9.4 移动端（Phase 4）

| ID | 任务 | 状态 |
| --- | --- | --- |
| P4-01 | Android NDK 交叉编译 aria2（armeabi-v7a / arm64-v8a / x86_64） | ◐ 进行中（`build_android_aria2_docker.sh` + upstream Dockerfile.android） |
| P4-02 | 将二进制打包到 `assets/`，运行时拷贝到应用私有目录并赋可执行权限 | ◐ 进行中（`AndroidBinaryExtractor`、`stage_android_aria2.sh`、`assets/android/`；需 NDK 产物） |
| P4-03 | Android 后台 Service：保持 aria2c 存活 | ◐ 进行中（`Aria2KeepAliveService` + `AndroidKeepAlive`；与 NDK 二进制联调仍待） |
| P4-04 | 移动端 UI 适配 | ◐ 进行中（`SafeArea`、平台提示、欢迎对话框；新建/任务列表宽屏约束；默认远程 RPC） |
| P4-05 | iOS 可行性评估报告 | ✅ 完成（[docs/IOS.md](docs/IOS.md)） |
| P4-06 | iOS 集成方式确定（静态库 / 远程模式） | ✅ 完成（MVP 推荐 **远程 RPC**，见 IOS.md） |
| P4-07 | 移动端打包：apk / ipa | ◐ 进行中（CI **`android-apk`** + **`ios-build-smoke`**；[docs/IPA.md](docs/IPA.md) 说明 ipa 构建） |

### 9.5 增强功能（Phase 5）

| ID | 任务 | 状态 |
| --- | --- | --- |
| P5-01 | 任务详情页：分块/文件/Tracker | ✅ 完成（分块进度条、复制 GID/路径/InfoHash、BT 详情既有能力；单 Tracker 健康仍无 RPC） |
| P5-07 | 任务历史持久化（drift / isar） | ✅ 完成（JSON 文件 + 历史 Tab + `TaskHistoryRecorder`） |
| P5-02 | BT 任务文件选择 | ✅ 完成（新建多文件种子：解析 bencode 弹出勾选 + `addTorrent` 传 `select-file`；任务详情页 `changeOption` 调整） |
| P5-03 | 系统托盘 + 最小化到托盘 | ✅ 完成（`desktop_shell_io` + 设置项 `closeToTray` / `minimizeToTray` + l10n 托盘菜单） |
| P5-04 | 开机自启 | ✅ 完成（`launch_at_startup` + 设置开关） |
| P5-05 | 远程模式 UI + 实现 `RemoteDaemon` | ✅ 完成（`aria2DaemonProvider`、设置页本机/远程切换） |
| P5-06 | 配置导入 / 导出 | ✅ 完成（`SettingsExport` JSON + 设置页导入/导出） |
| P5-08 | 浏览器扩展（v0.4+） | ◐ 进行中（**Test connection**、发送页面/链接、NM 安装脚本；[docs/EXTENSIONS.md](docs/EXTENSIONS.md)） |

### 9.6 libaria2 全平台库化（Phase 6 / ADR-007）

| ID | 任务 | 状态 |
| --- | --- | --- |
| P6-01 | FFI 插件脚手架 [packages/aria2_native](packages/aria2_native/) | ✅ 完成 |
| P6-02 | C ABI shim：`packages/aria2_native/src/aria2_ffi.{h,cc}` | ✅ 完成 |
| P6-03 | Dart 绑定 + `Aria2NativeSession` + 事件桥 | ✅ 完成 |
| P6-04 | `Aria2InProcessTransport`（JSON-RPC ⇄ libaria2 调用翻译） | ✅ 完成 |
| P6-05 | [`LibraryDaemon`](lib/aria2/daemon/library_daemon.dart) + Provider 引擎分支 | ✅ 完成 |
| P6-06 | `AppSettings.LocalEngine` / `fallbackToSubprocess` + 设置 UI + zh/en arb | ✅ 完成 |
| P6-07 | macOS 构建脚本 [scripts/build_libaria2_macos.sh](scripts/build_libaria2_macos.sh)（universal） | ✅ 完成（脚本就绪；首轮 CI 跑通待维护者验证） |
| P6-08 | Linux 构建脚本 | ✅ 完成 |
| P6-09 | Windows 构建脚本（mingw-w64 / Docker） | ✅ 完成 |
| P6-10 | Android 构建脚本（NDK / Docker，三 ABI） | ✅ 完成 |
| P6-11 | iOS 构建脚本（device + simulator） | ✅ 完成（OpenSSL 依赖仍需手动放入 deps/） |
| P6-12 | CI 集成（`build-aria2.yml` 新增 5 套 libaria2 artifact） | ✅ 完成 |
| P6-13 | ADR-007 / `docs/IOS.md` 重写 / [docs/BUILD_LIBARIA2.md](docs/BUILD_LIBARIA2.md) | ✅ 完成 |
| P6-14 | 集成测试拆分 subprocess / library 两套 | ◐ 进行中 |
| P6-15 | Widget 测试覆盖「引擎切换」 | ◐ 进行中 |

---

## 10. 测试策略

| 层级 | 工具 | 覆盖目标 |
| --- | --- | --- |
| 单元测试 | `flutter_test`（可选 `mocktail`） | `Aria2Client` JSON-RPC、配置生成等 |
| Widget 测试 | `flutter_test` | 核心页面渲染、交互 |
| 集成测试 | `integration_test` + 真实 aria2c | 端到端下载小文件 |
| 手动测试 | — | 各平台烟雾测试、长时间下载、网络异常 |
| 性能 | DevTools | 列表滚动、内存占用 |
| 静态检查 | `flutter analyze`、`dart format --set-exit-if-changed` | CI 强制 |

---

## 11. 风险与缓解措施

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| iOS 沙盒不允许 fork/exec | 无法启动 aria2c 子进程 | 评估静态库方案 / 在 MVP 阶段降级为远程模式 |
| 各平台 aria2 编译复杂 | 阻塞发版 | 使用 aria2 项目自带 Dockerfile（`Dockerfile.android`/`Dockerfile.mingw`），并写入 `docs/BUILD.md` |
| aria2 二进制与 OpenSSL 等动态库依赖问题 | 桌面用户无法运行 | 静态链接（`--enable-static` + 静态依赖）或随包分发依赖 |
| Android 后台进程被系统杀死 | 下载中断 | 使用前台 Service + 通知 |
| 许可证冲突（aria2 GPLv2） | 法律风险 | 本项目同样采用 GPLv2 / GPLv2+ 许可证 |
| RPC 安全：本地 token 泄漏 | 其他本机进程操作下载任务 | 仅监听回环、随机长 token、文件权限 0600 |
| Flutter 桌面成熟度（尤其 Linux） | 部分场景 bug | 关注官方 stable 通道、避免冷门插件 |

---

## 12. 发布计划

| 版本 | 内容 | 目标日期 |
| --- | --- | --- |
| v0.1.0 (MVP) | Phase 0~3 全部完成，桌面三平台 | 待定 |
| v0.2.0 | Phase 5 部分（任务详情、托盘、自启） | 待定 |
| v0.3.0 | Phase 4（Android），远程模式 | 待定 |
| v1.0.0 | 全平台稳定，包含浏览器扩展 | 待定 |

---

## 13. 项目进度

> **总体进度**：约 **89%**（WBS：已完成 65 / 共 75 项；进行中 9）
> 上次更新：2026-05-19

### 阶段进度概览

| Phase | 任务总数 | 已完成 | 进行中 | 待办 | 完成率（约） |
| --- | --- | --- | --- | --- | --- |
| Phase 0 — 准备 | 10 | 10 | 0 | 0 | 100% |
| Phase 1 — 内核打通 | 16 | 14 | 2 | 0 | 88% |
| Phase 2 — 基础 UI | 11 | 11 | 0 | 0 | 100% |
| Phase 3 — MVP | 8 | 5 | 3 | 0 | 62% |
| Phase 4 — 移动端 | 7 | 2 | 5 | 0 | 29% |
| Phase 5 — 增强 | 8 | 7 | 1 | 0 | 88% |
| Phase 6 — libaria2 FFI | 15 | 13 | 2 | 0 | 87% |
| **合计** | **75** | **65** | **10** | **0** | **89%** |

### 当前焦点

- **Phase 6 收尾**：P6-14 集成测试 library 通路、P6-15 引擎切换 widget 测试，并在 CI 中跑通各平台 libaria2 构建。
- **Phase 3 收尾**：P3-04 移动端「仅打开目录」；P3-05 msix/AppImage；P3-06 macOS/Windows CI 与静态链接；**P3-08** 打 tag / GitHub Release
- **Phase 1**：P1-01 / P1-02 本机编译 aria2c（Phase 6 已替代主要路径，但子进程兜底仍依赖此通道）
- **Phase 5**：P5-08 浏览器扩展；Phase 4 Android 内嵌 aria2

---

## 14. 项目进度日志

> 每完成一个有意义的工作单元（任务/里程碑/决策），追加一条记录。
> 格式：`YYYY-MM-DD | 作者 | 类型 | 内容`
> 类型：`feat` / `fix` / `docs` / `chore` / `decision` / `release`

| 日期 | 作者 | 类型 | 内容 |
| --- | --- | --- | --- |
| 2026-05-19 | dev | decision | **ADR-007**：所有原生平台默认改用内嵌 libaria2（Dart FFI），子进程作为兜底；新增 `packages/aria2_native` 插件、`LibraryDaemon`、`Aria2InProcessTransport`、引擎切换 UI、`scripts/build_libaria2_*.sh` 与 CI 任务。 |
| 2026-05-19 | dev | feat | 任务长按菜单（详情/目录/暂停/分享）、列表 errorMessage、RPC 超时映射、设置导入友好错误 |
| 2026-05-19 | dev | feat | 任务长按菜单、错误 Banner、日志搜索、扩展 Test connection、保存应用下载目录、EXTENSIONS.md |
| 2026-05-19 | dev | feat | 导航角标、粘贴并入队、清除 stopped 记录、历史导入、QA.md、stage_windows_aria2.ps1 |
| 2026-05-19 | dev | feat | queueUris、RPC 错误文案、历史导出、剪贴板跳转新建、扩展发送页面、tag_release.sh、macOS aria2 CI |
| 2026-05-19 | dev | feat | 详情自适应轮询、全局选项搜索、扩展 aria2_rpc/角标、NM 安装脚本、WINDOWS.md、关于页快捷键 |
| 2026-05-19 | dev | feat | tellStatus keys、版本缓存、搜索防抖、Ctrl+N、深链复制、宽屏新建页、Firefox 导入 RPC、`release.yml`、DEEPLINKS.md |
| 2026-05-19 | dev | feat | 任务详情操作栏、`/add?uri=` 深链、RPC tell keys 减负、远程 RPC 预设、Chrome 导入配置、macOS/iOS CI、`validate_release.sh`、AGENTS.md |
| 2026-05-19 | dev | feat | 任务 Tab 计数、空态 CTA、全局选项页、Native Messaging/rpc_add_uri、复制扩展 RPC 配置、DESKTOP.md |
| 2026-05-19 | dev | feat | 远程 RPC 测试、关于页 RPC 信息、任务滑动操作、恢复刷新；设置导出元数据；CI 子模块 aria2；P4-01 Docker 脚本、IPA 文档 |
| 2026-05-19 | dev | feat | daemon 重试、错误页切远程、欢迎对话框、重复 URI 过滤；MSIX/build_bundle_with_aria2；Firefox 扩展；CI build-aria2 |
| 2026-05-19 | dev | feat | 任务列表：WS 降频轮询、排序、强制暂停/导出快照；设置 aria2 日志；移动默认远程；Android 前台 Service 骨架 |
| 2026-05-19 | dev | feat | P5-08：`extensions/chrome` 右键 addUri；`docs/BUILD_ARIA2.md`、`CONTRIBUTING.md`、`print_release_notes.sh` |
| 2026-05-18 | init | chore | 初始化 git 仓库（main 分支） |
| 2026-05-18 | init | chore | 添加 aria2 1.37.0 作为 git 子模块 `third_party/aria2` |
| 2026-05-18 | init | docs | 编写 `PLAN.md` 项目规划文档（含 WBS 与进度跟踪） |
| 2026-05-19 | dev | feat | 实现 `LocalDaemon` + `Aria2Client`（HTTP RPC）、`WsAria2Notifier`、首页任务列表与添加 URL |
| 2026-05-19 | dev | docs | 新增 `docs/BUILD.md`、根目录 `LICENSE`（GPLv2 全文） |
| 2026-05-19 | dev | chore | 添加 `.github/workflows/flutter.yml`（`flutter analyze` / `flutter test`） |
| 2026-05-19 | dev | feat | 新增 `bin/cli_demo.dart`：`addUri` + `tellStatus` 轮询示例 |
| 2026-05-20 | dev | feat | 底栏/侧栏壳（`StatefulShellRoute`）、设置持久化（`shared_preferences`）、中英 l10n、`Aria2RpcTransport` 抽象与 `Aria2Client` 单测 |
| 2026-05-21 | dev | feat | WS 通知驱动任务刷新；新建页高级选项与 Torrent/Metalink；任务重试与打开目录（桌面）；`Aria2Client` 支持动态 RPC options |
| 2026-05-22 | dev | feat | P3-04：Android/iOS 对已落地文件通过 `open_file` 调起系统应用；纯目录在移动设备上给出明确提示；`RevealPathResult` 细分失败原因 |
| 2026-05-23 | dev | feat | P1-15：`test/integration/aria2_e2e_test.dart`（真实 aria2c + 本机 HttpServer）；CI 安装 aria2；`Aria2HttpTransport` 使用 plain+手动 JSON 解析以兼容 `flutter test`；`LocalDaemon` 启动前创建 session 文件、RPC 端口改为系统分配 |
| 2026-05-23 | dev | chore | P3-07：新增 `scripts/build_desktop.sh`（analyze + test + release build） |
| 2026-05-24 | dev | feat | P5-01 首版：任务详情路由 `/tasks/detail/:gid`，概览/文件/BT（announce + peers）；`Aria2Client.getPeers` |
| 2026-05-26 | dev | feat | `aria2.getFiles` / `Aria2Client.getFiles`；P5-02：详情「文件」页 BT 多文件勾选 + `changeOption`(`select-file`)；P3-06 文档与 WBS 对齐「同目录 aria2c」解析 |
| 2026-05-27 | dev | feat | P5-02 收尾：`lib/core/torrent_metainfo.dart` 解析种子文件列表；新建页多文件 `.torrent` 弹窗勾选并以 `select-file` 调用 `addTorrent`；`test/core/torrent_metainfo_test.dart` |
| 2026-06-01 | dev | docs | P3-08 筹备：`CHANGELOG.md`、`docs/RELEASE.md`；`pubspec` 版本 **0.1.0+1**；`README` 链接与 CI 预构建说明 |
| 2026-05-30 | dev | chore | P3-06：CI 新增 `linux-release-bundle`（`flutter build linux` + 拷 apt `aria2c` 至 bundle + artifact）；`docs/BUILD.md`；`stage_aria2c.sh` 注释 |
| 2026-05-29 | dev | feat | P3-04 Web：`TaskListPage` 复制保存路径到剪贴板 + `openFolderWebCopied`；P5-01：BT 详情 `aria2.getOption` 展示 DHT/LPD 节选；补全 `_TorrentTab.btOptions` 与 `flutter gen-l10n` |
| 2026-05-28 | dev | feat | P5-01：BT 详情页展示 `tellStatus` 的 infoHash / numSeeders / seeder / 连接数；announce 按 tier 分组；`lib/core/bt_announce.dart` 与 `test/core/bt_announce_test.dart` |
| 2026-05-18 | dev | chore | P3-05 / P3-06：新增 `scripts/package_desktop.sh`（dmg / linux tar.gz / windows zip）、`scripts/stage_aria2c.sh`；`docs/BUILD.md` 脚本说明 |
| 2026-05-19 | dev | feat | P5-03～P5-06：`RemoteDaemon`、`aria2DaemonProvider`、设置页远程/限速/托盘/自启、JSON 导入导出；托盘 l10n 与可配置关闭行为 |
| 2026-05-19 | dev | feat | P5-07 / P5-01：任务历史 JSON + 历史 Tab；详情分块进度与复制；列表搜索/刷新；`LocalDaemon` 崩溃自动重启 |
| 2026-05-19 | dev | docs | P4-05 / P4-06：`docs/IOS.md`；P3-05 AppImage 可选脚本；CI `macos-release-bundle` |
| 2026-05-19 | dev | feat | 批量 RPC、任务 ETA/批量菜单、剪贴板粘贴、运行时限速、关于页；Android 二进制脚手架；CI Windows bundle + format check |
| 2026-05-19 | dev | docs | `docs/ANDROID.md`、`scripts/build_aria2.sh`、`extensions/README.md` |
| 2026-05-19 | dev | feat | Web 远程 RPC、连接错误页、平台提示、设置连接状态、桌面快捷键、批量删除已停止 |
| 2026-05-19 | dev | chore | `scripts/prepare_release.sh`、`docs/DEVELOPMENT.md`；CI `android-apk`；Chrome 扩展占位 |
| 2026-05-19 | dev | feat | URI 智能提取、粘贴并添加、设置默认目录；设置重置/关闭 aria2；任务详情复制链接；全局统计含已停止数 |
| 2026-05-19 | dev | chore | CI Windows 尝试 stage `aria2c.exe`；`test/core/uri_utils_test.dart` |

---

## 附录 A：常用命令

```bash
# 克隆（包含子模块）
git clone --recurse-submodules <repo-url>

# 已克隆后初始化子模块
git submodule update --init --recursive

# 更新 aria2 子模块到最新 release（注意检查兼容性）
cd third_party/aria2 && git fetch --tags && git checkout release-1.37.0

# Flutter 相关
flutter pub get
flutter analyze
flutter test
flutter run -d macos      # 桌面调试
flutter build macos       # 桌面打包
./scripts/build_desktop.sh macos   # 分析 + 单测 + release 构建（linux / windows 同理）
./scripts/stage_aria2c.sh macos third_party/aria2/src/aria2c   # build 之后拷入同目录 aria2c
./scripts/package_desktop.sh macos # 再生成 build/dist/*.dmg（或 linux tar.gz / windows zip）
```

## 附录 B：维护本规划文档的约定

1. 每次完成任务，将对应任务状态从 `☐` 改为 `✅`，进行中改为 `◐`。
2. 同步更新 [项目进度](#13-项目进度) 表格中的统计数字与「上次更新」日期。
3. 在 [项目进度日志](#14-项目进度日志) 追加一行。
4. 重要决策（技术选型变更、范围调整）以 `decision` 类型记录。
5. 范围变更（新增/删除任务）需在 WBS 中增删条目，并在日志中说明原因。
