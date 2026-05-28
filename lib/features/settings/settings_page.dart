import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart' show kDefaultSeedColor;
import '../../core/platform_hints.dart';
import '../../core/rpc_error_message.dart';
import '../../core/app_deep_link.dart';
import '../../core/remote_rpc_probe.dart';
import '../../data/app_settings.dart';
import '../../data/settings_export.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/aria2_daemon_provider.dart';
import '../../providers/connection_info_provider.dart'
    show ActiveEngine, ConnectionInfo, connectionInfoProvider;
import '../../providers/library_capabilities_provider.dart';
import '../about/about_page.dart';
import 'aria2_global_options_page.dart';
import 'aria2_log_page.dart';

/// 设置页：所有控件**改即生效**，没有显式「保存」按钮。
///
/// - 开关 / SegmentedButton / Dropdown / 主题色 / 下载目录选择器：每次点击直接
///   写入 [appSettingsProvider]（先发布到内存 `state` → UI 立刻响应，再异步
///   持久化）。
/// - 文本框（远程端点 / Secret / 并发数 / 限速等）：用 [FocusNode] 监听失焦，
///   或按回车 `onSubmitted` 时一次性提交，避免每按一个键就重启 aria2 / 重连
///   远程 RPC。
/// - 导入 / 重置走 [AppSettingsNotifier.update] / [AppSettingsNotifier.resetToDefaults]
///   后再同步更新本地文本控制器，让用户即刻看到变化。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(appSettingsProvider)
        .when(
          // 不再使用 `key: ValueKey(s)`：那样会让每次 notifier.update() 把
          // 整个 _SettingsForm 销毁重建，破坏 TextField 焦点 / 光标位置。
          // 现在表单常驻，靠局部 watch + 文本控制器自我同步。
          data: (_) => const _SettingsForm(),
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
        );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm();

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

String _engineLabel(AppLocalizations l10n, ConnectionInfo c) {
  final modeLabel = c.mode == ConnectionMode.local
      ? l10n.connectionLocal
      : l10n.connectionRemote;
  final engineLabel = switch (c.engine) {
    ActiveEngine.library => l10n.engineLibraryShort,
    ActiveEngine.remote => l10n.engineRemoteShort,
  };
  return '$modeLabel · ${l10n.engineCurrent(engineLabel)}';
}

/// 库引擎功能受限提示：仅当 [libraryCapabilitiesProvider] 报告缺失任何标记的
/// 能力时显示——告知用户「prebuilt libaria2 缺补丁，请重编」。
class _LibraryCapabilitiesWarning extends ConsumerWidget {
  const _LibraryCapabilitiesWarning();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(libraryCapabilitiesProvider);
    final caps = async.valueOrNull;
    if (caps == null) return const SizedBox.shrink();
    final missing = LibraryCapability.all.difference(caps);
    if (missing.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final t = Theme.of(context);
    final labels = missing
        .map((c) => _localizedCapability(l10n, c))
        .where((s) => s.isNotEmpty)
        .join('、');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: t.colorScheme.errorContainer.withValues(alpha: 0.35),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_outlined, color: t.colorScheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.libraryCapabilitiesDegradedTitle,
                      style: t.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.libraryCapabilitiesDegradedBody(labels),
                      style: t.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _localizedCapability(AppLocalizations l10n, String cap) {
    switch (cap) {
      case LibraryCapability.removeDownloadResult:
        return l10n.libraryCapabilityRemoveDownloadResult;
      case LibraryCapability.listReserved:
        return l10n.libraryCapabilityListReserved;
      case LibraryCapability.listDownloadResults:
        return l10n.libraryCapabilityListDownloadResults;
      case LibraryCapability.downloadHandleExt:
        return l10n.libraryCapabilityDownloadHandleExt;
      default:
        return '';
    }
  }
}

class _ConnectionStatusCard extends ConsumerWidget {
  const _ConnectionStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final info = ref.watch(connectionInfoProvider);
    return info.when(
      loading: () => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          l10n.connectionStatusLoading,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          l10n.connectionStatusOffline,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      data: (c) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Card(
          child: ListTile(
            leading: Icon(c.wsAvailable ? Icons.link : Icons.link_off),
            title: Text(l10n.connectionStatusTitle),
            subtitle: Text(
              '${_engineLabel(l10n, c)}\n'
              '${c.httpEndpoint}\n'
              '${l10n.connectionStatusWs(c.wsAvailable ? l10n.taskDetailBoolYes : l10n.taskDetailBoolNo)}',
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: l10n.copyRpcEndpoint,
              icon: const Icon(Icons.copy_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: c.httpEndpoint));
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l10n.snackCopied)));
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  // --- 文本控制器（含远程端点 / Secret + 4 个调优数值） ---
  late final TextEditingController _remoteEndpointCtrl;
  late final TextEditingController _remoteSecretCtrl;
  late final TextEditingController _maxConcurrentCtrl;
  late final TextEditingController _maxConnCtrl;
  late final TextEditingController _dlLimitCtrl;
  late final TextEditingController _ulLimitCtrl;

