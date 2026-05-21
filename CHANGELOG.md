# 变更日志

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 约定，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 新增（全平台后台能力强化）

- **桌面托盘扩展**：托盘菜单从「显示窗口 / 退出」扩展为「显示窗口 / 新建下载… / 全部暂停 / 全部继续 / 打开下载目录 / 退出」；托盘 tooltip 实时显示当前下载/上传速度与活跃/等待任务数；右键弹出菜单、双击/单击托盘图标恢复主窗口。
- **桌面静默启动**：新增 `AppSettings.startMinimized`，桌面端配合开机自启可在启动时直接最小化到托盘（[lib/main.dart](lib/main.dart) 在显示窗口之前读取 `SettingsRepository`，在 `initDesktopShell` 完成后立即 `hide`）。
- **Android 前台服务通知动态化**：[Aria2KeepAliveService.kt](android/app/src/main/kotlin/cloud/iothub/aria2down/Aria2KeepAliveService.kt) 支持 `start` / `update` 动作，通知正文实时显示 `↓ down ↑ up  活动 N · 等待 M`；通知按钮提供「显示 / 全部暂停 / 全部继续 / 退出」，点击通知体回到任务列表；活跃任务期间持有 `PARTIAL_WAKE_LOCK`，空闲后释放。
- **Android 控制信号流**：新增 `cloud.iothub.aria2down/keep_alive_control` EventChannel；通知按钮通过 `MainActivity` 转发 `pause_all` / `resume_all` / `show_window` 到 Flutter，由 [`MobileBackgroundBinding`](lib/app/mobile_background_binding.dart) 调用 `Aria2Client.pauseAll/unpauseAll` 或路由到任务列表。
- **iOS 后台时间**：[AppDelegate.swift](ios/Runner/AppDelegate.swift) 进入后台时调用 `beginBackgroundTask`，并注册 `BGAppRefreshTask` (`cloud.iothub.aria2down.bgrefresh`) / `BGProcessingTask` (`cloud.iothub.aria2down.bgprocessing`)；[`Info.plist`](ios/Runner/Info.plist) 声明 `UIBackgroundModes=fetch,processing` 与 `BGTaskSchedulerPermittedIdentifiers`。
- **统一全局统计 Provider**：[`globalStatStreamProvider`](lib/providers/global_stat_provider.dart)（独立 1s/5s 自适应轮询，前后台切换立即唤醒）作为桌面托盘 tooltip、Android 前台通知的唯一数据源，与任务列表页轮询解耦。
- **移动端后台保活开关**：新增 `AppSettings.keepAliveInBackground`（默认开启）；Android 关闭后立即 `stopService`，iOS 仍保留 BGTask 调度（系统决定是否执行）。
- **新 l10n 文案**：`trayNewTask / trayPauseAll / trayResumeAll / trayOpenDownloads / trayToolTipStats / startMinimized(+Desc) / keepAliveInBackground(+Desc) / keepAliveTitle / notifPauseAllDone / notifResumeAllDone`，同时修复 `app_zh.arb` 中 `speedGlobalExtended` 的重复 key。
- **结构变化**：`TrayExitBinding` 迁移到 router 之内并扩展为「桌面托盘所有命令中枢」；新增 [`MobileBackgroundBinding`](lib/app/mobile_background_binding.dart) 负责 Android 通知更新与控制信号订阅；`LibraryDaemon` / `LocalDaemon` 不再直接调 `AndroidKeepAlive`，统一由 binding 根据「daemon 已就绪 + 移动平台 + keepAlive 开关」三件事决策。

### 新增（关联完善 / Linux & Windows portable）

