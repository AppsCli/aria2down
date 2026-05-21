import 'dart:async';

import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../aria2/client/aria2_client.dart' show GlobalStat;
import '../core/android_keep_alive.dart';
import '../core/platform_hints.dart';
import '../providers/app_settings_provider.dart';
import '../providers/aria2_daemon_provider.dart';
import '../providers/global_stat_provider.dart';

/// 移动端后台运维：
/// - Android：把全局速率/任务数推送给前台服务通知；监听通知按钮触发的
///   控制信号并执行 `pauseAll` / `unpauseAll` / 路由到任务列表。
/// - iOS：仅监听 lifecycle，必要时申请 background task（已在 AppDelegate
///   完成；本绑定保持空操作但保留 keepAliveInBackground 开关读取）。
class MobileBackgroundBinding extends ConsumerStatefulWidget {
  const MobileBackgroundBinding({
    super.key,
    required this.child,
    required this.router,
  });

  final Widget child;
  final GoRouter router;

  @override
  ConsumerState<MobileBackgroundBinding> createState() =>
      _MobileBackgroundBindingState();
}

class _MobileBackgroundBindingState
    extends ConsumerState<MobileBackgroundBinding> {
  StreamSubscription<String>? _controlSub;
  ProviderSubscription<AsyncValue<GlobalStat>>? _statSub;
  GlobalStat? _lastStat;
  bool _serviceRunning = false;
  bool _keepAlive = true;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (!isMobilePlatform) return;
    if (_isAndroid) {
      _controlSub = AndroidKeepAlive.controlEvents.listen(_handleControl);
    }
    _statSub = ref.listenManual<AsyncValue<GlobalStat>>(
      globalStatStreamProvider,
      (prev, next) {
        next.whenData((stat) {
          _lastStat = stat;
          _pushUpdate();
        });
      },
    );
  }

  @override
  void dispose() {
    unawaited(_controlSub?.cancel());
    _statSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isMobilePlatform) {
      final settings = ref.watch(appSettingsProvider).valueOrNull;
      final daemonReady =
          ref.watch(aria2DaemonProvider).valueOrNull != null &&
          settings != null &&
          !settings.isRemote;
      final keepAlive = settings?.keepAliveInBackground ?? true;
      _keepAlive = keepAlive;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncService(running: daemonReady && keepAlive);
      });
    }
    return widget.child;
  }

  Future<void> _syncService({required bool running}) async {
    if (!_isAndroid) return;
    if (running == _serviceRunning) {
      if (running) _pushUpdate();
      return;
    }
    _serviceRunning = running;
    final l10n = AppLocalizations.of(context);
    final labels = l10n == null
        ? null
        : KeepAliveLabels(
            title: l10n.keepAliveTitle,
            show: l10n.trayShowWindow,
            pause: l10n.batchPauseAll,
            resume: l10n.batchUnpauseAll,
            quit: l10n.trayQuit,
          );
    if (running) {
      final stat = _lastStat;
      await AndroidKeepAlive.start(
        downSpeed: stat?.downloadSpeed ?? 0,
        upSpeed: stat?.uploadSpeed ?? 0,
        active: stat?.numActive ?? 0,
        waiting: stat?.numWaiting ?? 0,
        labels: labels,
      );
    } else {
      await AndroidKeepAlive.stop();
    }
  }

  void _pushUpdate() {
    if (!_isAndroid || !_serviceRunning || !_keepAlive) return;
    final stat = _lastStat;
    if (stat == null) return;
    final l10n = AppLocalizations.of(context);
    final labels = l10n == null
        ? null
        : KeepAliveLabels(
            title: l10n.keepAliveTitle,
            show: l10n.trayShowWindow,
            pause: l10n.batchPauseAll,
            resume: l10n.batchUnpauseAll,
            quit: l10n.trayQuit,
          );
    unawaited(
      AndroidKeepAlive.update(
        downSpeed: stat.downloadSpeed,
        upSpeed: stat.uploadSpeed,
        active: stat.numActive,
        waiting: stat.numWaiting,
        labels: labels,
      ),
    );
  }

  Future<void> _handleControl(String action) async {
    switch (action) {
      case 'pause_all':
        await _runOnClient((c) => c.pauseAll());
        _showSnack(_localizedPauseAllDone());
      case 'resume_all':
        await _runOnClient((c) => c.unpauseAll());
        _showSnack(_localizedResumeAllDone());
      case 'show_window':
        widget.router.go('/tasks');
    }
  }

  Future<void> _runOnClient(
    Future<void> Function(dynamic client) action,
  ) async {
    try {
      final d = await ref.read(aria2DaemonProvider.future);
      await action(d.client);
    } catch (_) {}
  }

  void _showSnack(String? msg) {
    if (msg == null) return;
    final ctx = context;
    if (!ctx.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    messenger?.showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _localizedPauseAllDone() =>
      AppLocalizations.of(context)?.notifPauseAllDone;
  String? _localizedResumeAllDone() =>
      AppLocalizations.of(context)?.notifResumeAllDone;
}