  // --- 焦点节点：失焦时把当前文本提交到 [appSettingsProvider] ---
  late final FocusNode _remoteEndpointFocus;
  late final FocusNode _remoteSecretFocus;
  late final FocusNode _maxConcurrentFocus;
  late final FocusNode _maxConnFocus;
  late final FocusNode _dlLimitFocus;
  late final FocusNode _ulLimitFocus;

  bool _testingRemote = false;

  bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  @override
  void initState() {
    super.initState();
    // 首次 build 之前，先从 provider 当前 value 里抓初值——SettingsPage 在
    // `.when(data:)` 分支内创建本表单，所以 `.valueOrNull` 一定非空。
    final s = ref.read(appSettingsProvider).valueOrNull ?? const AppSettings();
    _remoteEndpointCtrl = TextEditingController(
      text: s.remoteRpcEndpoint ?? '127.0.0.1:6800',
    );
    _remoteSecretCtrl = TextEditingController(text: s.remoteRpcSecret ?? '');
    _maxConcurrentCtrl = TextEditingController(
      text: s.maxConcurrentDownloads?.toString() ?? '',
    );
    _maxConnCtrl = TextEditingController(
      text: s.maxConnectionPerServer?.toString() ?? '',
    );
    _dlLimitCtrl = TextEditingController(text: s.globalDownloadLimit ?? '');
    _ulLimitCtrl = TextEditingController(text: s.globalUploadLimit ?? '');

    // 失焦提交：用户 Tab / 点别处 / 关键盘时把当前文本一次性写到设置。
    // 比每个 onChanged 都重启 aria2 友好得多。
    _remoteEndpointFocus = FocusNode()..addListener(_onTextFocusChanged);
    _remoteSecretFocus = FocusNode()..addListener(_onTextFocusChanged);
    _maxConcurrentFocus = FocusNode()..addListener(_onTextFocusChanged);
    _maxConnFocus = FocusNode()..addListener(_onTextFocusChanged);
    _dlLimitFocus = FocusNode()..addListener(_onTextFocusChanged);
    _ulLimitFocus = FocusNode()..addListener(_onTextFocusChanged);
  }

  @override
  void dispose() {
    _remoteEndpointCtrl.dispose();
    _remoteSecretCtrl.dispose();
    _maxConcurrentCtrl.dispose();
    _maxConnCtrl.dispose();
    _dlLimitCtrl.dispose();
    _ulLimitCtrl.dispose();
    _remoteEndpointFocus.dispose();
    _remoteSecretFocus.dispose();
    _maxConcurrentFocus.dispose();
    _maxConnFocus.dispose();
    _dlLimitFocus.dispose();
    _ulLimitFocus.dispose();
    super.dispose();
  }

  /// 任意文本框失焦时统一调一次——逐字段对比，把改动一并写盘。
  void _onTextFocusChanged() {
    if (_anyTextFieldFocused) return;
    _commitTextFields();
  }

  bool get _anyTextFieldFocused =>
      _remoteEndpointFocus.hasFocus ||
      _remoteSecretFocus.hasFocus ||
      _maxConcurrentFocus.hasFocus ||
      _maxConnFocus.hasFocus ||
      _dlLimitFocus.hasFocus ||
      _ulLimitFocus.hasFocus;

  /// 把所有文本框当前值合并到 [appSettingsProvider]——文本字段是「提交时」
  /// 同步，逐字段对比避免无谓重启。
  Future<void> _commitTextFields() async {
    final current = ref.read(appSettingsProvider).valueOrNull;
    if (current == null) return;
    final ep = _remoteEndpointCtrl.text.trim();
    final sec = _remoteSecretCtrl.text.trim();
    final mc = _parsePositiveInt(_maxConcurrentCtrl.text);
    final mcps = _parsePositiveInt(_maxConnCtrl.text);
    final dl = _dlLimitCtrl.text.trim();
    final ul = _ulLimitCtrl.text.trim();

    final next = AppSettings(
      connectionMode: current.connectionMode,
      remoteRpcEndpoint: current.connectionMode == ConnectionMode.remote
          ? (ep.isEmpty ? null : ep)
          : current.remoteRpcEndpoint,
      remoteRpcSecret: current.connectionMode == ConnectionMode.remote
          ? (sec.isEmpty ? null : sec)
          : current.remoteRpcSecret,
      downloadDirectoryOverride: current.downloadDirectoryOverride,
      askDownloadDirEachTime: current.askDownloadDirEachTime,
      theme: current.theme,
      seedColorArgb: current.seedColorArgb,
      locale: current.locale,
      closeToTray: current.closeToTray,
      minimizeToTray: current.minimizeToTray,
      launchAtStartup: current.launchAtStartup,
      startMinimized: current.startMinimized,
      keepAliveInBackground: current.keepAliveInBackground,
      maxConcurrentDownloads: mc,
      maxConnectionPerServer: mcps,
      globalDownloadLimit: dl.isEmpty ? null : dl,
      globalUploadLimit: ul.isEmpty ? null : ul,
    );
    await ref.read(appSettingsProvider.notifier).set(next);
  }