- **Linux 系统级安装脚本**：新增 [scripts/install_linux_associations.sh](scripts/install_linux_associations.sh) 与 [scripts/uninstall_linux_associations.sh](scripts/uninstall_linux_associations.sh)，把 `linux/aria2down.desktop`（含 `MimeType=`）和自定义 MIME XML 安装到 `/usr/share/`（系统级）或 `~/.local/share/`（用户级），并自动调 `update-desktop-database` / `update-mime-database`；可选 `--set-default` 一键把 aria2down 设为 `magnet:` / `.torrent` / `.metalink` / `aria2down://` 的默认处理器。
- **自定义 MIME 注册**：新增 [linux/aria2down-mime.xml](linux/aria2down-mime.xml)，显式声明 `application/metalink+xml`、`application/metalink4+xml`（部分发行版的 shared-mime-info 默认不带），含 `*.metalink` / `*.meta4` glob 与 XML magic 匹配，确保「双击 .metalink」一定能路由到 aria2down。
- **AppImage 关联保留**：[scripts/package_desktop.sh](scripts/package_desktop.sh) 的 AppImage 流程改为直接使用仓库内完整 `aria2down.desktop` + `aria2down-mime.xml`（之前 heredoc 生成的精简 desktop 会丢失 MimeType），配合 AppImageLauncher 安装后能自动注册全部关联。
- **Windows portable 注册表助手**：新增 [scripts/register_windows_associations.ps1](scripts/register_windows_associations.ps1)。MSIX 声明仅对 MSIX 安装包生效，对解压 zip 直接运行的 portable 版无能为力；本脚本以 ProgId 形式（`aria2down.torrent.1` / `.metalink.1` / `.meta4.1`）把 `.torrent` / `.metalink` / `.meta4` 与 `aria2down:` / `magnet:` 两个 URL Protocol 写入 `HKCU\Software\Classes`，无需管理员；文件扩展用 `OpenWithProgids` 不抢系统首选；支持 `-Unregister` 清理。
- **iOS Files App 集成**：`ios/Runner/Info.plist` 增加 `LSSupportsOpeningDocumentsInPlace=true` 与 `UIFileSharingEnabled=true`，从「文件」App / 邮件附件直接把 `.torrent` 用 aria2down 打开（in-place），同时让 aria2down 沙盒目录出现在「我的 iPhone」分组，便于跨 App 转移种子文件。
- **文档**：[docs/DEEPLINKS.md](docs/DEEPLINKS.md) 同步更新 Linux 安装脚本用法、Windows portable 关联注册方法与 iOS 「文件」集成说明。

### 新增（外部唤起 / 跨平台 deep link）

- **`aria2down://` 自定义 Scheme**：所有原生平台统一接口（`aria2down://add?uri=…&uris=…&url=…`、`aria2down://magnet?xt=…`），任意浏览器 / 扩展 / 桌面快捷方式均可唤起本应用并预填新建任务。
- **系统级处理器注册**：
  - **Android**：`intent-filter` 注册 `aria2down`、`magnet`、`.torrent`、`.metalink/.meta4` 与 `ACTION_SEND text/plain` 分享菜单；新增 `cloud.iothub.aria2down/incoming_link` MethodChannel 从 `content://` 读取 torrent 字节；按 app_links 要求关闭 Flutter 内建 deep linking。
  - **iOS / macOS**：`Info.plist` 增加 `CFBundleURLTypes`（`aria2down`、`magnet`）、`CFBundleDocumentTypes` 与 `UTImportedTypeDeclarations`（`.torrent` / `.metalink`，`LSHandlerRank=Alternate` 不抢默认）。
  - **Linux**：`linux/runner/my_application.cc` 改为单实例 + `G_APPLICATION_HANDLES_OPEN`，新增 `linux/aria2down.desktop` 模板，`MimeType=` 注册 `x-scheme-handler/aria2down`、`x-scheme-handler/magnet`、`application/x-bittorrent`、`application/metalink+xml`。
  - **Windows**：`windows/runner/main.cpp` 接入 app_links `SendAppLinkToInstance`，已存在窗口时把 deep link 转发给主实例；`msix_config` 增加 `protocol_activation: aria2down, magnet` 与 `file_extension: .torrent, .metalink, .meta4`。
- **Dart 派发链路**：
  - `lib/core/incoming_link.dart`：纯函数解析 URI / 分享文本，输出 `IncomingUris` / `IncomingFile` / `IncomingUnknown` 三态。
  - `lib/core/incoming_file_loader.dart`：兼容 `file://` 与 Android `content://`（通过 MethodChannel）读取本地字节。
  - `lib/providers/pending_payload_provider.dart`：缓冲未消费的 torrent / metalink 字节，AddTaskPage 首次构建时自动 `addTorrent` / `addMetalink`，多文件 torrent 沿用现有选择对话框。
  - `lib/app/incoming_link_listener.dart`：基于 `app_links` 的 `uriLinkStream` + `getInitialLink` 监听器，挂在 `MaterialApp.router` 之下；路由至 `/add?uri=…` 复用现有预填。
