import '../aria2/client/aria2_client.dart';
import '../aria2/client/http_transport.dart';
import '../aria2/client/logging_transport.dart';
import '../aria2/client/ws_listener.dart';
import 'remote_endpoint.dart';

/// 探测远程 aria2 RPC 是否可达（不启动应用级 [RemoteDaemon]）。
class RemoteRpcProbeResult {
  const RemoteRpcProbeResult({
    required this.ok,
    this.version,
    this.error,
    this.wsReachable,
  });

  final bool ok;
  final String? version;
  final String? error;
  final bool? wsReachable;
}

Future<RemoteRpcProbeResult> probeRemoteRpc({
  required String endpointRaw,
  String secret = '',
}) async {
  try {
    final endpoint = parseRemoteRpcEndpoint(endpointRaw);
    final httpUri = endpoint.httpJsonRpcUri('/jsonrpc');
    final transport = Aria2HttpTransport(
      endpoint: httpUri,
      secret: secret.trim(),
    );
    final client = Aria2Client(
      transport: Aria2LoggingTransport(transport, label: 'probe'),
    );
    final ver = await client.getVersion();
    final version = '${ver['version'] ?? ver}';

    bool? wsOk;
    try {
      final ws = WsAria2Notifier(
        endpoint: endpoint.webSocketJsonRpcUri('/jsonrpc'),
        secret: secret.trim(),
      );
      await ws.connect();
      await ws.ping();
      wsOk = true;
      await ws.dispose();
    } catch (_) {
      wsOk = false;
    }

    return RemoteRpcProbeResult(ok: true, version: version, wsReachable: wsOk);
  } catch (e) {
    return RemoteRpcProbeResult(ok: false, error: '$e');
  }
}
