import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../aria2/client/aria2_exceptions.dart';
import '../aria2/daemon/aria2_daemon.dart';
import '../aria2/daemon/library_daemon.dart';
import '../aria2/daemon/remote_daemon.dart';
import '../data/app_settings.dart';
import 'app_settings_provider.dart';

/// 应用级 aria2 连接，两条路径：
///
/// 1. [ConnectionMode.remote] → [RemoteDaemon]（连接外部 aria2c HTTP/WS RPC）。
/// 2. [ConnectionMode.local]  → [LibraryDaemon]（FFI 内嵌 libaria2）。
///
/// ADR-010 之前还有一条 `LocalDaemon`（启动 `aria2c` 子进程）兜底分支。现在
/// 已经彻底移除：prebuilt libaria2 在每个发布目标上都强制可用，FFI 引擎是
/// 唯一的本机路径；其它需要外部 aria2c 的场景请用远程 RPC。
///
/// Web 没有原生进程，强制本机模式时抛 [Aria2WebLocalUnsupportedException]——
/// 配置层 ([appSettingsProvider]) 在首次启动时会把 Web 默认连接模式设为
/// remote，正常情况下走不到这条异常。
final aria2DaemonProvider = FutureProvider<Aria2Daemon>((ref) async {
  final settings = await ref.watch(appSettingsProvider.future);

  // 关键：在 daemon 创建后**立即**注册 onDispose，无论 `start()` 是否成功。
  // 启动失败时仍要 stop() 释放任何已分配的资源（FFI session、WS 连接等）。
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
  if (settings.connectionMode == ConnectionMode.remote) {
    final d = RemoteDaemon.fromSettings(settings);
    onCreated(d);
    await _startWithRetry(d);
    return d;
  }
  // 本机模式：唯一选项是内嵌 libaria2。Web 平台无法加载 FFI 库——
  // `LibraryDaemon.create` 内部已经会校验 prebuilt 是否真实可用，缺失时
  // 直接抛 `Aria2NativeUnavailableException`；这里不再做隐式 fallback。
  final lib = await LibraryDaemon.create(settings: settings);
  onCreated(lib);
  await _startWithRetry(lib);
  return lib;
}

/// 远程或本机启动失败时短暂重试（网络抖动 / 端口占用）。
///
/// daemon 自身 `start()` 已经在失败路径里做完资源回收；这里只负责按退避
/// 策略再次调 `start()`。
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
