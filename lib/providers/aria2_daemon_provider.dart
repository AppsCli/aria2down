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

  final daemon = await _createAndStart(settings);

  ref.onDispose(() {
    unawaited(daemon.stop());
  });
  return daemon;
});

Future<Aria2Daemon> _createAndStart(AppSettings settings) async {
  if (kIsWeb) {
    if (settings.connectionMode != ConnectionMode.remote) {
      throw const Aria2WebLocalUnsupportedException();
    }
    final d = RemoteDaemon.fromSettings(settings);
    await _startWithRetry(d);
    return d;
  }
  if (settings.connectionMode == ConnectionMode.remote) {
    final d = RemoteDaemon.fromSettings(settings);
    await _startWithRetry(d);
    return d;
  }

  if (settings.localEngine == LocalEngine.library) {
    try {
      final lib = await LibraryDaemon.create(settings: settings);
      await _startWithRetry(lib);
      return lib;
    } catch (e) {
      if (!settings.fallbackToSubprocess) rethrow;
      // ignore: avoid_print
      print('[aria2] LibraryDaemon 启动失败，回退到子进程: $e');
      final sub = await LocalDaemon.create(settings: settings);
      await _startWithRetry(sub);
      return sub;
    }
  }
  final sub = await LocalDaemon.create(settings: settings);
  await _startWithRetry(sub);
  return sub;
}

/// 远程或本机启动失败时短暂重试（网络抖动 / 端口占用）。
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
