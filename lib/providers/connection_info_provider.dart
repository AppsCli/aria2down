import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_settings.dart';
import 'app_settings_provider.dart';
import 'aria2_daemon_provider.dart';

/// 当前 RPC 连接摘要（设置页展示）。
///
/// 本机模式只剩 [LibraryDaemon] 一条路径（ADR-010 之后移除了 aria2c 子进程
/// 引擎），所以这里直接按 `ConnectionMode` 决定 [ActiveEngine]，无需再像
/// 之前那样通过 `daemon is LibraryDaemon` 区分本机两种引擎。
final connectionInfoProvider = Provider<AsyncValue<ConnectionInfo>>((ref) {
  final settings = ref.watch(appSettingsProvider);
  final daemon = ref.watch(aria2DaemonProvider);

  return settings.when(
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
    data: (s) => daemon.when(
      loading: () => const AsyncValue.loading(),
      error: (e, st) => AsyncValue.error(e, st),
      data: (d) {
        final activeEngine = switch (s.connectionMode) {
          ConnectionMode.remote => ActiveEngine.remote,
          ConnectionMode.local => ActiveEngine.library,
        };
        return AsyncValue.data(
          ConnectionInfo(
            mode: s.connectionMode,
            engine: activeEngine,
            httpEndpoint: d.rpcHttpUri.toString(),
            port: d.rpcPort,
            wsAvailable: d.wsNotifier != null,
          ),
        );
      },
    ),
  );
});

enum ActiveEngine { library, remote }

class ConnectionInfo {
  const ConnectionInfo({
    required this.mode,
    required this.engine,
    required this.httpEndpoint,
    required this.port,
    required this.wsAvailable,
  });

  final ConnectionMode mode;
  final ActiveEngine engine;
  final String httpEndpoint;
  final int port;
  final bool wsAvailable;
}