  static int? _parsePositiveInt(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    if (n == null || n < 1) return null;
    return n;
  }

  /// 把外部对 [appSettingsProvider] 的更改（导入 / 重置 / 其它页面写入）同步
  /// 回本表单的文本控制器；只在控件未持有焦点 + 实际差异时改写，避免抢用户
  /// 正在输入的光标。
  void _syncControllersFrom(AppSettings s) {
    void sync(TextEditingController c, FocusNode f, String desired) {
      if (f.hasFocus) return;
      if (c.text == desired) return;
      c.text = desired;
    }

    sync(
      _remoteEndpointCtrl,
      _remoteEndpointFocus,
      s.remoteRpcEndpoint ?? '127.0.0.1:6800',
    );
    sync(_remoteSecretCtrl, _remoteSecretFocus, s.remoteRpcSecret ?? '');
    sync(
      _maxConcurrentCtrl,
      _maxConcurrentFocus,
      s.maxConcurrentDownloads?.toString() ?? '',
    );
    sync(
      _maxConnCtrl,
      _maxConnFocus,
      s.maxConnectionPerServer?.toString() ?? '',
    );
    sync(_dlLimitCtrl, _dlLimitFocus, s.globalDownloadLimit ?? '');
    sync(_ulLimitCtrl, _ulLimitFocus, s.globalUploadLimit ?? '');
  }

