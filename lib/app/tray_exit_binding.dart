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
        next.whenData(_pushToolTip);
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCallbacks());
    }
    return widget.child;
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
    } catch (_) {}
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

  void _pushToolTip(GlobalStat stat) {
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
}
