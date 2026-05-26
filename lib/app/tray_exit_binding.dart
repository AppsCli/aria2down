import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../aria2/client/aria2_client.dart' show GlobalStat;
import '../core/format_utils.dart';
import '../core/reveal_path.dart';
import '../desktop/desktop_shell.dart';
import '../providers/app_settings_provider.dart';
import '../providers/aria2_daemon_provider.dart';
import '../providers/global_stat_provider.dart';
import 'package:aria2down/l10n/app_localizations.dart';

/// 在 [ProviderScope] 下托管桌面托盘：
/// - 注册退出前关停 daemon 的 handler
/// - 注册托盘菜单回调（显示窗口 / 新建 / 全部暂停 / 全部继续 / 打开下载目录）
/// - 监听 [globalStatStreamProvider] 把实时速率写入托盘 tooltip
class TrayExitBinding extends ConsumerStatefulWidget {
  const TrayExitBinding({super.key, required this.child, required this.router});

  final Widget child;
  final GoRouter router;

  @override
  ConsumerState<TrayExitBinding> createState() => _TrayExitBindingState();
}

class _TrayExitBindingState extends ConsumerState<TrayExitBinding> {
  bool _exitRegistered = false;
  String? _lastToolTip;
  String? _lastLabelsKey;
  ProviderSubscription<AsyncValue<GlobalStat>>? _statSub;

  bool get _enabled {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  @override
  void initState() {
    super.initState();
    if (!_enabled) return;
    _statSub = ref.listenManual<AsyncValue<GlobalStat>>(
      globalStatStreamProvider,
      (prev, next) {
        // 不要只在 data 路径更新——stat 流出错（daemon 没就绪 / 远程断网）
        // 时 tooltip 一直停在上一份成功的数值上，用户看不出已经掉线。
        next.when(
          data: _pushStatToolTip,
          error: (_, __) => _pushOfflineToolTip(),
          loading: () {
            // 仅在「曾经显示过 stat」的情况下转为脱机文案；首帧 loading
            // 时还没有任何 tooltip 可对比，让默认 trayToolTip 占位即可。
            if (_lastToolTip != null) _pushOfflineToolTip();
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _statSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_enabled) {
      _ensureExitHandlerRegistered();
      _pushLocalizedLabels(context);
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCallbacks());
    }
    return widget.child;
  }

  /// 把当前 [AppLocalizations] 文案同步到桌面托盘菜单/tooltip。
  /// 在 [build] 内调用即可：此组件位于 [MaterialApp] 之下，可访问 l10n。
  void _pushLocalizedLabels(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    final key = [
      l10n.trayShowWindow,
      l10n.trayNewTask,
      l10n.trayPauseAll,
      l10n.trayResumeAll,
      l10n.trayOpenDownloads,
      l10n.trayQuit,
      l10n.trayToolTip,
    ].join('\u0000');
    if (key == _lastLabelsKey) return;
    _lastLabelsKey = key;
    updateDesktopTrayLabels(
      DesktopTrayLabels(
        showWindow: l10n.trayShowWindow,
        newTask: l10n.trayNewTask,
        pauseAll: l10n.trayPauseAll,
        resumeAll: l10n.trayResumeAll,
        openDownloads: l10n.trayOpenDownloads,
        quit: l10n.trayQuit,
        toolTip: l10n.trayToolTip,
      ),
    );
  }

  void _ensureExitHandlerRegistered() {
    if (_exitRegistered) return;
    _exitRegistered = true;
    registerDesktopExitHandler(() async {
      try {
        final d = await ref.read(aria2DaemonProvider.future);
        await d.stop();
      } catch (_) {}
    });
  }

  void _refreshCallbacks() {
    updateDesktopTrayCallbacks(
      DesktopTrayCallbacks(
        onShowWindow: showDesktopWindow,
        onNewTask: () async {
          await showDesktopWindow();
          widget.router.go('/add');
        },
        onPauseAll: () => _safeRun((c) => c.pauseAll()),
        onResumeAll: () => _safeRun((c) => c.unpauseAll()),
        onOpenDownloads: _openDownloadsFolder,
      ),
    );
  }

  Future<void> _safeRun(Future<void> Function(dynamic client) action) async {
    try {
      final d = await ref.read(aria2DaemonProvider.future);
      await action(d.client);
    } catch (e, st) {
      // 之前是 `catch (_) {}` 完全吞错——托盘点「全部暂停」失败时用户
      // 既看不到反馈也无法排查。至少留到 debug 日志，配合 logging
      // transport 已记录的 RPC 失败行能复盘根因。
      debugPrint('[tray] action failed: $e');
      debugPrintStack(stackTrace: st, label: '[tray] action failed');
    }
  }

  Future<void> _openDownloadsFolder() async {
    try {
      final settings = ref.read(appSettingsProvider).valueOrNull;
      String? path = settings?.downloadDirectoryOverride?.trim();
      if (path == null || path.isEmpty) {
        try {
          final d = await ref.read(aria2DaemonProvider.future);
          final opts = await d.client.getGlobalOption();
          final dir = opts['dir'];
          if (dir != null && dir.isNotEmpty) path = dir;
        } catch (_) {}
      }
      if (path == null || path.isEmpty) {
        final dl = await getDownloadsDirectory();
        path = dl?.path;
      }
      if (path == null || path.isEmpty) return;
      final dir = Directory(path);
      if (!await dir.exists()) return;
      await revealPathInFileManager(path);
    } catch (_) {}
  }

  void _pushStatToolTip(GlobalStat stat) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    final text = l10n.trayToolTipStats(
      formatSpeed(stat.downloadSpeed),
      formatSpeed(stat.uploadSpeed),
      stat.numActive,
      stat.numWaiting,
    );
    if (text == _lastToolTip) return;
    _lastToolTip = text;
    updateDesktopTrayToolTip(text);
  }

  void _pushOfflineToolTip() {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    final text = l10n.trayToolTipOffline;
    if (text == _lastToolTip) return;
    _lastToolTip = text;
    updateDesktopTrayToolTip(text);
  }
}