- **依赖**：`app_links: ^6.4.1`。
- **测试**：新增 `test/core/incoming_link_test.dart`（15 用例，覆盖 scheme / magnet / file / content / 分享文本 / 备选键 / 兜底）。
- **文档**：[docs/DEEPLINKS.md](docs/DEEPLINKS.md) 重写为「应用内深链 + 外部唤起」综合手册，含各平台配置、测试命令与浏览器扩展关系说明。

### 重大变更

- **默认下载引擎切换为内嵌 libaria2（ADR-007）**：macOS / Linux / Windows / Android / iOS 五个原生平台均通过 Dart FFI 在应用进程内运行 aria2，下载更快启动、不再依赖随包发布的 `aria2c` 二进制。
- **iOS 现在原生支持本机下载**（取代此前的仅远程模式），通过 `packages/aria2_native` 静态链接 libaria2。
- **设置 → 本机引擎**：新增 **内嵌库 / aria2c 子进程** 切换；默认开启「失败时自动回退到子进程」，确保旧版构建/未带 libaria2 产物的环境仍可工作。

### 变更

- **移动端体验**：首次安装默认本机内嵌引擎；设置页移动端说明卡片与底部保存栏；任务列表 FAB、滑动操作、紧凑统计；添加页 FAB；后台降低轮询频率；更新欢迎与横幅文案（本机下载 + 后台限制说明）；iOS 隐藏子进程引擎选项。

### 修复

- **界面操作延迟数百毫秒**：根因是 `Aria2InProcessTransport` / `LibraryDaemon`
  在主 isolate（Flutter UI 线程）上同步调用 `aria2_ffi_run_once`，进而触发
  libaria2 `DownloadEngine::run(RUN_ONCE)` → `eventPoll_->poll(refreshInterval=1s)`，
  每次都可能阻塞主线程最长 1 秒，与定时器 200ms~800ms 的 tick 叠加后
  几乎持续占用 UI 线程。修复方案：把所有 libaria2 FFI 调用搬到独立 worker
  isolate（`packages/aria2_native/lib/src/worker.dart`），主 isolate 仅通过
  SendPort 异步收发消息；事件回调亦在 worker 内由 `NativeCallable.listener`
  接收后转发回主 isolate。`Aria2NativeSession` 全部 API 改为 `Future<T>`，
  `Aria2InProcessTransport._dispatch` 相应 `await`。worker 自带自适应运行
  循环（活跃 80ms / 空闲 800ms）并在每次变更类 RPC 后立刻 kick 一次，
  无需主 isolate 维护任何 Timer。UI 线程不再因事件循环停顿。
- **macOS 沙盒 / iOS 下载报「Could not contact DNS servers」**：根因是
  aria2 默认使用 c-ares 异步 DNS，沙盒里 `/etc/resolv.conf` 只有 mDNSResponder
  的 loopback stub，c-ares 没有 XPC 通道无法解析。两条 daemon 路径
  （`Aria2ConfigBuilder` / `LibraryDaemon`）默认写入 `async-dns=false`，
  回退到系统 `getaddrinfo`；同时附带 `async-dns-server=1.1.1.1,8.8.8.8,223.5.5.5,119.29.29.29`
  作为用户重新开启异步 DNS 时的兜底。
- **跨平台权限与网络策略**：macOS 沙盒补充 `network.client`、`files.user-selected.read-write`、`files.downloads.read-write`；Android 增加 `network_security_config`、启动前台服务前请求 `POST_NOTIFICATIONS`；iOS 增加 ATS（本地/用户 RPC HTTP）与 `NSLocalNetworkUsageDescription`；Android torrent/metalink 选择使用 `withData` 避免 `path == null`。
- **macOS 启动闪退（io.flutter.ui 线程 SIGSEGV in `SSL_CTX_set_default_verify_paths`）**：根因是
  静态链接的 OpenSSL 3.x 在 macOS 下 `OSSL_PROVIDER_load("legacy")` 走 DSO 路径加载失败，
  aria2 `Platform::setUp` 抛异常但 `initialized_` 标志已置位，二次 `libraryInit` 假成功，
  随后 `SSL_CTX_new` 返回 NULL，aria2 的 `OpenSSLTLSContext` 未守护 NULL 直接 `addSystemTrustedCACerts`。
  改用 **AppleTLS (SecureTransport)** 作为 macOS 上的 TLS 后端，彻底摆脱 OpenSSL 静态 provider 困境。
- **macOS libaria2 链接**：podspec 现链 `Security/CFNetwork/CoreFoundation/SystemConfiguration` framework
  及系统 `expat/zlib/iconv`；不再依赖 OpenSSL 静态库。
