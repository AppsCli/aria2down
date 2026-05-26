# aria2down 架构设计文档

> 本文档详细描述 `aria2down` 的整体架构、关键模块、关键流程与设计决策。
> 与 `PLAN.md` 互补：`PLAN.md` 关注「做什么、何时做」，本文档关注「怎么做」。

---

## 目录

1. [架构总览](#1-架构总览)
2. [分层职责](#2-分层职责)
3. [aria2 集成层详解](#3-aria2-集成层详解)
4. [关键流程时序](#4-关键流程时序)
5. [线程与并发模型](#5-线程与并发模型)
6. [数据模型](#6-数据模型)
7. [配置与持久化](#7-配置与持久化)
8. [错误处理与日志](#8-错误处理与日志)
9. [安全](#9-安全)
10. [跨平台差异](#10-跨平台差异)
11. [测试架构](#11-测试架构)
12. [扩展点](#12-扩展点)

---

## 1. 架构总览

```
┌────────────────────────────────────────────────────────────────┐
│                       Presentation                             │
│   Flutter Widgets / Pages（features/*/presentation）           │
└──────────────────────────────┬─────────────────────────────────┘
                               │ Riverpod Providers
┌──────────────────────────────┴─────────────────────────────────┐
│                       Application                              │
│   Controllers / Notifiers（features/*/application）            │
│   - TaskListController, NewTaskController, SettingsController  │
└──────────────────────────────┬─────────────────────────────────┘
                               │
┌──────────────────────────────┴─────────────────────────────────┐
│                          Domain                                │
│   纯 Dart：Entities、UseCases、Repository 接口                 │
│   - Task, GlobalStat, AddTaskUseCase, ToggleTaskUseCase ...    │
└──────────────────────────────┬─────────────────────────────────┘
                               │
┌──────────────────────────────┴─────────────────────────────────┐
│                            Data                                │
│   Repository 实现、本地存储、远程数据源                         │
│   - TaskRepositoryImpl(Aria2Client)                            │
│   - SettingsRepositoryImpl(SharedPreferences)                  │
└──────────────────────────────┬─────────────────────────────────┘
                               │
┌──────────────────────────────┴─────────────────────────────────┐
│                     aria2 Integration                          │
│   - Aria2Daemon (LibraryDaemon / RemoteDaemon)                 │
│   - Aria2Client (HTTP / WebSocket / in-process transport)      │
└──────────────────────────────┬─────────────────────────────────┘
                               │ FFI / Socket
┌──────────────────────────────┴─────────────────────────────────┐
│  libaria2 静态库（third_party/aria2 编译产物，FFI 内嵌）       │
│  远程 RPC 时则连接外部 aria2c HTTP/WS                          │
└────────────────────────────────────────────────────────────────┘
```

采用 **Clean Architecture** 风格的分层：

- 上层只依赖下层接口，不依赖实现。
- 通过 Riverpod 在边界处注入依赖（便于测试与替换实现）。

---

## 2. 分层职责

### 2.1 Presentation（`features/*/presentation`）

- 仅负责渲染与转发用户事件。
- 通过 `ref.watch` 观察 Provider 暴露的状态。
- 不包含业务逻辑，不直接调用 `Aria2Client`。

### 2.2 Application（`features/*/application`）

- Riverpod `Notifier` / `AsyncNotifier`。
- 协调 UseCases、维护 UI 状态、处理副作用（导航、SnackBar）。
- 不直接持有网络/进程对象，依赖通过 Provider 注入。

### 2.3 Domain（`features/*/domain` 与 `data/models`）

- 纯 Dart，不依赖 Flutter / dio / 进程。
- 定义实体（Entities）：`Task`、`TaskFile`、`GlobalStat`。
- 定义 UseCase：`AddUriUseCase`、`PauseTaskUseCase`、`WatchTasksUseCase`。
- 定义 Repository **接口**。

### 2.4 Data（`data/`）

- 实现 Repository，把 Domain 层的请求翻译成对 `Aria2Client` 的 RPC 调用。
- 管理本地持久化（设置、历史）。

### 2.5 aria2 Integration（`aria2/`）

- 本项目的核心：见下一节。

---

## 3. aria2 集成层详解

### 3.1 模块结构

```
lib/aria2/
├── client/
│   ├── aria2_client.dart           # 高层 API（addUri, tellActive 等）
│   ├── rpc_methods.dart            # 方法名常量
│   ├── rpc_transport.dart          # 抽象传输接口（HTTP / 库内 共用）
│   ├── http_transport.dart         # 基于 dio 的 HTTP 实现（仅远程模式）
│   ├── in_process_transport.dart   # 库模式实现：调用 packages/aria2_native
│   └── ws_listener.dart            # 通知源接口 + WS 实现
└── daemon/
    ├── aria2_daemon.dart           # 抽象接口
    ├── library_daemon.dart         # 内嵌 libaria2（本机唯一引擎；ADR-007 / ADR-010）
    ├── remote_daemon.dart          # 远程连接实现（含 Web）
    └── daemon_state.dart           # 状态枚举

packages/
└── aria2_native/                   # 独立 FFI 插件：C 薄封装 + Dart 绑定
    ├── src/aria2_ffi.{h,cc}        # extern "C" shim
    ├── lib/                        # Dart bindings + Aria2NativeSession
    └── prebuilt/<platform>/<arch>/ # libaria2.a + 依赖（构建脚本生成）
```

> ADR-010 之前还存在 `lib/aria2/daemon/local_daemon.dart`（aria2c 子进程）、`lib/aria2/binary/binary_resolver.dart`、`lib/aria2/config/aria2_config_builder.dart` 三个分支，已整体移除。需要外部 aria2c 的用户改用「远程 RPC」连接方式连接自己运行的 aria2c。

### 3.2 Transport 抽象

```dart
abstract class Aria2Transport {
  Future<Map<String, dynamic>> call(String method, List<dynamic> params);
  Stream<Aria2Notification> get notifications; // 仅 WS 实现支持
  Future<void> close();
}
```

- HTTP：`POST /jsonrpc`，请求体 JSON-RPC 2.0，单请求对应单响应。
- WebSocket：连接到 `ws://host:port/jsonrpc`，自增 id 匹配请求/响应；收到 `method` 字段以 `aria2.on*` 开头的消息视为通知。

`Aria2Client` 默认优先使用 WS；若 WS 不可用回退到 HTTP（轮询模式）。

### 3.3 Aria2Client API（节选）

```dart
class Aria2Client {
  Aria2Client({required Aria2Transport transport, required String secret});

  Future<String> addUri(List<String> uris, {Aria2Options? options});
  Future<String> addTorrent(Uint8List torrent, {Aria2Options? options});
  Future<String> addMetalink(Uint8List metalink, {Aria2Options? options});

  Future<void> pause(String gid);
  Future<void> unpause(String gid);
  Future<void> remove(String gid, {bool force = false});

  Future<TaskStatus> tellStatus(String gid, {List<String>? keys});
  Future<List<TaskStatus>> tellActive({List<String>? keys});
  Future<List<TaskStatus>> tellWaiting({int offset = 0, int num = 1000});
  Future<List<TaskStatus>> tellStopped({int offset = 0, int num = 1000});

  Future<GlobalStat> getGlobalStat();
  Future<Map<String, String>> getGlobalOption();
  Future<void> changeGlobalOption(Map<String, String> options);

  Future<String> getVersion();
  Future<void> shutdown({bool force = false});

  Stream<Aria2Notification> get notifications;
}
```

所有 RPC 方法都自动注入 `secret` 参数（`token:<secret>`）。

### 3.4 Aria2Daemon 接口

```dart
abstract class Aria2Daemon {
  DaemonState get state;
  Stream<DaemonState> get stateStream;

  Aria2Endpoint get endpoint;   // host / port / secret / scheme
  Aria2Client get client;

  Future<void> start();
  Future<void> stop({bool force = false});
  Future<void> restart();
}
```

- `LibraryDaemon`：在应用进程内启动 libaria2 session；启动时把进程级 aria2 options（`dir` / `input-file` / `save-session` 等）作为 FFI `KeyVals` 注入，session 内部维护 `aria2.session` 与 `aria2.log` 文件。
- `RemoteDaemon`：仅维护到远端 RPC 的连接，无进程管理。

### 3.5 进程级 aria2 选项

`LibraryDaemon` 启动时注入的关键 options（与 ADR-010 之前 LocalDaemon 写入 `aria2.conf` 的字段一致）：

```text
dir=<user_downloads>
input-file=<state>/aria2.session
save-session=<state>/aria2.session
save-session-interval=30
continue=true
min-split-size=1M
disk-cache=64M
file-allocation=prealloc
seed-time=0
log=<state>/aria2.log
log-level=warn
```

设置页用户填入的 `maxConcurrentDownloads` / `maxConnectionPerServer` / `globalDownloadLimit` / `globalUploadLimit` 等运行时参数通过 `changeGlobalOption` 写入活跃 session（不重启进程）。

---

## 4. 关键流程时序

### 4.1 应用启动 → aria2 就绪

```
User → MyApp.main()
  → ProviderScope 初始化
    → aria2DaemonProvider:
        本机模式：
        1. Aria2NativeSession.open(options)         # FFI 加载 libaria2，注入 options
        2. 启动 worker isolate 持续驱动事件循环      # ADR-008
        3. 包装为 LibraryDaemon + Aria2InProcessTransport + Aria2Client
        4. 调用 aria2.getVersion 验证连通
        远程模式：
        1. 解析用户填入的 endpoint + secret
        2. WebSocket 连接 + HTTP fallback
        3. Aria2Client.getVersion 验证连通
    → DaemonState = ready
  → 路由到 TaskListPage
```

> ADR-010 之前还有第三条路径——`LocalDaemon` spawn `aria2c` 子进程 + 选空闲端口 + 写 `aria2.conf` + 等 RPC 就绪——已经整体移除。

### 4.2 新建下载任务

```
NewTaskPage → 用户填写 URL + 选项
  → NewTaskController.submit()
    → AddUriUseCase
      → TaskRepository.addUri(...)
        → Aria2Client.addUri(...)
          → Transport.call('aria2.addUri', [token, uris, options])
          → 返回 gid
    → 路由回 TaskListPage（高亮新任务）
```

### 4.3 任务进度推送

```
aria2c → WS 推送 aria2.onDownloadStart {gid}
  → Aria2Client.notifications stream
    → TaskListController 收到事件
      → tellStatus(gid) 拉取最新状态
      → 更新 Riverpod 状态
        → UI 自动刷新进度条

定时（1s）→ getGlobalStat() → 更新顶部统计条
```

### 4.4 应用退出

```
User 关闭窗口
  → window_manager onClose 拦截
    → Aria2Daemon.stop()
      → Aria2Client.shutdown()  # 优雅关闭，aria2 会保存 session
      → 等待进程退出（最多 3s），超时则 forceKill
  → app exit
```

---

## 5. 线程与并发模型

- Dart 单线程（main isolate）+ async/await。
- 阻塞操作（文件 I/O、加密计算）使用 `compute()` 或 `Isolate`。
- aria2 进程的 stdout/stderr 通过 `transform(utf8.decoder).transform(LineSplitter())` 流式读取并写入应用日志。
- WebSocket 与 HTTP 调用都是异步非阻塞的，不会阻塞 UI。

---

## 6. 数据模型

### 6.1 Task（aria2 任务，对应 `tellStatus` 返回）

```dart
class TaskStatus {
  final String gid;
  final TaskState status; // active / waiting / paused / error / complete / removed
  final int totalLength;
  final int completedLength;
  final int downloadSpeed;
  final int uploadSpeed;
  final List<String>? followedBy;
  final String? following;
  final int connections;
  final int? errorCode;
  final String? errorMessage;
  final List<TaskFile> files;
  final String? bittorrent;       // 仅 BT 任务
  final String dir;
  final Map<String, String> options;
}
```

### 6.2 GlobalStat

```dart
class GlobalStat {
  final int downloadSpeed;
  final int uploadSpeed;
  final int numActive;
  final int numWaiting;
  final int numStopped;
  final int numStoppedTotal;
}
```

### 6.3 Aria2Notification

```dart
sealed class Aria2Notification {}
class DownloadStart extends Aria2Notification { final String gid; }
class DownloadPause extends Aria2Notification { final String gid; }
class DownloadStop extends Aria2Notification { final String gid; }
class DownloadComplete extends Aria2Notification { final String gid; }
class DownloadError extends Aria2Notification { final String gid; }
class BtDownloadComplete extends Aria2Notification { final String gid; }
```

---

## 7. 配置与持久化

| 数据 | 存储 |
| --- | --- |
| 用户设置（主题、语言、下载目录、限速） | `shared_preferences` |
| aria2 会话（任务列表） | aria2 自身的 `aria2.session` 文件 |
| 应用日志 | 用户日志目录滚动文件，最多保留 7 天 |
| 任务历史（v0.2+，独立于 aria2 session） | `drift` (SQLite) |
| RPC token | `aria2.conf` + 加密保存到应用设置 |

目录约定（基于 `path_provider`）：

```
<ApplicationSupport>/aria2down/
├── conf/aria2.conf
├── state/
│   ├── aria2.session
│   └── aria2.log
├── logs/app.log
└── settings.json
```

---

## 8. 错误处理与日志

- 统一异常类型：`Aria2Exception`、`DaemonException`、`TransportException`。
- RPC 错误码透传到 UI（按 `errorCode` 友好提示）。
- 日志分级：`trace / debug / info / warn / error`。
- 日志去敏：自动屏蔽 `secret` token、Cookie 等敏感字段。
- 用户可在 「设置 → 关于 → 打开日志目录」 直接查看。

---

## 9. 安全

| 关注点 | 措施 |
| --- | --- |
| RPC 暴露 | 仅 `127.0.0.1` 监听；`rpc-secret` 使用 `Random.secure()` 生成 32 字节十六进制 |
| token 文件权限 | `aria2.conf` 写入后 chmod 600（POSIX） |
| 远程模式凭证 | 仅明文存于本机，提示用户使用 HTTPS |
| 二进制完整性 | 应用启动校验内置 aria2c 的 SHA256（与构建时锁定值对比） |
| 下载文件安全 | 不自动执行；提供 「在文件夹中显示」 而非 「打开」 默认 |

---

## 10. 跨平台差异

| 平台 | 关键差异 |
| --- | --- |
| macOS | App 沙盒启用；entitlements 含 `network.client`、`network.server`（接收 BT 入站连接 / metadata 服务）、用户自选目录与 Downloads 写权限 |
| Windows | 桌面平台无 sandbox；prebuilt libaria2 通过 mingw 交叉编译生成 |
| Linux | 多种发行版打包格式：deb / rpm / AppImage；libaria2 静态链入 app binary |
| Android | libaria2 通过 NDK 交叉编译为 `.so`，FFI 直接 dlopen；用 ForegroundService 守护下载（ADR-009） |
| iOS | 不允许 fork/exec；libaria2 通过 `xcframework` 静态链接进 app 主二进制（ADR-007）。沙盒严格，下载只能写应用 Documents 等沙箱目录 |

> ADR-010 后所有平台共用一条本机路径——`LibraryDaemon`。子进程引擎与对应的 Android/桌面 binary staging 已经从源码与构建脚本中整体移除。

平台抽象通过 `lib/core/platform/` 暴露统一接口。

---

## 11. 测试架构

```
test/
├── unit/
│   ├── aria2/
│   │   ├── http_transport_test.dart        # 用 mockito 模拟 dio
│   │   ├── ws_transport_test.dart          # 用本地 echo server
│   │   ├── aria2_client_test.dart          # 用 fake transport
│   │   └── config_builder_test.dart
│   ├── domain/
│   └── data/
├── widget/
│   ├── task_list_page_test.dart
│   ├── new_task_page_test.dart
│   └── settings_page_test.dart
└── integration/
    └── e2e_download_test.dart              # 启动真 aria2c + HTTP server
```

CI 跑 `flutter analyze` + `flutter test`；集成测试在本地或自托管 runner 跑。

---

## 12. 扩展点

| 扩展场景 | 扩展点 |
| --- | --- |
| 添加新 RPC 方法 | `Aria2Client` 增加方法，`rpc_methods.dart` 增加常量 |
| 接入远程 aria2 | 实现 `RemoteDaemon` 即可，UI 已经面向 `Aria2Daemon` 接口 |
| 多实例（同时连接多台机器） | `Aria2Daemon` 改为可多实例 + 每个实例独立 Riverpod scope |
| 替换状态管理 | 仅 `application` 与 `presentation` 受影响，集成层不变 |
| 新协议（如 IPFS） | 仍由 aria2 处理（如支持），UI 层无需改动 |

---

## 13. 决策记录（ADR 摘要）

| ID | 决策 | 替代方案 | 选择理由 | 状态 |
| --- | --- | --- | --- | --- |
| ADR-001 | 用 JSON-RPC（子进程）而非 FFI 集成 aria2 | FFI 直接调用 C++ | 隔离崩溃、跨平台一致、aria2 官方稳定 RPC API | **Superseded by ADR-007** |
| ADR-002 | 默认使用 WebSocket 传输 | 仅 HTTP 轮询 | 实时通知，CPU 占用低 | 生效 |
| ADR-003 | 项目协议 GPLv2+ | MIT/Apache | 与 aria2 兼容（必选） | 生效 |
| ADR-004 | iOS MVP 仅远程模式 | 编译静态库 | 沙盒限制 + 工作量；后续再做静态库方案 | **Resolved by ADR-007** |
| ADR-005 | UI 层使用 Riverpod | Provider / Bloc | 类型安全、可组合、社区活跃 | 生效 |
| ADR-006 | aria2 作为 git submodule（不 fork） | 复制源码 / vendoring | 易于跟随 upstream 更新，体积可控 | 生效 |
| ADR-007 | **所有原生平台默认内嵌 libaria2（Dart FFI）**；保留子进程作为兜底/调试通道 | 继续 ADR-001 子进程模式 | 进程数 ↓、iOS 沙盒可用、启动时间 ↓、可同步事件 | **生效（默认引擎）** |
| ADR-008 | libaria2 FFI 全部委派给独立 worker isolate（含事件循环 `run_once`） | 在主 isolate 同步调用 + Timer 驱动 `run_once` | UI 线程不再被 `eventPoll_->poll(refreshInterval=1s)` 阻塞，避免数百毫秒抖动 | **生效** |
| ADR-009 | 桌面 / Android 后台保活与控制信号集中到 `MobileBackgroundBinding` / `TrayExitBinding`，统一消费 `globalStatStreamProvider` | 各 daemon 自行调用平台 API；UI 页面驱动通知 | 解耦 daemon 与平台外壳；切换页面、首页未打开时托盘 tooltip / 前台服务通知仍能持续刷新；通知按钮可在 Flutter Engine 已初始化的前提下直接控制 aria2 | **生效** |
| ADR-010 | **移除 aria2c 子进程引擎**：`LocalDaemon` / `BinaryResolver` / `Aria2ConfigBuilder` / Android `assets/android/<abi>/aria2c` staging / `bin/native_messaging_host.dart` / `bin/rpc_add_uri.dart` 等子进程相关代码全部删除；`AppSettings.localEngine` / `fallbackToSubprocess` / `aria2BinaryPath` 字段一并撤销 | 保留子进程引擎作为 FFI 失败时的"安全网" | prebuilt libaria2 在每个发布目标上都已经稳定可用且 ADR-008 worker isolate 解决了主线程阻塞；子进程引擎要再维护一份 staging 脚本 / Android assets / Windows binary / native messaging host / Chrome 扩展安装脚本，单平台 binary 资源 +3~12 MB；收益已远低于成本。需要外部 aria2c 的用户改用「远程 RPC」连接模式 | **生效** |

### ADR-007：默认改用内嵌 libaria2（Dart FFI）

- **背景**：ADR-001 选择子进程模型，但带来 iOS 沙盒不可用、桌面/移动需附带额外二进制、子进程崩溃感知滞后等问题。
- **决策**：在所有原生平台（macOS / Linux / Windows / Android / iOS）默认使用 [packages/aria2_native](../packages/aria2_native/) FFI 插件，把 libaria2 静态链接进应用进程；通过 [`LibraryDaemon`](../lib/aria2/daemon/library_daemon.dart) + [`Aria2InProcessTransport`](../lib/aria2/client/in_process_transport.dart) 把 JSON-RPC 等价调用翻译为 libaria2 C ABI。
- **兜底（已在 ADR-010 移除）**：曾存在的 `LocalDaemon`（aria2c 子进程）+ `AppSettings.fallbackToSubprocess` 自动回退在 ADR-010 中整体撤销；本机模式现在唯一选项即 `LibraryDaemon`。
- **Web**：仍仅支持 [`RemoteDaemon`](../lib/aria2/daemon/remote_daemon.dart)（浏览器无法运行原生代码）。
- **绑定层**：libaria2 是 C++ API，无法直接被 Dart FFI（仅 C ABI）绑定，故在 [packages/aria2_native/src/aria2_ffi.{h,cc}](../packages/aria2_native/src/aria2_ffi.h) 提供 `extern "C"` 薄封装；状态/选项序列化为 JSON 字符串以复用 [`Aria2Client`](../lib/aria2/client/aria2_client.dart) 原有解析路径。
- **事件**：libaria2 的 `DownloadEventCallback` 经 `NativeCallable.listener` 跨线程推入 Dart `Stream`，再适配为现有的 [`Aria2NotificationSource`](../lib/aria2/client/ws_listener.dart) 形态，UI 层零改动。
- **隔离 worker（ADR-008）**：libaria2 的 `aria2::run(RUN_ONCE)` 内部最长阻塞 1 s 等待 socket I/O，因此 `Aria2NativeSession` 把所有 FFI 调用统一委派给独立 worker isolate（[packages/aria2_native/lib/src/worker.dart](../packages/aria2_native/lib/src/worker.dart)）；事件回调由 worker 内的 `NativeCallable.listener` 接收后转发回主 isolate，主 isolate（UI 线程）零阻塞。
- **构建**：每平台一份脚本：[scripts/build_libaria2_macos.sh](../scripts/build_libaria2_macos.sh)、`_linux.sh`、`_windows.sh`、`_android.sh`、`_ios.sh`；产物落到 `packages/aria2_native/prebuilt/<platform>/<arch>/`，FFI 插件 CMake/podspec 自动检测：未发现产物时编译为 **stub-only** 版本（每个入口返回 `ARIA2_FFI_ERR_UNAVAILABLE`），让 Dart 侧自动回退到子进程。
- **依赖**：OpenSSL、c-ares、sqlite3、zlib 等以静态库形式链接，避免运行时依赖。各平台依赖落入 `prebuilt/<...>/deps/*.a`。
- **包体积**：单平台预估 +6 ~ 12 MB（静态 strip 后）。
- **取舍**：单进程单 Session 限制由 libaria2 决定（[third_party/aria2/src/includes/aria2/aria2.h](../third_party/aria2/src/includes/aria2/aria2.h) 文档），引擎切换通过 `ref.invalidate(aria2DaemonProvider)` 重建 daemon 实现优雅迁移。

### ADR-009：后台/托盘统一由 binding 层驱动

- **背景**：ADR-001~008 让 daemon 负责进程/库生命周期；早期版本 [`LibraryDaemon`](../lib/aria2/daemon/library_daemon.dart) / [`LocalDaemon`](../lib/aria2/daemon/local_daemon.dart) 直接调用 `AndroidKeepAlive.start/stop`，UI 页面（任务列表）独立轮询 `getGlobalStat`。这带来两个问题：(1) 任务列表页未挂载时，桌面托盘 tooltip 与 Android 前台通知都拿不到实时数据；(2) daemon 抽象渗漏到平台外壳。
- **决策**：
  - 新增 [`globalStatStreamProvider`](../lib/providers/global_stat_provider.dart)（独立 1s/5s 自适应轮询，跟随 `appInBackgroundProvider` 立即唤醒），作为「全局统计的唯一来源」。
  - 桌面：[`TrayExitBinding`](../lib/app/tray_exit_binding.dart) 订阅 `globalStatStreamProvider` 更新托盘 tooltip；注册整套 `DesktopTrayCallbacks`（新建任务 → 路由 `/add`，全部暂停/继续 → `aria2DaemonProvider.future` + `client.pauseAll/unpauseAll`，打开下载目录 → `getGlobalOption.dir` → `revealPathInFileManager`）。
  - 移动：[`MobileBackgroundBinding`](../lib/app/mobile_background_binding.dart) 在「daemon 就绪 + 本机模式 + `keepAliveInBackground=true`」时调用 [`AndroidKeepAlive.start`](../lib/core/android_keep_alive.dart)，随后每次 `globalStatStreamProvider` 触发都 `update`；同时订阅 `controlEvents`，处理通知按钮信号（`pause_all` / `resume_all` / `show_window`）。
  - daemon 内部不再耦合 `AndroidKeepAlive`。
- **Android Service**：[`Aria2KeepAliveService`](../android/app/src/main/kotlin/cloud/iothub/aria2down/Aria2KeepAliveService.kt) 接受 `ACTION_START` / `ACTION_UPDATE` / `ACTION_PAUSE_ALL` / `ACTION_RESUME_ALL` / `ACTION_QUIT`；通知按钮通过 `PendingIntent.getService` 触发，service 收到控制 action 后 `startActivity(MainActivity, action=…)` 把信号转给 Flutter；活跃任务时持 `PARTIAL_WAKE_LOCK`，空闲释放，30 min 兜底超时。
- **iOS**：[`AppDelegate.swift`](../ios/Runner/AppDelegate.swift) 进入后台时 `beginBackgroundTask` 延长存活并提交 `BGAppRefreshTask` / `BGProcessingTask`；`Info.plist` 声明 `UIBackgroundModes=fetch,processing` 与 `BGTaskSchedulerPermittedIdentifiers`。
- **静默启动**：[`AppSettings.startMinimized`](../lib/data/app_settings.dart) 在 [`main.dart`](../lib/main.dart) 提前读取，桌面 `initDesktopShell(startMinimized: true)` 立即 `windowManager.hide()`，与 `launchAtStartup` 组合实现「登录即托盘待命」。

### ADR-010：移除 aria2c 子进程引擎

- **背景**：ADR-007 把内嵌 libaria2 设为默认，但保留了 `LocalDaemon`（spawn `aria2c` 子进程 + 写 `aria2.conf` + 等 RPC 就绪）作为兜底。一年过去后实际情况：
  - prebuilt libaria2 在 macOS / Linux / Windows / Android / iOS 全平台都已经稳定可用；
  - ADR-008 worker isolate 解决了 `aria2::run(RUN_ONCE)` 阻塞 UI 线程的问题；
  - 子进程引擎要单独维护 `binary_resolver.dart` / `aria2_config_builder.dart` / Android `assets/android/<abi>/aria2c` staging / Windows `stage_windows_aria2.ps1` / `bin/native_messaging_host.dart` / `bin/rpc_add_uri.dart` / Chrome 扩展 native messaging 安装脚本 / `local_rpc_credentials.dart`；
  - APK 体积单独为 4 个 ABI 各拷一份 `aria2c` 二进制（约 +12 MB）；
  - Release CI 流程额外跑一遍 `build_aria2.sh` + `stage_aria2c.sh`；
  - 实际触发回退的场景几乎没有报告——prebuilt 缺失时改用远程 RPC 的引导路径已经成熟。
- **决策**：完整移除子进程引擎及其所有附属代码与资源：
  - **代码**：`lib/aria2/daemon/local_daemon.dart`、`lib/aria2/daemon/local_daemon_paths.dart`、`lib/aria2/binary/binary_resolver.dart`、`lib/aria2/binary/android_binary_extractor.dart`、`lib/aria2/config/aria2_config_builder.dart`、`lib/core/local_rpc_credentials.dart`、`lib/core/add_uri_via_local_rpc.dart`、`bin/native_messaging_host.dart`、`bin/rpc_add_uri.dart`、`bin/cli_demo.dart`、`Aria2BinaryNotFoundException`。
  - **数据**：`AppSettings.localEngine` / `fallbackToSubprocess` / `aria2BinaryPath` 字段与对应 SharedPreferences key 删除；`settings_export.dart` 静默忽略历史 JSON 中的这些字段以保留旧备份的可导入性；`SettingsRepository.save()` 主动 `remove` 老 key 完成迁移。
  - **UI**：设置页删除引擎二选一 SegmentedButton、aria2c 路径输入框、`fallbackToSubprocess` switch。`ConnectionMode.local` 下只展示「内嵌库（libaria2）」说明。「复制 RPC 配置给浏览器扩展」仅在远程模式下露出，直接复用用户填的 endpoint+secret 生成 JSON。
  - **Assets / scripts**：`assets/android/`（含 README + binary placeholder）、`scripts/build_aria2.sh`、`scripts/build_android_aria2_docker.sh`、`scripts/build_bundle_with_aria2.sh`、`scripts/stage_android_aria2.sh`、`scripts/stage_aria2c.sh`、`scripts/stage_windows_aria2.ps1`、`scripts/install_native_messaging_host.sh`、`extensions/native-messaging/` 整目录。
  - **CI**：`.github/workflows/build-aria2.yml` 中所有 `*-aria2c` job 移除；`flutter.yml` 与 `release.yml` 不再下载 / 编译 / 拷贝 `aria2c` 到产物 bundle。
  - **i18n**：删除 `engineSubprocess` / `engineSubprocessDesc` / `engineSubprocessShort` / `engineFallbackToSubprocess(Desc)` / `engineUnavailableBanner` / `engineInitFailed` / `aria2BinaryPath` / `aria2BinaryHint` / `restartAria2Hint` / `daemonErrorBinaryNotFound` 共 11 个 key（中英）。
- **替代路径**：需要在外部运行 aria2c（譬如远程 NAS、Docker 容器内的下载机、自定义参数的 aria2c）的用户改用「远程 RPC」连接模式，输入 endpoint + secret 即可。Chrome 扩展也指向远程 endpoint，体验与之前的子进程模式完全等价。
- **prebuilt 不可用**：`LibraryDaemon.create` 内部检测 prebuilt libaria2 缺失时直接抛 `Aria2NativeUnavailableException`；设置页有「库引擎运行在功能受限模式」红条引导用户重编 prebuilt，daemon 错误屏也明确提示改用远程 RPC。
- **可恢复性**：本次清理记录在 git 历史中，未来若发现极端场景下确实需要子进程兜底，可以从 git 历史恢复对应模块。但当前没有任何已知场景需要这条路径。

> 后续重要决策按 `ADR-NNN` 编号继续追加。
