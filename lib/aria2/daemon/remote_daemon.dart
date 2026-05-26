import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/remote_endpoint.dart';
import '../../data/app_settings.dart';
import '../client/aria2_client.dart';
import '../client/aria2_exceptions.dart';
import '../client/http_transport.dart';
import '../client/logging_transport.dart';
import '../client/ws_listener.dart';
import 'aria2_daemon.dart';
import 'daemon_state.dart';

/// 连接外部已运行的 aria2 RPC（不启动子进程）。
///
/// 实现细节：
/// - 启动时只做一次 `getVersion()` 验证；后续 RPC 失败由调用方处理。
/// - 运行期间维护一个 30s 的健康检查 timer：每次 tick 调一次 `getVersion()`，
///   连续成功且 `_ws == null` 时尝试 (重) 连 WebSocket；连续失败则 dispose
///   旧 WS，下个周期再尝试。这样远程 aria2 重启/网络瞬断后无需用户介入
///   即可恢复事件推送。
final class RemoteDaemon implements Aria2Daemon {
  RemoteDaemon({required this.endpoint, required this.rpcSecret});

  final RemoteRpcEndpoint endpoint;
  @override
  final String rpcSecret;

  Aria2Client? _client;
  Aria2HttpTransport? _transport;
  WsAria2Notifier? _ws;
  DaemonState _state = DaemonState.stopped;
  Timer? _healthTimer;
  bool _healthInFlight = false;
  final ValueNotifier<int> _connectionGeneration = ValueNotifier<int>(0);

  static const _healthInterval = Duration(seconds: 30);
  static const _healthTimeout = Duration(seconds: 5);

  @override
  int get rpcPort => endpoint.port;

  @override
  Uri get rpcHttpUri => endpoint.httpJsonRpcUri('/jsonrpc');

  @override
  Uri get rpcWebSocketUri => endpoint.webSocketJsonRpcUri('/jsonrpc');

  @override
  String? get logFilePath => null;

  @override
  Aria2Client get client {
    final c = _client;
    if (c == null) {
      throw const Aria2DaemonException('尚未连接到远程 aria2');
    }
    return c;
  }

  @override
  WsAria2Notifier? get wsNotifier => _ws;

  @override
  ValueListenable<int> get connectionGeneration => _connectionGeneration;

  static RemoteDaemon fromSettings(AppSettings settings) {
    final raw = settings.remoteRpcEndpoint?.trim();
    if (raw == null || raw.isEmpty) {
      throw const Aria2DaemonException('请填写远程 RPC 地址（host:port）');
    }
    final endpoint = parseRemoteRpcEndpoint(raw);
    final secret = settings.remoteRpcSecret?.trim() ?? '';
    return RemoteDaemon(endpoint: endpoint, rpcSecret: secret);
  }

  @override
  Future<void> start() async {
    if (_state == DaemonState.ready) return;
    _state = DaemonState.starting;

    _transport = Aria2HttpTransport(endpoint: rpcHttpUri, secret: rpcSecret);
    _client = Aria2Client(
      transport: Aria2LoggingTransport(_transport!, label: 'remote'),
    );

    try {
      await _client!.getVersion();
    } catch (e) {
      _state = DaemonState.failed;
      await stop();
      throw Aria2DaemonException('无法连接远程 aria2：$e');
    }

    await _connectWebSocket();
    _state = DaemonState.ready;
    _startHealthMonitor();
  }

  Future<void> _connectWebSocket() async {
    final ws = WsAria2Notifier(endpoint: rpcWebSocketUri, secret: rpcSecret);
    try {
      await ws.connect();
      await ws.ping();
      _ws = ws;
    } catch (_) {
      await ws.dispose();
      _ws = null;
    }
  }

  void _startHealthMonitor() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(_healthInterval, (_) {
      if (_state != DaemonState.ready) return;
      if (_healthInFlight) return;
      unawaited(_runHealthCheck());
    });
  }

  Future<void> _runHealthCheck() async {
    _healthInFlight = true;
    try {
      final c = _client;
      if (c == null) return;
      bool ok;
      try {
        await c.getVersion().timeout(_healthTimeout);
        ok = true;
      } catch (_) {
        ok = false;
      }
      if (!ok) {
        // HTTP 也连不上时把 WS 释放，等下一轮再试，避免半死状态。
        if (_ws != null) {
          await _ws!.dispose();
          _ws = null;
          _connectionGeneration.value = _connectionGeneration.value + 1;
        }
        return;
      }
      if (_ws == null) {
        // HTTP 通了但 WS 缺失：尝试重连。成功后 bump generation 让 UI 重绑。
        await _connectWebSocket();
        if (_ws != null) {
          _connectionGeneration.value = _connectionGeneration.value + 1;
        }
      }
    } finally {
      _healthInFlight = false;
    }
  }

  @override
  Future<void> stop({bool force = false}) async {
    if (_state == DaemonState.stopped) return;
    _state = DaemonState.stopping;

    _healthTimer?.cancel();
    _healthTimer = null;

    await _ws?.dispose();
    _ws = null;
    _client = null;
    _transport = null;

    _state = DaemonState.stopped;
  }
}