- **FFI shim 编译**：将 `b64_decode` / `write_temp` 等返回 `std::string` 的辅助函数移出 `extern "C"` 块，避免 clang 在 macOS 下因 `-Wreturn-type-c-linkage` 报错。
- **`scripts/build_libaria2_macos.sh`**：
  - 切换到 `--without-openssl --with-appletls`，依赖只剩 c-ares / sqlite3；
  - 修复 `build_for_arch` 子函数的 `$(...)` 返回值被 configure/make stdout 污染的隐性 bug
    （所有构建日志显式重定向到 stderr）；
  - 容忍新版 macOS libtool 在 `make libaria2.la` 后处理时偶发的 "File name too long"
    （只要 `src/.libs/libaria2.a` 实际产出即视为成功）；
  - 输出前清理旧的 OpenSSL 残留产物 `deps/libssl.a`、`deps/libcrypto.a`。

### 新增

- **FFI 插件**：`packages/aria2_native` 提供 libaria2 的 C ABI shim + Dart 绑定 + `Aria2NativeSession`（事件流 / 选项 / 查询）。
- **`LibraryDaemon`**：实现 `Aria2Daemon` 抽象，通过 `Aria2InProcessTransport` 把 JSON-RPC 等价请求翻译为 libaria2 调用，使现有 `Aria2Client` / Repository / UI 零改动。
- **构建脚本**：`scripts/build_libaria2_macos.sh`、`_linux.sh`、`_windows.sh`、`_android.sh`、`_ios.sh`，产物落 `packages/aria2_native/prebuilt/<platform>/<arch>/`。
- **CI**：`.github/workflows/build-aria2.yml` 新增 5 套 libaria2 artifact（含 stub 兜底）。
- **文档**：新增 [docs/BUILD_LIBARIA2.md](docs/BUILD_LIBARIA2.md)；重写 [docs/IOS.md](docs/IOS.md)；ARCHITECTURE.md 增加 **ADR-007** 并标记 ADR-001/004 被替代。
- **任务**：长按菜单扩展为 **查看详情 / 打开目录 / 暂停·继续·强制暂停 / 分享**；列表行展示 **errorMessage**（红色提示）。
- **RPC 错误**：`formatRpcError` 识别超时；设置 **导入/远程测试** 失败提示统一友好文案。
- **任务**：长按 **快捷菜单**（GID / URI / 深链）；列表加载失败 **Banner + 重试**；详情展示 **errorMessage**。
- **设置**：保存时 **立即应用下载目录** 到运行中 aria2（`changeGlobalOption`）。
- **日志页**：搜索过滤、复制日志。
- **扩展**：选项页 **Test connection**（`getVersion`）；[docs/EXTENSIONS.md](docs/EXTENSIONS.md)。
- **脚本**：`check_submodule.sh`；CI **每周一** 定时构建。
- **导航**：进行中任务 **角标**（底栏/侧栏）。
- **任务列表**：**粘贴并入队**；批量 **清除已停止记录**（`removeDownloadResult`）；历史 **剪贴板导入**；宽屏 **最大宽度 960**。
- **全局选项**：**复制全部**键值；错误页统一 `formatRpcError`。
- **脚本/文档**：`stage_windows_aria2.ps1`；[docs/QA.md](docs/QA.md) 发版前清单。
- **核心**：`queueUrisToAria2` 统一入队与去重；`formatRpcError` 友好错误提示。
- **任务列表**：剪贴板 **一键跳转新建**；历史 Tab **导出 JSON**；设置 **复制 RPC 地址**。
- **扩展**：右键 **发送当前页面** 到 aria2；`removeDownloadResult` RPC 封装。
- **脚本**：`tag_release.sh`；`build-aria2.yml` 增加 macOS artifact（可选）。
- **任务详情**：按状态 **自适应轮询**（进行中 2s / 暂停 5s / 已结束 10s）。
- **全局选项页**：**搜索**过滤键值。
- **扩展**：共用 `aria2_rpc.js`；Chrome 添加成功/失败 **角标**反馈。
- **Native Messaging**：`install_native_messaging_host.sh` 安装脚本。
- **文档**： [docs/WINDOWS.md](docs/WINDOWS.md)；关于页 **桌面快捷键** 说明；设置 **复制示例深链**。
- **性能**：任务详情/历史 `tellStatus` 使用精简 `keys`；列表轮询 **缓存 aria2 版本**（仅首次/手动刷新拉取）。
- **性能**：任务列表轮询不再拉取 `bitfield` 等大字段；`tellWaiting` 上限 200；WS 事件 **400ms 防抖** + 进行中请求 **合并**，避免重叠 RPC 拖慢 UI。
- **性能**：内嵌库 `aria2_ffi_run_once` **自适应间隔**（活跃 200ms / 空闲 800ms），变更类 RPC 立即唤醒；任务列表 **签名 diff** 跳过无变化的整页重建；移除每行 `Consumer` 包装并将 Theme 与回调上提；任务详情 BT 选项首次后不再重拉、`getPeers` 仅在 Peers Tab 或每 5 轮拉一次。
- **任务列表**：搜索 **250ms 防抖**。
- **桌面快捷键**：⌘/Ctrl+N 打开新建任务。
- **任务详情**：复制 **应用内添加深链**（`/add?uri=`）；[docs/DEEPLINKS.md](docs/DEEPLINKS.md)。
- **新建任务**：宽屏 **双栏布局**（链接 | 操作与高级选项）。
- **Firefox 扩展**：选项页剪贴板导入 RPC JSON（与 Chrome 一致）。
- **CI**：`release.yml` 手动发版校验 + Linux bundle；`prepare_release.sh` 复用 `validate_release.sh`。
- **任务详情**：底部 **暂停 / 继续 / 强制暂停 / 删除 / 重试** 操作栏。
- **深链**：`/add?uri=`、`/add?uris=` 预填新建任务页。
- **RPC 优化**：任务列表 `tell*` 使用精简 `keys`（`task_list_keys.dart`）。
- **设置**：远程 RPC 地址 **快捷预设**（127.0.0.1 / localhost / 0.0.0.0）。
- **Chrome 扩展**：选项页 **从剪贴板导入** aria2down RPC JSON。
- **CI**：macOS 尝试子模块编译 aria2c；**iOS 无签名编译冒烟**。
- **脚本 / 文档**：`scripts/validate_release.sh`、`AGENTS.md`。
- **任务列表**：Tab **数量角标**、空列表 **新建任务** 按钮、长按复制 GID、点击统计条复制全局速度。
- **设置**：**aria2 全局选项** 只读页；本机模式 **复制扩展 RPC 配置**（`rpc.secret`）。
- **CLI / Native Messaging**：`bin/rpc_add_uri.dart`、`bin/native_messaging_host.dart`；`extensions/native-messaging/` 宿主草案。
- **文档**：[docs/DESKTOP.md](docs/DESKTOP.md) 桌面快速参考。
- **设置**：远程 RPC **测试连接**（版本 + WebSocket 探测）。
- **关于页**：显示当前 RPC 地址；本机模式可复制 **RPC Token**。
- **任务**：窄屏 **滑动** 暂停/继续/删除；详情页 **分享/复制** 任务文本。
- **应用**：从后台 **恢复时自动刷新** 任务列表。
- **设置导出**：JSON 含 `appVersion` 与 `exportedAt`。
- **构建/文档**：`build_android_aria2_docker.sh`、`create_github_release.sh`、[docs/IPA.md](docs/IPA.md)；CI Linux 尝试子模块编译 aria2c。
- **扩展**：Native Messaging 方案说明（`extensions/native-messaging/`）。
- **连接**：daemon 启动 **3 次重试**；错误页 **一键切换远程 RPC**；移动/Web **首次欢迎对话框**。
- **新建任务**：跳过队列中 **重复 URI** 并提示跳过数量。
- **设置**：本机日志路径无需启动 daemon（`LocalDaemonPaths`）。
- **构建**：`build_bundle_with_aria2.sh`（编译 + stage + 打包）；`package_msix.sh` + `msix_config`；CI **`build-aria2.yml`** 上传 Linux `aria2c` artifact。
- **扩展**：**Firefox** 草案（`extensions/firefox/`）。
- **任务列表**：WS 连接时轮询降至 30s；进行中按速度、已停止按完成时间排序；**强制全部暂停**、**导出任务快照**（剪贴板 JSON）。
- **设置**：本机模式 **aria2 日志**查看；移动/Web **首次安装默认远程 RPC**。
- **Android**：`Aria2KeepAliveService` 前台服务骨架（`LocalDaemon` 启停联动）。
- **Chrome 扩展草案**：右键链接 `aria2.addUri` + 选项页配置 RPC（`extensions/chrome/`）。
- **URI 智能提取**：从多行文本/剪贴板识别 HTTP(S)/FTP/磁力；**粘贴并添加**一键入队。
- **新建任务**默认使用设置中的下载目录。
- **设置**：**恢复默认**、**关闭 aria2**；全局统计条显示 **已停止** 任务数。
- **任务详情**：复制任务全部下载链接。
- **Web 远程模式**：浏览器端可连接远程 aria2 RPC（本机子进程仍不可用）。
- **连接失败页**：重试、跳转设置；移动/Web **平台提示**横幅。
- **设置**：**当前连接**状态卡片（RPC 地址、WS 是否可用）。
- **桌面快捷键**：⌘/Ctrl+R 刷新任务、⌘/Ctrl+, 打开设置。
- **批量**：删除全部已停止任务。
- **批量任务操作**：全部暂停/继续、清除 aria2 已停止记录；列表显示 **ETA** 与实时速度。
- **新建任务**：**从剪贴板粘贴** 链接。
- **设置**：**立即应用** 全局限速/并发到运行中的 aria2（`changeGlobalOption`）。
- **关于页**：版本、aria2 与 GPLv2 链接（`url_launcher`）。
- **Android 脚手架**：`AndroidBinaryExtractor` + `assets/android/<abi>/aria2c` + `docs/ANDROID.md`。
- **任务历史**：本地 JSON 持久化、任务列表 **「历史」** Tab、WS/轮询自动记录、清空与重试。
- **任务列表**：搜索过滤、下拉刷新、移动端路径复制面板。
- **任务详情**：分块/总体进度条、GID/路径/InfoHash **一键复制**。
- **本机 aria2**：进程异常退出后约 **3 秒自动重启**（保留 session）。
- **远程 RPC 模式**：`RemoteDaemon` + 设置页连接切换（`host:port` / URL + token）。
- **设置增强**：全局/并发限速写入本机 `aria2.conf`、关闭到托盘/最小化到托盘开关、**开机自启**（`launch_at_startup`）。
- **设置导入/导出**：JSON 备份（桌面可另存为文件，其它平台复制到剪贴板）。
- **桌面托盘**：菜单与提示文案接入 l10n；关闭行为可配置（关闭到托盘 vs 直接退出）。

