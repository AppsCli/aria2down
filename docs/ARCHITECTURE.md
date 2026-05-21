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
│   - Aria2Daemon (Local / Remote)                               │
│   - Aria2Client (HTTP / WebSocket transport)                   │
│   - Aria2ConfigBuilder, BinaryResolver                         │
└──────────────────────────────┬─────────────────────────────────┘
                               │ Process / Socket
┌──────────────────────────────┴─────────────────────────────────┐
│              aria2c (third_party/aria2 编译产物)              │
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
│   ├── http_transport.dart         # 基于 dio 的 HTTP 实现
│   ├── in_process_transport.dart   # 库模式实现：调用 packages/aria2_native
│   └── ws_listener.dart            # 通知源接口 + WS 实现
├── daemon/
│   ├── aria2_daemon.dart           # 抽象接口
│   ├── library_daemon.dart         # 内嵌 libaria2（默认；ADR-007）
│   ├── local_daemon.dart           # aria2c 子进程兜底
│   ├── remote_daemon.dart          # 远程连接实现（含 Web）
│   └── daemon_state.dart           # 状态枚举
├── binary/
│   └── binary_resolver.dart        # 解析 aria2c 路径（兜底引擎用）
└── config/
    └── aria2_config_builder.dart   # 生成 aria2.conf（兜底引擎用）

packages/
└── aria2_native/                   # 独立 FFI 插件：C 薄封装 + Dart 绑定
    ├── src/aria2_ffi.{h,cc}        # extern "C" shim
    ├── lib/                        # Dart bindings + Aria2NativeSession
    └── prebuilt/<platform>/<arch>/ # libaria2.a + 依赖（构建脚本生成）
```

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

- `LocalDaemon`：管理 `aria2c` 子进程；自动生成端口（避开占用）、token、写 `aria2.conf`；监听进程退出码并自愈。
- `RemoteDaemon`：仅维护到远端 RPC 的连接，无进程管理。

### 3.5 BinaryResolver

定位 `aria2c` 二进制的优先级：

1. 用户在设置中显式指定的路径。
2. 应用安装目录内置（桌面：`<app>/aria2c[.exe]`；Android：私有目录拷贝出的二进制）。
3. 系统 `PATH` 中的 `aria2c`（开发模式 / 系统已安装时方便调试）。

### 3.6 ConfigBuilder

生成的 `aria2.conf` 大致内容：

```ini
enable-rpc=true
rpc-listen-all=false
rpc-allow-origin-all=false
rpc-listen-port=<dynamic>
rpc-secret=<random-32-bytes-hex>
rpc-secure=false
dir=<user_downloads>
input-file=<state>/aria2.session
save-session=<state>/aria2.session
save-session-interval=30
continue=true
max-connection-per-server=8
split=8
min-split-size=1M
disk-cache=64M
file-allocation=falloc
seed-time=0
log=<state>/aria2.log
log-level=warn
console-log-level=warn
```

参数全部可在设置页覆盖；用户修改后写入用户配置（与默认值合并）。

---

## 4. 关键流程时序

### 4.1 应用启动 → aria2 就绪

```
User → MyApp.main()
  → ProviderScope 初始化
    → Aria2Daemon.provider:
        1. BinaryResolver 找到 aria2c 路径
        2. ConfigBuilder 写出 aria2.conf
        3. 选择空闲端口（默认 6800，冲突时 +1 重试）
        4. Process.start(aria2c, ['--conf-path', '<path>'])
        5. 等待 RPC 端口可连接（最多 5s，每 100ms 重试）
        6. 创建 WS Transport + Aria2Client
        7. 调用 aria2.getVersion 验证连通
    → DaemonState = ready
  → 路由到 TaskListPage
```

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
| macOS | App 沙盒启用；entitlements 含 `network.client`、用户自选目录与 Downloads 写权限；子进程 RPC 需 `network.server` |
| Windows | `aria2c.exe`；UAC 弹窗（自启时） |
| Linux | 多种发行版打包格式：deb / rpm / AppImage |
| Android | aria2c 放入 `assets/`，启动时拷贝到 `getApplicationSupportDirectory()` 并 `chmod 755`；用 ForegroundService 守护 |
| iOS | 不允许 fork/exec，因此默认引擎为 **内嵌 libaria2（ADR-007）**；同步支持远程 RPC。子进程兜底在 iOS 上自动不可用。|

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

### ADR-007：默认改用内嵌 libaria2（Dart FFI）

- **背景**：ADR-001 选择子进程模型，但带来 iOS 沙盒不可用、桌面/移动需附带额外二进制、子进程崩溃感知滞后等问题。
- **决策**：在所有原生平台（macOS / Linux / Windows / Android / iOS）默认使用 [packages/aria2_native](../packages/aria2_native/) FFI 插件，把 libaria2 静态链接进应用进程；通过 [`LibraryDaemon`](../lib/aria2/daemon/library_daemon.dart) + [`Aria2InProcessTransport`](../lib/aria2/client/in_process_transport.dart) 把 JSON-RPC 等价调用翻译为 libaria2 C ABI。
- **兜底**：[`LocalDaemon`](../lib/aria2/daemon/local_daemon.dart)（aria2c 子进程）保留为可选引擎，由设置项 `LocalEngine.subprocess` 切换；`AppSettings.fallbackToSubprocess` 控制 FFI 初始化失败时是否自动回退。
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

> 后续重要决策按 `ADR-NNN` 编号继续追加。
