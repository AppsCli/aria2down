import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../aria2/client/aria2_exceptions.dart';
import '../aria2/daemon/aria2_daemon.dart';
import '../aria2/daemon/library_daemon.dart';
import '../aria2/daemon/local_daemon.dart';
import '../aria2/daemon/remote_daemon.dart';
import '../data/app_settings.dart';
import 'app_settings_provider.dart';

/// 应用级 aria2 连接（内嵌库 / 本地子进程 / 远程 RPC）。
///
/// 选择优先级：
/// 1. [ConnectionMode.remote] → [RemoteDaemon]。
/// 2. [LocalEngine.library] 且当前平台支持 FFI → [LibraryDaemon]，
///    启动失败且 [AppSettings.fallbackToSubprocess] 为真时自动降级到 [LocalDaemon]。
/// 3. 否则 [LocalDaemon]（aria2c 子进程）。
/// 4. Web 无原生进程，只支持 [RemoteDaemon]；强制本机模式时抛
///    [Aria2WebLocalUnsupportedException]。
final aria2DaemonProvider = FutureProvider<Aria2Daemon>((ref) async {
  final settings = await ref.watch(appSettingsProvider.future);

  // 关键：在 daemon 创建后**立即**注册 onDispose，无论 `start()` 是否成功。
  // 此前实现把 onDispose 放在 `await _startWithRetry` 之后——如果启动失败
  // (例：LocalDaemon spawn 了 aria2c 但 RPC 未就绪超时)，已 spawn 的子进程
  // 不会被回收，进入 Provider error 状态时也不会触发任何清理。
  Aria2Daemon? created;
  ref.onDispose(() {
    final d = created;
    if (d != null) {
      unawaited(d.stop());
    }
  });

  return _createAndStart(settings, (d) => created = d);
});

Future<Aria2Daemon> _createAndStart(
  AppSettings settings,
  void Function(Aria2Daemon) onCreated,
) async {
  if (kIsWeb) {
    if (settings.connectionMode != ConnectionMode.remote) {
      throw const Aria2WebLocalUnsupportedException();
    }
    final d = RemoteDaemon.fromSettings(settings);
    onCreated(d);
    await _startWithRetry(d);
    return d;
  }
  if (settings.connectionMode == ConnectionMode.remote) {
    final d = RemoteDaemon.fromSettings(settings);
    onCreated(d);
    await _startWithRetry(d);
    return d;
  }

  if (settings.localEngine == LocalEngine.library) {
    final lib = await LibraryDaemon.create(settings: settings);
    onCreated(lib);
    try {
      await _startWithRetry(lib);
      return lib;
    } catch (e) {
      if (!settings.fallbackToSubprocess) rethrow;
      // ignore: avoid_print
      print('[aria2] LibraryDaemon 启动失败，回退到子进程: $e');
      // 库引擎失败：显式 stop 释放任何已分配的 native session，再切换到
      // 子进程 daemon。`onCreated` 会覆盖前一个引用，让 onDispose 始终
      // 指向 _最后_ 创建的 daemon。
      try {
        await lib.stop(force: true);
      } catch (_) {}
      final sub = await LocalDaemon.create(settings: settings);
      onCreated(sub);
      await _startWithRetry(sub);
      return sub;
    }
  }
  final sub = await LocalDaemon.create(settings: settings);
  onCreated(sub);
  await _startWithRetry(sub);
  return sub;
}

/// 远程或本机启动失败时短暂重试（网络抖动 / 端口占用）。
///
/// daemon 自身 `start()` 已经在失败路径里 cleanup spawn 出的子进程；这里
/// 只负责按退避策略再次调 `start()`，无需重复清理。
Future<void> _startWithRetry(Aria2Daemon daemon) async {
  const attempts = 3;
  Object? lastError;
  for (var i = 0; i < attempts; i++) {
    try {
      await daemon.start();
      return;
    } catch (e) {
      lastError = e;
      if (i < attempts - 1) {
        await Future<void>.delayed(Duration(seconds: 1 + i));
      }
    }
  }
  throw lastError ?? StateError('aria2 start failed');
}

/// 兼容旧引用。
@Deprecated('Use aria2DaemonProvider')
final localDaemonProvider = aria2DaemonProvider;