### 变更

- `localDaemonProvider` 由 `aria2DaemonProvider` 统一本地/远程连接（旧名仍 export 兼容）。

### 文档 / 构建

- [docs/BUILD_ARIA2.md](docs/BUILD_ARIA2.md)、[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)；`scripts/print_release_notes.sh`。
- 新增 [docs/IOS.md](docs/IOS.md)（iOS 可行性：推荐远程模式）。
- Linux 打包可选 **AppImage**（`appimagetool`）；CI：**format check**、**macOS/Windows bundle** artifacts。
- `scripts/build_aria2.sh`、`scripts/stage_android_aria2.sh`；`extensions/README.md`（浏览器扩展使用说明）。

---

## [0.1.0] - 未发布

> 对应规划中的 **MVP（Phase 0～3）** 桌面优先版本；**尚未打 Git 标签** 时仍视为未发布。

### 新增

- 本机启动 **aria2c**（`LocalDaemon`）、**JSON-RPC HTTP** 客户端与可选 **WebSocket** 任务刷新。
- **任务列表**（进行中 / 等待 / 已停止）、**新建** HTTP(S)/磁力/.torrent/Metalink、**设置**（主题、语言、默认目录、aria2c 路径）。
- **任务详情**：概览、多文件选择、`tellStatus` BT 字段、**announce 分层**、**peers**、**getOption** 节选（DHT / LPD 等）。
- **国际化**：简体中文 / English。
- **桌面**：在文件管理器中打开下载位置；**Web**：将保存路径复制到剪贴板。
- **构建与 CI**：`scripts/build_desktop.sh`、`package_desktop.sh`、`stage_aria2c.sh`；GitHub Actions **`linux-release-bundle`** 产出带 **同目录 `aria2c`** 的 Linux bundle artifact。
- **命令行示例**：`bin/cli_demo.dart`（需本机 `aria2c`）。

### 说明

- 许可证：**GPLv2+**（与 aria2 一致）；分发二进制须遵守许可证并提供源码获取方式。
- 各平台 **aria2c** 的编译与嵌入策略见 [docs/BUILD.md](docs/BUILD.md)；发版检查清单见 [docs/RELEASE.md](docs/RELEASE.md)。
