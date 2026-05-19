/// 解析远程 aria2 RPC 端点（host:port 或 URL）。
class RemoteRpcEndpoint {
  const RemoteRpcEndpoint({
    required this.host,
    required this.port,
    this.useTls = false,
  });

  final String host;
  final int port;
  final bool useTls;

  String get scheme => useTls ? 'https' : 'http';
  String get wsScheme => useTls ? 'wss' : 'ws';

  Uri httpJsonRpcUri(String path) =>
      Uri(scheme: scheme, host: host, port: port, path: path);

  Uri webSocketJsonRpcUri(String path) =>
      Uri(scheme: wsScheme, host: host, port: port, path: path);
}

/// 将用户输入解析为 [RemoteRpcEndpoint]。
///
/// 支持：`host:port`、`http(s)://host:port`、`http(s)://host:port/jsonrpc`。
RemoteRpcEndpoint parseRemoteRpcEndpoint(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('RPC 地址不能为空');
  }

  if (trimmed.contains('://')) {
    final uri = Uri.parse(trimmed);
    if (uri.host.isEmpty) {
      throw FormatException('无效的 RPC 地址：$raw');
    }
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    return RemoteRpcEndpoint(
      host: uri.host,
      port: port,
      useTls: uri.scheme == 'https' || uri.scheme == 'wss',
    );
  }

  final hostPort = trimmed.split('/');
  final hp = hostPort.first;
  final colon = hp.lastIndexOf(':');
  if (colon <= 0 || colon >= hp.length - 1) {
    throw FormatException('无效的 RPC 地址（需要 host:port）：$raw');
  }
  final host = hp.substring(0, colon);
  final port = int.tryParse(hp.substring(colon + 1));
  if (host.isEmpty || port == null || port < 1 || port > 65535) {
    throw FormatException('无效的 RPC 地址：$raw');
  }
  return RemoteRpcEndpoint(host: host, port: port);
}
