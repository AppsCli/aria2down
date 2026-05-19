import 'package:aria2down/aria2/client/aria2_client.dart';
import 'package:aria2down/aria2/client/http_transport.dart';

import 'local_rpc_credentials.dart';

/// 使用已保存的本机 `rpc.secret` 向运行中的 aria2 添加 URI。
Future<String> addUrisViaStoredCredentials(List<String> uris) async {
  if (uris.isEmpty) {
    throw ArgumentError('uris 不能为空');
  }
  final creds = await readLocalRpcCredentials();
  if (creds == null) {
    throw StateError('未找到 rpc.secret，请先启动本机 aria2');
  }
  final transport = Aria2HttpTransport(
    endpoint: creds.httpJsonRpcUri,
    secret: creds.secret,
  );
  final client = Aria2Client(transport: transport);
  await client.getVersion();
  return client.addUri(uris);
}