  /// 弹一个对话框让用户输入十六进制颜色（`#RRGGBB` 或 `#AARRGGBB`）。
  ///
  /// 不引入完整 color picker 依赖：99% 的用户在 8 个预设色板里能选到合适
  /// 的；个别强诉求（"我想要公司品牌色"）通过 hex 文本直接输入即可，键盘
  /// 操作也比拖色块拾色精确。返回 null 表示用户取消或输入无效。
  Future<void> _pickCustomSeedColor(AppLocalizations l10n) async {
    final current = ref.read(appSettingsProvider).valueOrNull;
    final currentArgb = current?.seedColorArgb;
    // 用户输入习惯用 #RRGGBB，把默认 0xFF Alpha 隐去更短。如果当前色已经
    // 是非 0xFF Alpha（来自备份导入），保持 8 位 hex 让 round-trip 一致。
    String initial = '';
    if (currentArgb != null) {
      final hex = currentArgb.toRadixString(16).padLeft(8, '0');
      initial = hex.startsWith('ff') ? hex.substring(2) : hex;
    }
    final ctrl = TextEditingController(text: initial);
    final argb = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(l10n.themeSeedColorCustomTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.themeSeedColorCustomBody),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixText: '#',
                    hintText: '1565C0',
                    border: const OutlineInputBorder(),
                    errorText: error,
                  ),
                  maxLength: 8,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: Text(l10n.dialogCancel),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = _parseHexColor(ctrl.text);
                  if (parsed == null) {
                    setState(() => error = l10n.themeSeedColorCustomInvalid);
                    return;
                  }
                  Navigator.pop(ctx, parsed);
                },
                child: Text(l10n.dialogConfirm),
              ),
            ],
          ),
        );
      },
    );
    ctrl.dispose();
    if (argb != null && mounted) {
      await ref
          .read(appSettingsProvider.notifier)
          .mutate((s) => s.copyWith(seedColorArgb: argb));
    }
  }

  /// `#RRGGBB` / `RRGGBB` / `#AARRGGBB` / `AARRGGBB` → 32 位 ARGB int。
  /// 缺 alpha 默认补 `FF`（不透明）。非法输入返回 null。
  static int? _parseHexColor(String raw) {
    var s = raw.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return null;
    return int.tryParse(s, radix: 16);
  }

  Future<void> _pickDir(AppLocalizations l10n) async {
    try {
      final path = await getDirectoryPath(
        confirmButtonText: l10n.downloadDirectoryPick,
      );
      if (path != null && mounted) {
        await _applyDownloadDir(path);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.folderPickerUnavailable)));
      }
    }
  }

  /// 切换 / 清空默认下载目录：先持久化设置，再尝试用 RPC `changeGlobalOption`
  /// 把 `dir` 推给正在跑的 daemon（失败安静吞掉——下次启动还会从 settings
  /// 重新读）。
  Future<void> _applyDownloadDir(String? path) async {
    final normalized = path?.trim().isNotEmpty == true ? path : null;
    await ref
        .read(appSettingsProvider.notifier)
        .mutate(
          (s) => s.copyWith(
            downloadDirectoryOverride: normalized,
            clearDownloadDirectoryOverride: normalized == null,
          ),
        );
    if (normalized == null) return;
    final d = ref.read(aria2DaemonProvider).valueOrNull;
    if (d == null) return;
    try {
      await d.client.changeGlobalOption({'dir': normalized});
    } catch (_) {
      // 下次启动仍会从 aria2.conf 读取
    }
  }

  Future<void> _testRemoteConnection(AppLocalizations l10n) async {
    setState(() => _testingRemote = true);
    // 测连前把端点 + secret 先 commit 到 settings，让 probeRemoteRpc 拿到的
    // 输入和用户在输入框里看到的一致。
    await _commitTextFields();
    final result = await probeRemoteRpc(
      endpointRaw: _remoteEndpointCtrl.text.trim(),
      secret: _remoteSecretCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _testingRemote = false);
    final message = result.ok
        ? l10n.remoteTestOk(
            result.version ?? '?',
            result.wsReachable == true
                ? l10n.taskDetailBoolYes
                : l10n.taskDetailBoolNo,
          )
        : l10n.remoteTestFailed(
            formatRpcError(l10n, Exception(result.error ?? '')),
          );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyDeepLinkExample(AppLocalizations l10n) async {
    const example = 'https://example.com/file.zip';
    await Clipboard.setData(ClipboardData(text: buildInAppAddPath(example)));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.copyDeepLinkExampleDone)));
    }
  }

  Future<void> _copyExtensionRpcConfig(AppLocalizations l10n) async {
    // ADR-010 之后这里只对「远程 RPC」模式有意义——把用户当前填的 endpoint
    // 与 secret 直接打包成扩展可读的 JSON。本机 LibraryDaemon 不暴露 HTTP
    // 端口，浏览器扩展无法连接。
    final endpoint = _remoteEndpointCtrl.text.trim();
    final secret = _remoteSecretCtrl.text.trim();
    if (endpoint.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.copyRpcConfigUnavailable)));
      return;
    }
    final rpcUri = endpoint.contains('://')
        ? endpoint
        : 'http://$endpoint/jsonrpc';
    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert({'rpcUrl': rpcUri, 'secret': secret});
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.copyRpcConfigDone)));
    }
  }

  Future<void> _openAria2Log(AppLocalizations l10n) async {
    try {
      // LibraryDaemon 启动时把日志写到 stateRoot/state/aria2.log 并通过
      // `Aria2Daemon.logFilePath` 暴露。
      final daemon = ref.read(aria2DaemonProvider).value;
      final path = daemon?.logFilePath;
      if (path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.copyRpcConfigUnavailable)),
          );
        }
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => Aria2LogPage(logPath: path)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatRpcError(l10n, e))));
      }
    }
  }

  Future<void> _confirmShutdownAria2(AppLocalizations l10n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.shutdownAria2Title),
        content: Text(l10n.shutdownAria2Message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.shutdownAria2Confirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final d = ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    try {
      await d.client.shutdown(force: false);
      ref.invalidate(aria2DaemonProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.shutdownAria2Done)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatRpcError(l10n, e))));
      }
    }
  }

  Future<void> _confirmResetSettings(AppLocalizations l10n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.resetSettingsTitle),
        content: Text(l10n.resetSettingsMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.resetSettingsConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(appSettingsProvider.notifier).resetToDefaults();
    ref.invalidate(aria2DaemonProvider);
    // 重置后同步文本控制器到默认值——`_syncControllersFrom` 在 build 里也会
    // 被调一次，这里提前一次让用户即刻看到清空效果。
    _syncControllersFrom(const AppSettings());
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.resetSettingsDone)));
    }
  }

  Future<void> _applyRuntimeLimits(AppLocalizations l10n) async {
    final d = ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    final opts = <String, String>{};
    final dl = _dlLimitCtrl.text.trim();
    final ul = _ulLimitCtrl.text.trim();
    if (dl.isNotEmpty) opts['max-overall-download-limit'] = dl;
    if (ul.isNotEmpty) opts['max-overall-upload-limit'] = ul;
    final mc = int.tryParse(_maxConcurrentCtrl.text.trim());
    if (mc != null && mc > 0) {
      opts['max-concurrent-downloads'] = '$mc';
    }
    final conn = int.tryParse(_maxConnCtrl.text.trim());
    if (conn != null && conn > 0) {
      opts['max-connection-per-server'] = '$conn';
    }
    if (opts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.applyRuntimeLimitsEmpty)));
      }
      return;
    }
    try {
      // 先把输入框里的值提交到 settings（下次重启 daemon 也能保留），再
      // 通过 RPC 推给正在跑的 aria2。
      await _commitTextFields();
      await d.client.changeGlobalOption(opts);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.applyRuntimeLimitsDone)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatRpcError(l10n, e))));
      }
    }
  }

  Future<void> _exportSettings(AppLocalizations l10n) async {
    final current =
        ref.read(appSettingsProvider).valueOrNull ?? const AppSettings();
    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert(SettingsExport.toJson(current));
    if (_isDesktop) {
      try {
        final name =
            'aria2down-settings-${DateTime.now().toIso8601String().split('T').first}.json';
        final path = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'JSON', extensions: ['json']),
          ],
        );
        if (path != null) {
          final file = File(path.path);
          await file.writeAsString(json);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.settingsExportSaved(path.path))),
            );
          }
          return;
        }
      } catch (_) {}
    }
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.settingsExportCopied)));
    }
  }

  Future<void> _importSettings(AppLocalizations l10n) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      final path = result.files.single.path;
      final text = bytes != null
          ? utf8.decode(bytes)
          : (path != null ? await File(path).readAsString() : null);
      if (text == null || text.trim().isEmpty) return;

      final map = jsonDecode(text) as Map<String, dynamic>;
      final imported = SettingsExport.fromJson(map);
      if (!mounted) return;
      // 直接走 notifier 写入——`_syncControllersFrom` 在下一次 build 里会
      // 把文本框拉到新值（前提：用户没正在编辑某个字段）。
      await ref.read(appSettingsProvider.notifier).set(imported);
      _syncControllersFrom(imported);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.settingsImportApplied)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.settingsImportFailed(formatRpcError(l10n, e))),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = Theme.of(context);

    final mobile = isMobilePlatform;
    final settings =
        ref.watch(appSettingsProvider).valueOrNull ?? const AppSettings();

    // 文本控制器与设置同步：用户没在输入时把控件文本拉齐最新设置——支持
    // 「导入 / 重置 / 其它页面修改了某个文本字段」的场景。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncControllersFrom(settings);
    });

    final connectionMode = kIsWeb
        ? ConnectionMode.remote
        : settings.connectionMode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, mobile ? 24 : 16),
        children: [
          if (mobile)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.smartphone_outlined,
                      color: t.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.mobileSettingsCardTitle,
                            style: t.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.mobileSettingsCardBody,
                            style: t.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (mobile) const SizedBox(height: 16),
          Text(l10n.settingsConnection, style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (kIsWeb)
            Text(l10n.settingsWebRemoteOnly, style: t.textTheme.bodySmall)
          else
            SegmentedButton<ConnectionMode>(
              segments: [
                ButtonSegment(
                  value: ConnectionMode.local,
                  label: Text(l10n.connectionLocal),
                ),
                ButtonSegment(
                  value: ConnectionMode.remote,
                  label: Text(l10n.connectionRemote),
                ),
              ],
              selected: {connectionMode},
              onSelectionChanged: (v) async {
                // 切模式之前先把文本框的当前值提交，不然用户在 remote 输入了
                // 但没失焦就切到 local，端点 / secret 会丢。
                await _commitTextFields();
                await ref
                    .read(appSettingsProvider.notifier)
                    .mutate((s) => s.copyWith(connectionMode: v.first));
              },
            ),
          const _ConnectionStatusCard(),
          const _LibraryCapabilitiesWarning(),
          // ADR-010：本机模式只剩 LibraryDaemon（FFI 内嵌 libaria2）一条路。
          // 之前在这里展示的「引擎二选一 SegmentedButton + aria2c 二进制路径
          // 输入框 + fallback switch」全部一并移除——子进程引擎与其 binary
          // staging 维护成本已经远高于收益。需要外部 aria2c 的用户改用
          // 「远程 RPC」连接模式。
          if (connectionMode == ConnectionMode.local && !kIsWeb) ...[
            const SizedBox(height: 16),
            Text(l10n.settingsEngine, style: t.textTheme.titleSmall),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.memory_outlined),
              title: Text(l10n.engineLibrary),
              subtitle: Text(l10n.engineLibraryDesc),
            ),
          ],
          if (connectionMode == ConnectionMode.remote) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _remoteEndpointCtrl,
              focusNode: _remoteEndpointFocus,
              onSubmitted: (_) => _commitTextFields(),
              decoration: InputDecoration(
                labelText: l10n.remoteRpcEndpoint,
                hintText: l10n.remoteRpcEndpointHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final preset
                    in mobile
                        ? const ['127.0.0.1:6800', '192.168.1.1:6800']
                        : const [
                            '127.0.0.1:6800',
                            'localhost:6800',
                            '0.0.0.0:6800',
                          ])
                  ActionChip(
                    label: Text(preset),
                    onPressed: () async {
                      _remoteEndpointCtrl.text = preset;
                      await _commitTextFields();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _remoteSecretCtrl,
              focusNode: _remoteSecretFocus,
              obscureText: true,
              onSubmitted: (_) => _commitTextFields(),
              decoration: InputDecoration(
                labelText: l10n.remoteRpcSecret,
                border: const OutlineInputBorder(),
              ),
            ),
            Text(l10n.remoteModeHint, style: t.textTheme.bodySmall),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _testingRemote
                  ? null
                  : () => _testRemoteConnection(l10n),
              icon: _testingRemote
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering),
              label: Text(l10n.remoteTestConnection),
            ),
          ],
          const SizedBox(height: 24),
          Text(l10n.appearance, style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(l10n.theme, style: t.textTheme.bodyMedium),
          const SizedBox(height: 8),
          SegmentedButton<AppThemePreference>(
            segments: [
              ButtonSegment(
                value: AppThemePreference.system,
                label: Text(l10n.themeSystem),
              ),
              ButtonSegment(
                value: AppThemePreference.light,
                label: Text(l10n.themeLight),
              ),
              ButtonSegment(
                value: AppThemePreference.dark,
                label: Text(l10n.themeDark),
              ),
            ],
            selected: {settings.theme},
            onSelectionChanged: (v) async {
              await ref
                  .read(appSettingsProvider.notifier)
                  .mutate((s) => s.copyWith(theme: v.first));
            },
          ),
          const SizedBox(height: 20),
          // 主题色选择：默认 + 8 个预设色 + 自定义十六进制按钮。Material 3
          // 的 ColorScheme.fromSeed 会自动从种子推导 light/dark 全色板，
          // 所以这里只需要一个 ARGB 整数。
          Text(l10n.themeSeedColor, style: t.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            l10n.themeSeedColorBody,
            style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _SeedColorPicker(
            selectedArgb: settings.seedColorArgb,
            onSelected: (argb) async {
              await ref
                  .read(appSettingsProvider.notifier)
                  .mutate(
                    (s) => s.copyWith(
                      seedColorArgb: argb,
                      clearSeedColor: argb == null,
                    ),
                  );
            },
            onPickCustom: _pickCustomSeedColor,
            l10n: l10n,
          ),
          const SizedBox(height: 24),
          Text(l10n.language, style: t.textTheme.bodyMedium),
          const SizedBox(height: 8),
          // 13 个语言 SegmentedButton 装不下，改 Dropdown：保留「跟随系统」
          // 顶部分组 + 其他语言按本地命名（English / 简体中文 / 日本語…）
          // 排列，让用户能在不切到目标语言之前就识别选项。
          DropdownButtonFormField<AppLocalePreference>(
            value: settings.locale,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(
                value: AppLocalePreference.system,
                child: Text(l10n.langSystem),
              ),
              DropdownMenuItem(
                value: AppLocalePreference.en,
                child: Text(l10n.langEnglish),
              ),
              DropdownMenuItem(
                value: AppLocalePreference.zh,
                child: Text(l10n.langChineseSimplified),
              ),
              DropdownMenuItem(
                value: AppLocalePreference.zhTw,
                child: Text(l10n.langChineseTraditional),
              ),
              DropdownMenuItem(
                value: AppLocalePreference.ja,
                child: Text(l10n.langJapanese),
              ),
              DropdownMenuItem(
                value: AppLocalePreference.ko,
                child: Text(l10n.langKorean),
              ),
              DropdownMenuItem(
                value: AppLocalePreference.es,
                child: Text(l10n.langSpanish),
              ),
              DropdownMenuItem(
                value: AppLocalePreference.fr,
                child: Text(l10n.langFrench),
              ),
              DropdownMenuItem(
                value: AppLocalePreference.de,
                child: Text(l10n.langGerman),
              ),
              DropdownMenuItem(
                value: AppLocalePreference.ru,
                child: Text(l10n.langRussian),
              ),
              DropdownMenuItem(
                value: AppLocalePreference.pt,
                child: Text(l10n.langPortuguese),
              ),
              DropdownMenuItem(
                value: AppLocalePreference.ar,
                child: Text(l10n.langArabic),
              ),
              DropdownMenuItem(
                value: AppLocalePreference.vi,
                child: Text(l10n.langVietnamese),
              ),
            ],
            onChanged: (v) async {
              if (v == null) return;
              await ref
                  .read(appSettingsProvider.notifier)
                  .mutate((s) => s.copyWith(locale: v));
            },
          ),
          const SizedBox(height: 24),
          Text(l10n.settingsDownloadTuning, style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _maxConcurrentCtrl,
            focusNode: _maxConcurrentFocus,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _commitTextFields(),
            decoration: InputDecoration(
              labelText: l10n.maxConcurrentDownloads,
              hintText: l10n.settingsOptionalHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _maxConnCtrl,
            focusNode: _maxConnFocus,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _commitTextFields(),
            decoration: InputDecoration(
              labelText: l10n.maxConnectionPerServer,
              hintText: '16',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _dlLimitCtrl,
            focusNode: _dlLimitFocus,
            onSubmitted: (_) => _commitTextFields(),
            decoration: InputDecoration(
              labelText: l10n.globalDownloadLimit,
              hintText: l10n.speedLimitHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ulLimitCtrl,
            focusNode: _ulLimitFocus,
            onSubmitted: (_) => _commitTextFields(),
            decoration: InputDecoration(
              labelText: l10n.globalUploadLimit,
              hintText: l10n.speedLimitHint,
              border: const OutlineInputBorder(),
            ),
          ),
          if (connectionMode == ConnectionMode.local)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.settingsTuningLocalOnly,
                style: t.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _applyRuntimeLimits(l10n),
            icon: const Icon(Icons.speed_outlined),
            label: Text(l10n.applyRuntimeLimits),
          ),
          Text(l10n.applyRuntimeLimitsHint, style: t.textTheme.bodySmall),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: Text(l10n.downloadDirectory),
            subtitle: Text(
              settings.downloadDirectoryOverride ??
                  '(${l10n.downloadDirectoryClear})',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => _pickDir(l10n),
                  child: Text(l10n.downloadDirectoryPick),
                ),
                TextButton(
                  onPressed: () => _applyDownloadDir(null),
                  child: Text(l10n.downloadDirectoryClear),
                ),
              ],
            ),
          ),
          // 「每次询问下载目录」switch：开启后用户每次发起下载（URL / 粘贴 /
          // .torrent / .metalink / 分享 intent）在没有手填本次下载目录时
          // 都会弹原生（桌面）/ 自定义沙箱内（移动）目录选择器。各平台
          // 的权限路径与限制详见 [pickDownloadDirectory] 的文档注释。
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.help_outline),
            title: Text(l10n.askDownloadDirEachTimeTitle),
            subtitle: Text(l10n.askDownloadDirEachTimeBody),
            value: settings.askDownloadDirEachTime,
            onChanged: (v) async {
              await ref
                  .read(appSettingsProvider.notifier)
                  .mutate((s) => s.copyWith(askDownloadDirEachTime: v));
            },
          ),
          if (_isDesktop) ...[
            const SizedBox(height: 24),
            Text(l10n.settingsDesktop, style: t.textTheme.titleSmall),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.closeToTray),
              subtitle: Text(l10n.closeToTrayDesc),
              value: settings.closeToTray,
              onChanged: (v) async {
                await ref
                    .read(appSettingsProvider.notifier)
                    .mutate((s) => s.copyWith(closeToTray: v));
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.minimizeToTray),
              subtitle: Text(l10n.minimizeToTrayDesc),
              value: settings.minimizeToTray,
              onChanged: (v) async {
                await ref
                    .read(appSettingsProvider.notifier)
                    .mutate((s) => s.copyWith(minimizeToTray: v));
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.launchAtStartup),
              subtitle: Text(l10n.launchAtStartupDesc),
              value: settings.launchAtStartup,
              onChanged: (v) async {
                await ref
                    .read(appSettingsProvider.notifier)
                    .mutate((s) => s.copyWith(launchAtStartup: v));
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.startMinimized),
              subtitle: Text(l10n.startMinimizedDesc),
              value: settings.startMinimized,
              onChanged: (v) async {
                await ref
                    .read(appSettingsProvider.notifier)
                    .mutate((s) => s.copyWith(startMinimized: v));
              },
            ),
          ],
          if (mobile) ...[
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.keepAliveInBackground),
              subtitle: Text(l10n.keepAliveInBackgroundDesc),
              value: settings.keepAliveInBackground,
              onChanged: (v) async {
                await ref
                    .read(appSettingsProvider.notifier)
                    .mutate((s) => s.copyWith(keepAliveInBackground: v));
              },
            ),
          ],
          const SizedBox(height: 24),
          Text(l10n.settingsBackup, style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _exportSettings(l10n),
                icon: const Icon(Icons.upload_outlined),
                label: Text(l10n.settingsExport),
              ),
              OutlinedButton.icon(
                onPressed: () => _importSettings(l10n),
                icon: const Icon(Icons.download_outlined),
                label: Text(l10n.settingsImport),
              ),
            ],
          ),
          if (connectionMode == ConnectionMode.local && !kIsWeb) ...[
            const SizedBox(height: 24),
            Text(l10n.settingsDiagnostics, style: t.textTheme.titleSmall),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.article_outlined),
              title: Text(l10n.aria2LogTitle),
              subtitle: Text(l10n.aria2LogSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openAria2Log(l10n),
            ),
            // 「复制 RPC 配置给浏览器扩展」之前只对 subprocess 引擎有意义
            // （需要把本地 HTTP 端口 + secret 给扩展）。ADR-010 后本机只剩
            // LibraryDaemon（FFI，无 HTTP 端口），所以这条仅在「远程 RPC」
            // 模式下才有意义——把用户已经配好的远程 endpoint+secret 直接
            // 整理成扩展可用的 JSON 形态。
            if (connectionMode == ConnectionMode.remote)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.extension_outlined),
                title: Text(l10n.copyRpcConfigTitle),
                subtitle: Text(l10n.copyRpcConfigSubtitle),
                onTap: () => _copyExtensionRpcConfig(l10n),
              ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tune),
            title: Text(l10n.aria2GlobalOptionsTitle),
            subtitle: Text(l10n.aria2GlobalOptionsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Aria2GlobalOptionsPage(),
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.link_outlined),
            title: Text(l10n.copyDeepLinkExampleTitle),
            subtitle: Text(l10n.copyDeepLinkExampleSubtitle),
            onTap: () => _copyDeepLinkExample(l10n),
          ),
          const SizedBox(height: 24),
          Text(l10n.settingsDangerZone, style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _confirmShutdownAria2(l10n),
            icon: const Icon(Icons.power_settings_new),
            label: Text(l10n.shutdownAria2),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _confirmResetSettings(l10n),
            child: Text(l10n.resetSettings),
          ),
          const SizedBox(height: 32),
          Text(l10n.about, style: t.textTheme.titleSmall),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.aboutTitle),
            subtitle: Text(l10n.aboutOpenDetail),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
          ),
        ],
      ),
    );
  }
}

