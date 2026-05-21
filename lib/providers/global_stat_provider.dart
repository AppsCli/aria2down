import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../aria2/client/aria2_client.dart' show GlobalStat;
import 'aria2_daemon_provider.dart';
import 'app_background_provider.dart';

/// 实时全局速率/任务数。独立于任务列表页的轮询：始终在 daemon 就绪
/// 时按节流频率拉取 `aria2.getGlobalStat`，用于驱动桌面托盘 tooltip
/// 与 Android 前台服务通知，不要求任何 UI 页面可见。
///
/// 在移动平台、应用进入后台后，自动把轮询间隔放宽到 5s，避免在
/// `paused` / `inactive` 状态下唤醒过多。桌面与前台保持 1s。
final globalStatStreamProvider = StreamProvider<GlobalStat>((ref) async* {
  final daemonAsync = ref.watch(aria2DaemonProvider);
  final daemon = daemonAsync.value;
  if (daemon == null) return;

  Duration interval() {
    final inBackground = ref.read(appInBackgroundProvider);
    return inBackground
        ? const Duration(seconds: 5)
        : const Duration(seconds: 1);
  }

  // 后台状态切换时立刻打破当前 delay，立即拉取一次。
  final wake = StreamController<void>.broadcast();
  final sub = ref.listen<bool>(appInBackgroundProvider, (_, __) {
    if (!wake.isClosed) wake.add(null);
  });
  ref.onDispose(() {
    sub.close();
    unawaited(wake.close());
  });

  while (true) {
    try {
      final stat = await daemon.client.getGlobalStat();
      yield stat;
    } catch (_) {
      // 静默忽略；下一轮重试。
    }
    if (wake.isClosed) return;
    final completer = Completer<void>();
    StreamSubscription<void>? w;
    w = wake.stream.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    final timer = Timer(interval(), () {
      if (!completer.isCompleted) completer.complete();
    });
    try {
      await completer.future;
    } finally {
      await w.cancel();
      timer.cancel();
    }
  }
});
