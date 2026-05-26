import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../aria2/daemon/local_daemon_paths.dart';

/// 本机 aria2 RPC 凭据（与 [LocalDaemon] 写入的 `rpc.secret` 一致）。
class LocalRpcCredentials {
  const LocalRpcCredentials({required this.port, required this.secret});

  final int port;
  final String secret;

  Uri get httpJsonRpcUri => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: '/jsonrpc',
  );

  /// 用 `JsonEncoder` 生成，避免 secret 中的 `"` / `\` / 换行等字符破坏
  /// JSON 结构（虽然 `_generateSecret` 当前只产 hex，但用户/将来的实现
  /// 可能允许自定义 token，必须按字符串规范转义）。
  String get extensionConfigJson => const JsonEncoder.withIndent(
    '  ',
  ).convert({'rpcUrl': httpJsonRpcUri.toString(), 'secret': secret});
}

/// 读取已持久化的本机 RPC 端口与 token（aria2 未运行也可能存在）。
Future<LocalRpcCredentials?> readLocalRpcCredentials() async {
  final file = File(p.join(await LocalDaemonPaths.stateRoot(), 'rpc.secret'));
  if (!await file.exists()) return null;
  final lines = await file.readAsLines();
  if (lines.length < 2) return null;
  final port = int.tryParse(lines.first.trim());
  final secret = lines[1].trim();
  if (port == null || secret.isEmpty) return null;
  return LocalRpcCredentials(port: port, secret: secret);
}