/// 主题种子色挑选区：
/// - 第一个圆是「跟随默认」（透明背景 + 房子图标，表示用品牌默认色 `kDefaultSeedColor`）；
/// - 中间 8 个圆是手挑的预设色（暖 / 冷 / 中性各几支，覆盖大多数人偏好）；
/// - 最后一个圆是「自定义十六进制」入口，弹对话框收 `#RRGGBB` / `#AARRGGBB`。
///
/// 选中状态用 [Theme.colorScheme.primary] 的环高亮，不直接给圆加阴影避免与
/// 卡片背景的 elevation 拉扯。
class _SeedColorPicker extends StatelessWidget {
  const _SeedColorPicker({
    required this.selectedArgb,
    required this.onSelected,
    required this.onPickCustom,
    required this.l10n,
  });

  /// `null` 表示「跟随默认」（应用品牌色 [kDefaultSeedColor]）。
  final int? selectedArgb;

  /// 选定预设色（传入对应 ARGB），或回到默认（传 null）。
  final void Function(int? argb) onSelected;

  /// 用户点了「自定义...」按钮。具体的对话框逻辑在 SettingsForm 里实现，
  /// 让 picker 本身保持纯 UI。
  final Future<void> Function(AppLocalizations l10n) onPickCustom;

  final AppLocalizations l10n;

