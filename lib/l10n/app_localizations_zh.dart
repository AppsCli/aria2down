// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'aria2down';

  @override
  String get navTasks => '任务';

  @override
  String get navAdd => '新建';

  @override
  String get navSettings => '设置';

  @override
  String get loadingAria2 => '正在启动 aria2…';

  @override
  String get loadingRemoteAria2 => '正在连接远程 aria2…';

  @override
  String get loadingSettings => '正在加载设置…';

  @override
  String get settingsTitle => '设置';

  @override
  String get appearance => '外观';

  @override
  String get theme => '主题';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get language => '语言';

  @override
  String get langSystem => '跟随系统';

  @override
  String get langEnglish => 'English';

  @override
  String get langChinese => '简体中文';

  @override
  String get downloadDirectory => '默认下载目录';

  @override
  String get downloadDirectoryPick => '选择文件夹';

  @override
  String get downloadDirectoryClear => '使用系统默认';

  @override
  String get aria2BinaryPath => 'aria2c 路径（可选）';

  @override
  String get aria2BinaryHint => '留空则从 PATH 查找';

  @override
  String get save => '保存';

  @override
  String get restartAria2Hint => '修改路径后 aria2 将自动重启以生效。';

  @override
  String get tasksTitle => '任务';

  @override
  String get tabActive => '进行中';

  @override
  String get tabWaiting => '等待';

  @override
  String get tabStopped => '已停止';

  @override
  String get tabHistory => '历史';

  @override
  String get emptyHistory => '暂无本地历史记录';

  @override
  String get searchTasks => '搜索任务';

  @override
  String get searchTasksHint => '按名称或 GID 过滤';

  @override
  String get refreshTasks => '刷新';

  @override
  String get historyClearTitle => '清空历史';

  @override
  String get historyClearMessage => '将删除本机保存的已结束任务记录，不影响 aria2 当前队列。';

  @override
  String get historyClearConfirm => '清空';

  @override
  String get mobilePathSheetTitle => '保存路径';

  @override
  String get mobilePathCopied => '路径已复制到剪贴板';

  @override
  String get copyPath => '复制路径';

  @override
  String get snackCopied => '已复制';

  @override
  String get copyValue => '复制';

  @override
  String get taskDetailPieceProgress => '分块完成度';

  @override
  String get taskDetailOverallProgress => '总体进度';

  @override
  String speedGlobal(String down, String up, int active, int waiting) {
    return '↓ $down  ↑ $up  活动 $active  等待 $waiting';
  }

  @override
  String speedGlobalExtended(
    String down,
    String up,
    int active,
    int waiting,
    int stopped,
  ) {
    return '↓ $down  ↑ $up  活动 $active  等待 $waiting  已停止 $stopped';
  }

  @override
  String aria2Version(String version) {
    return 'aria2 $version';
  }

  @override
  String get wsConnected => 'WebSocket 通知已连接';

  @override
  String get wsPolling => 'WebSocket 不可用，使用定时刷新';

  @override
  String get emptyActive => '暂无进行中的任务';

  @override
  String get emptyWaiting => '暂无等待中的任务';

  @override
  String get emptyStopped => '暂无已停止任务';

  @override
  String get hintUrls => '输入 HTTP(S) / FTP / 磁力 链接，多个可用空格或换行分隔';

  @override
  String get addButton => '添加';

  @override
  String get snackAdded => '已添加下载任务';

  @override
  String snackAddFailed(String error) {
    return '添加失败：$error';
  }

  @override
  String get snackInvalidUrl => '未识别到有效下载链接';

  @override
  String get snackSaved => '设置已保存';

  @override
  String get advancedOptions => '高级选项…';

  @override
  String get userAgent => 'User-Agent';

  @override
  String get headersHint => 'HTTP 头，每行一条：Name: Value';

  @override
  String get cookie => 'Cookie 值（可选，将作为 Cookie: 头发送）';

  @override
  String get speedLimitHint => '单任务限速（aria2 max-download-limit），如 2M、500K';

  @override
  String get pickTorrent => '选择 .torrent';

  @override
  String get pickMetalink => '选择 Metalink（.metalink / .meta4）';

  @override
  String get retry => '重试';

  @override
  String get openFolder => '打开目录';

  @override
  String get openFolderWebCopied =>
      '已将保存路径复制到剪贴板（浏览器无法打开本机目录；路径为 aria2 服务端视角）。';

  @override
  String get openFolderFailed => '无法打开文件夹';

  @override
  String get openFolderMobileDirOnly =>
      '移动设备无法在系统文件管理器中仅打开目录；请等待文件下载完成后通过「打开」已存在的文件进入。';

  @override
  String get openFileFailed => '无法打开文件（路径无效、无可用应用或权限不足）。';

  @override
  String get snackRetryQueued => '已重新加入下载队列';

  @override
  String get snackNothingToRetry => '该任务没有可重试的链接';

  @override
  String get torrentNote => '种子 / Metalink 仅通过本机 RPC 传给 aria2。';

  @override
  String get dialogCancel => '取消';

  @override
  String get torrentSelectDialogTitle => '选择要下载的文件';

  @override
  String get torrentSelectDialogConfirm => '添加';

  @override
  String get about => '关于';

  @override
  String get aboutDesc => '基于 aria2 的跨平台下载客户端。';

  @override
  String appVersionLabel(String version) {
    return '版本 $version';
  }

  @override
  String get folderPickerUnavailable => '当前平台不支持文件夹选择，请手动输入路径（后续版本）。';

  @override
  String get taskDetailTitle => '任务详情';

  @override
  String taskDetailLoadFailed(String error) {
    return '加载失败：$error';
  }

  @override
  String get taskDetailTabOverview => '概览';

  @override
  String get taskDetailTabFiles => '文件';

  @override
  String get taskDetailTabTorrent => 'BT';

  @override
  String get taskDetailFieldGid => 'GID';

  @override
  String get taskDetailFieldStatus => '状态';

  @override
  String get taskDetailFieldDir => '目录';

  @override
  String get taskDetailFieldTotal => '总大小';

  @override
  String get taskDetailFieldCompleted => '已完成';

  @override
  String get taskDetailFieldUploadLength => '已上传';

  @override
  String get taskDetailFieldDownloadSpeed => '下载速度';

  @override
  String get taskDetailFieldUploadSpeed => '上传速度';

  @override
  String get taskDetailFieldConnections => '连接数';

  @override
  String get taskDetailFieldPieces => '分块';

  @override
  String get taskDetailFieldBitfield => '分块位图（hex）';

  @override
  String taskDetailPieceSummary(String count, String pieceSize) {
    return '$count 块 × $pieceSize';
  }

  @override
  String get taskDetailFieldError => '错误';

  @override
  String get taskDetailNoFiles => '无文件项';

  @override
  String taskDetailFileProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String taskDetailFileProgressSelected(
    String done,
    String total,
    String selected,
  ) {
    return '$done / $total · selected=$selected';
  }

  @override
  String get taskDetailNotTorrent => '此任务不是 BitTorrent 下载。';

  @override
  String get taskDetailTorrentName => '种子名称';

  @override
  String get taskDetailTorrentMode => '模式';

  @override
  String get taskDetailAnnounceList => 'Tracker / announce';

  @override
  String taskDetailAnnounceTier(int tier) {
    return '第 $tier 组';
  }

  @override
  String get taskDetailBtMetricsTitle => '传输与连接';

  @override
  String get taskDetailFieldInfoHash => 'InfoHash';

  @override
  String get taskDetailFieldNumSeeders => 'Tracker 汇报种子数';

  @override
  String get taskDetailFieldLocalSeeder => '本机为做种端';

  @override
  String get taskDetailFieldBtConnections => '当前连接数';

  @override
  String get taskDetailTrackerRpcNote =>
      'aria2 JSON-RPC 不提供各 Tracker 的单独状态；以下为任务级字段。';

  @override
  String get taskDetailBtRpcOptionsTitle => 'BitTorrent 选项（getOption）';

  @override
  String get taskDetailBtRpcOptionsNote => '以下为当前任务在 aria2 中的生效值。';

  @override
  String get taskDetailOptionEnableDht => 'DHT（IPv4）';

  @override
  String get taskDetailOptionEnableDht6 => 'DHT（IPv6）';

  @override
  String get taskDetailOptionBtEnableLpd => '本地 peer 发现（LPD）';

  @override
  String get taskDetailBoolYes => '是';

  @override
  String get taskDetailBoolNo => '否';

  @override
  String get taskDetailNoAnnounces => '无 announce 列表';

  @override
  String taskDetailPeersTitle(int count) {
    return 'Peers（$count）';
  }

  @override
  String get taskDetailPeersEmpty => '暂无 peer 数据（可能尚未连接或任务已结束）。';

  @override
  String get taskDetailPeerDown => '下行';

  @override
  String get taskDetailPeerUp => '上行';

  @override
  String get taskDetailSelectFilesHint =>
      '勾选要下载的文件后点击下方按钮应用到 aria2（等待/暂停/进行中任务）。';

  @override
  String get taskDetailApplyFileSelection => '应用文件选择';

  @override
  String taskDetailFileSelectionApplyFailed(String error) {
    return '应用失败：$error';
  }

  @override
  String get taskDetailNeedOneFileSelected => '请至少保留一个文件为选中状态。';

  @override
  String get taskDetailFileSelectionSaved => '文件选择已应用。';

  @override
  String get settingsConnection => '连接';

  @override
  String get connectionLocal => '本机 aria2';

  @override
  String get connectionRemote => '远程 RPC';

  @override
  String get settingsEngine => '本机引擎';

  @override
  String get engineLibrary => '内嵌库（libaria2）';

  @override
  String get engineSubprocess => 'aria2c 子进程';

  @override
  String get engineLibraryDesc =>
      '通过 Dart FFI 在进程内运行 aria2。内存更省、支持 iOS、无需附带额外二进制。';

  @override
  String get engineSubprocessDesc => '启动随包发布的 aria2c 可执行文件，适合作为内嵌库初始化失败时的兜底。';

  @override
  String get engineFallbackToSubprocess => '失败时自动回退到子进程';

  @override
  String get engineFallbackToSubprocessDesc => '内嵌引擎启动失败时，自动改用 aria2c 子进程重试。';

  @override
  String get engineUnavailableBanner => '当前构建未链接内嵌引擎，已回退到子进程。';

  @override
  String engineInitFailed(String error) {
    return '内嵌引擎启动失败：$error';
  }

  @override
  String engineCurrent(String engine) {
    return '当前引擎：$engine';
  }

  @override
  String get engineLibraryShort => '内嵌库';

  @override
  String get engineSubprocessShort => '子进程';

  @override
  String get engineRemoteShort => '远程';

  @override
  String get remoteRpcEndpoint => 'RPC 地址';

  @override
  String get remoteRpcEndpointHint =>
      '例如 127.0.0.1:6800 或 http://nas:6800/jsonrpc';

  @override
  String get remoteRpcSecret => 'RPC 密钥（token）';

  @override
  String get remoteModeHint => '远程模式不会启动本机子进程；请确保对方 aria2 已开启 RPC 且密钥一致。';

  @override
  String get settingsDownloadTuning => '下载参数（写入本机 aria2.conf）';

  @override
  String get settingsOptionalHint => '留空使用 aria2 默认';

  @override
  String get maxConcurrentDownloads => '最大同时下载数';

  @override
  String get maxConnectionPerServer => '单服务器最大连接数';

  @override
  String get globalDownloadLimit => '全局下载限速';

  @override
  String get globalUploadLimit => '全局上传限速';

  @override
  String get settingsTuningLocalOnly => '以下参数仅在「本机 aria2」模式下写入配置文件。';

  @override
  String get settingsDesktop => '桌面行为';

  @override
  String get closeToTray => '关闭窗口时最小化到托盘';

  @override
  String get closeToTrayDesc => '关闭按钮隐藏主窗口；在托盘菜单选择「退出」才会结束应用。';

  @override
  String get minimizeToTray => '最小化到托盘';

  @override
  String get minimizeToTrayDesc => '最小化时隐藏主窗口（否则为普通最小化）。';

  @override
  String get launchAtStartup => '开机自启';

  @override
  String get launchAtStartupDesc => '登录系统时自动启动 aria2down（需平台权限）。';

  @override
  String get settingsBackup => '备份与恢复';

  @override
  String get settingsExport => '导出设置';

  @override
  String get settingsImport => '导入设置';

  @override
  String get settingsExportCopied => '设置 JSON 已复制到剪贴板';

  @override
  String settingsExportSaved(String path) {
    return '设置已保存到 $path';
  }

  @override
  String get settingsImportApplied => '已载入设置，请点击「保存」或继续编辑后保存。';

  @override
  String settingsImportFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String get trayShowWindow => '显示主窗口';

  @override
  String get trayQuit => '退出';

  @override
  String get trayToolTip => 'aria2down — 点击显示窗口';

  @override
  String get tasksBatchMenu => '批量操作';

  @override
  String get batchPauseAll => '全部暂停';

  @override
  String get batchForcePauseAll => '强制全部暂停';

  @override
  String get batchExportTasks => '导出任务快照';

  @override
  String get batchExportTasksDone => '任务快照已复制到剪贴板';

  @override
  String get batchUnpauseAll => '全部继续';

  @override
  String get settingsDiagnostics => '诊断';

  @override
  String get aria2LogTitle => 'aria2 日志';

  @override
  String get aria2LogSubtitle => '查看本机 aria2 日志文件末尾';

  @override
  String get aria2LogEmpty => '日志文件为空或尚未生成。';

  @override
  String get batchPurgeStopped => '清除已停止记录';

  @override
  String get snackBatchDone => '批量操作已完成';

  @override
  String get pasteFromClipboard => '从剪贴板粘贴';

  @override
  String get clipboardEmpty => '剪贴板为空';

  @override
  String get applyRuntimeLimits => '立即应用到运行中的 aria2';

  @override
  String get applyRuntimeLimitsHint => '无需重启即可调整全局限速与并发（本机/远程均可用）。';

  @override
  String get applyRuntimeLimitsDone => '运行中选项已更新';

  @override
  String get applyRuntimeLimitsEmpty => '请先填写至少一项限速或并发参数';

  @override
  String get aboutTitle => '关于 aria2down';

  @override
  String get aboutOpenDetail => '版本、许可证与项目链接';

  @override
  String get aboutPoweredBy => '下载引擎';

  @override
  String get aboutLicense => '许可证';

  @override
  String get aboutLicenseBody => '本项目基于 GPLv2+ 发布，与 aria2 许可证兼容。';

  @override
  String get aboutLicenseLink => 'GNU GPLv2 全文';

  @override
  String get platformHintMessage =>
      '本设备建议连接远程 aria2（NAS / 本机已运行的 aria2 RPC），在设置中切换为「远程 RPC」并填写地址。';

  @override
  String get platformHintOpenSettings => '打开设置';

  @override
  String get platformHintDismiss => '不再提示';

  @override
  String get daemonErrorTitle => '无法连接 aria2';

  @override
  String get daemonErrorBinaryNotFound =>
      '未找到 aria2c。请安装 aria2、在设置中指定路径，或将预编译二进制放入 assets；也可改用远程 RPC。';

  @override
  String get daemonErrorWebLocal =>
      '浏览器无法启动本机 aria2。请在设置中使用「远程 RPC」连接已开启 RPC 的 aria2 服务。';

  @override
  String get daemonErrorRetry => '重试连接';

  @override
  String get daemonErrorSwitchRemote => '切换到远程 RPC';

  @override
  String get welcomeRemoteTitle => '欢迎使用 aria2down';

  @override
  String get welcomeRemoteBody =>
      '在本设备上请连接已在运行的 aria2（NAS、电脑或服务器）。打开「设置」→「远程 RPC」，填写地址与 Token。';

  @override
  String get snackAllDuplicates => '这些链接已在队列中';

  @override
  String snackAddedWithSkipped(int added, int skipped) {
    return '已添加 $added 个，跳过 $skipped 个重复';
  }

  @override
  String get batchRemoveStopped => '删除全部已停止任务';

  @override
  String get delete => '删除';

  @override
  String get swipeDeleteTitle => '删除任务？';

  @override
  String get swipeDeleteMessage => '将从 aria2 队列中移除该任务（除非配置了删除时删文件，否则磁盘文件保留）。';

  @override
  String get remoteTestConnection => '测试连接';

  @override
  String remoteTestOk(String version, String ws) {
    return '已连接 — aria2 $version，WebSocket：$ws';
  }

  @override
  String remoteTestFailed(String error) {
    return '连接失败：$error';
  }

  @override
  String get aboutRpcInfo => '当前 RPC';

  @override
  String get aboutRpcSecretHint => 'RPC Token（供本机扩展/远程客户端使用）：';

  @override
  String get taskShare => '复制分享文本';

  @override
  String get aria2GlobalOptionsTitle => 'aria2 全局选项';

  @override
  String get aria2GlobalOptionsSubtitle => '查看运行中 aria2 的全局配置（只读）';

  @override
  String get copyRpcConfigTitle => '复制扩展用 RPC 配置';

  @override
  String get copyRpcConfigSubtitle => '供 Chrome 扩展选项页粘贴（需曾启动过本机 aria2）';

  @override
  String get copyRpcConfigDone => 'RPC 配置已复制到剪贴板';

  @override
  String get copyRpcConfigUnavailable => '请先启动一次本机 aria2 以生成 rpc.secret';

  @override
  String get taskActionPause => '暂停';

  @override
  String get taskActionResume => '继续';

  @override
  String get taskActionForcePause => '强制暂停';

  @override
  String get settingsWebRemoteOnly => 'Web 端仅支持远程 RPC 模式。';

  @override
  String get connectionStatusTitle => '当前连接';

  @override
  String get connectionStatusLoading => '正在连接…';

  @override
  String get connectionStatusOffline => '未连接';

  @override
  String connectionStatusWs(String status) {
    return 'WebSocket 通知：$status';
  }

  @override
  String get desktopShortcutRefresh => '刷新任务列表';

  @override
  String get desktopShortcutSettings => '打开设置';

  @override
  String get pasteAndAdd => '粘贴并添加';

  @override
  String snackAddedCount(int count) {
    return '已添加 $count 个任务';
  }

  @override
  String get copyTaskUris => '复制全部链接';

  @override
  String get settingsDangerZone => '高级 / 危险操作';

  @override
  String get shutdownAria2 => '关闭 aria2 进程';

  @override
  String get shutdownAria2Title => '关闭 aria2？';

  @override
  String get shutdownAria2Message => '将优雅关闭 aria2 守护进程；进行中的任务会停止。应用可稍后重新连接。';

  @override
  String get shutdownAria2Confirm => '关闭';

  @override
  String get shutdownAria2Done => 'aria2 已关闭';

  @override
  String get resetSettings => '恢复默认设置';

  @override
  String get resetSettingsTitle => '恢复默认设置？';

  @override
  String get resetSettingsMessage => '将清除所有应用设置（不含任务历史文件）。aria2 将重新连接。';

  @override
  String get resetSettingsConfirm => '恢复';

  @override
  String get resetSettingsDone => '已恢复默认设置';

  @override
  String get copyAddTaskLink => '复制应用内添加链接';

  @override
  String get taskContextViewDetail => '查看详情';

  @override
  String get desktopShortcutAdd => '新建下载任务';

  @override
  String get aboutDesktopShortcuts => '键盘快捷键（桌面）';

  @override
  String get globalOptionsSearchHint => '搜索选项…';

  @override
  String get copyDeepLinkExampleTitle => '复制示例添加链接';

  @override
  String get copyDeepLinkExampleSubtitle =>
      '应用内路径如 /add?uri=…，详见 docs/DEEPLINKS.md';

  @override
  String get copyDeepLinkExampleDone => '已复制示例深链';

  @override
  String get rpcErrorConnection =>
      '无法连接 aria2 RPC。请确认 aria2 已运行，并检查设置中的 RPC 地址。';

  @override
  String get rpcErrorUnauthorized => 'RPC 拒绝了请求。请检查设置中的 Token / 密钥是否正确。';

  @override
  String rpcErrorGeneric(String error) {
    return '请求失败：$error';
  }

  @override
  String get copyRpcEndpoint => '复制 RPC 地址';

  @override
  String get batchExportHistory => '导出历史（JSON）';

  @override
  String get batchExportHistoryDone => '任务历史已复制到剪贴板';

  @override
  String get batchClearStoppedResults => '清除已停止记录（保留文件）';

  @override
  String get pasteAndQueue => '粘贴并入队';

  @override
  String get batchImportHistory => '从剪贴板导入历史';

  @override
  String historyImportDone(int count) {
    return '已导入 $count 条历史记录';
  }

  @override
  String historyImportFailed(String error) {
    return '历史导入失败：$error';
  }

  @override
  String get copyGlobalOptions => '复制全部选项';

  @override
  String get copyGlobalOptionsDone => '全局选项已复制到剪贴板';

  @override
  String get aboutBrowserExtension => '浏览器扩展';

  @override
  String get aboutBrowserExtensionHint => '见仓库 extensions/README.md';

  @override
  String get aria2LogSearchHint => '搜索日志行…';

  @override
  String get aria2LogNoMatch => '没有匹配的日志行。';
}
