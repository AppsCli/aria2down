import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../aria2/daemon/library_daemon.dart';
import '../data/app_settings.dart';
import 'app_settings_provider.dart';
import 'aria2_daemon_provider.dart';

/// 当前 RPC 连接摘要（设置页展示）。
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
          ConnectionMode.local =>
            d is LibraryDaemon ? ActiveEngine.library : ActiveEngine.subprocess,
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

enum ActiveEngine { library, subprocess, remote }

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