  /// 预设色板：选取饱和度适中、对深浅两种背景都能形成清晰主色调的 8 个种子色。
  /// 顺序按色相环排布（红→粉→紫→蓝→青→绿→黄绿→橙）方便用户挑。
  static const List<Color> _presets = [
    Color(0xFFC62828), // 砖红
    Color(0xFFC2185B), // 玫粉
    Color(0xFF7E57C2), // 薰衣草紫
    Color(0xFF1565C0), // 品牌默认蓝（也在预设中，便于"我换走了想换回来"）
    Color(0xFF00838F), // 青绿
    Color(0xFF2E7D32), // 森林绿
    Color(0xFF9E9D24), // 橄榄黄
    Color(0xFFEF6C00), // 暖橙
  ];

  bool _isSelected(int? presetArgb) {
    // null vs null（"跟随默认"）需要单独处理：selectedArgb 也是 null 时高亮
    // 第一个 chip。
    if (presetArgb == null) return selectedArgb == null;
    if (selectedArgb == null) return false;
    return selectedArgb == presetArgb;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _ColorDot(
          color: scheme.surfaceContainerHighest,
          icon: Icons.refresh,
          iconColor: scheme.onSurfaceVariant,
          selected: _isSelected(null),
          selectionColor: scheme.primary,
          tooltip: l10n.themeSeedColorDefault,
          onTap: () => onSelected(null),
        ),
        for (final c in _presets)
          _ColorDot(
            color: c,
            selected: _isSelected(c.toARGB32()),
            selectionColor: scheme.onSurface,
            onTap: () => onSelected(c.toARGB32()),
          ),
        _ColorDot(
          color: scheme.surfaceContainerHighest,
          icon: Icons.colorize,
          iconColor: scheme.onSurfaceVariant,
          selected:
              selectedArgb != null &&
              !_presets.any((c) => c.toARGB32() == selectedArgb),
          selectionColor: scheme.primary,
          tooltip: l10n.themeSeedColorCustomTitle,
          onTap: () => onPickCustom(l10n),
        ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.selectionColor,
    required this.onTap,
    this.icon,
    this.iconColor,
    this.tooltip,
  });

  final Color color;
  final IconData? icon;
  final Color? iconColor;
  final bool selected;
  final Color selectionColor;
  final String? tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dot = InkResponse(
      onTap: onTap,
      radius: 28,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: selectionColor, width: 2.5)
              : Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
        ),
        child: icon != null
            ? Icon(icon, size: 20, color: iconColor)
            : (selected
                  ? Icon(Icons.check, size: 20, color: selectionColor)
                  : null),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: dot);
    }
    return dot;
  }
}
