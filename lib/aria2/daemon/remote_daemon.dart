import '../../core/remote_endpoint.dart';
import '../../data/app_settings.dart';
import '../client/aria2_client.dart';
import '../client/aria2_exceptions.dart';
import '../client/http_transport.dart';
import '../client/ws_listener.dart';
import 'aria2_daemon.dart';
import 'daemon_state.dart';

/// 连接外部已运行的 aria2 RPC（不启动子进程）。
final class RemoteDaemon implements Aria2Daemon {
  RemoteDaemon({required this.endpoint, required this.rpcSecret});

  final RemoteRpcEndpoint endpoint;
  @override
  final String rpcSecret;

  Aria2Client? _client;
  Aria2HttpTransport? _transport;
  WsAria2Notifier? _ws;
  DaemonState _state = DaemonState.stopped;

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
    _client = Aria2Client(transport: _transport!);

    try {
      await _client!.getVersion();
    } catch (e) {
      _state = DaemonState.failed;
      await stop();
      throw Aria2DaemonException('无法连接远程 aria2：$e');
    }

    _ws = WsAria2Notifier(endpoint: rpcWebSocketUri, secret: rpcSecret);
    try {
      await _ws!.connect();
      await _ws!.ping();
    } catch (_) {
      await _ws?.dispose();
      _ws = null;
    }

    _state = DaemonState.ready;
  }

  @override
  Future<void> stop({bool force = false}) async {
    if (_state == DaemonState.stopped) return;
    _state = DaemonState.stopping;

    await _ws?.dispose();
    _ws = null;
    _client = null;
    _transport = null;

    _state = DaemonState.stopped;
  }
}
