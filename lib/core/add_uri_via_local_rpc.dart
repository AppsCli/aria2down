import 'package:aria2down/aria2/client/aria2_client.dart';
import 'package:aria2down/aria2/client/http_transport.dart';
import 'package:aria2down/aria2/client/logging_transport.dart';

import 'local_rpc_credentials.dart';

/// 使用已保存的本机 `rpc.secret` 向运行中的 aria2 添加 URI。
///
/// **每个 URI 一个任务**：与 UI `queueUrisToAria2` 一致——之前实现把所有
/// URI 当作同一资源的镜像（一次 `aria2.addUri([url1,url2,url3])`），导致
/// CLI/扩展粘 3 个独立链接时只产生 1 个任务，与剪贴板粘贴行为不一致。
///
/// 任意一条 URI 失败会让整次调用抛 [PartialAddUrisException]，其中包含
/// 已成功入队的 gid 列表与失败明细，方便调用方部分回报给用户。
Future<List<String>> addUrisViaStoredCredentials(List<String> uris) async {
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
  final client = Aria2Client(
    transport: Aria2LoggingTransport(transport, label: 'localAddUri'),
  );
  await client.getVersion();

  final gids = <String>[];
  final errors = <(String uri, Object error)>[];
  for (final uri in uris) {
    try {
      final gid = await client.addUri(<String>[uri]);
      gids.add(gid);
    } catch (e) {
      errors.add((uri, e));
    }
  }
  if (errors.isNotEmpty) {
    throw PartialAddUrisException(addedGids: gids, errors: errors);
  }
  return gids;
}

/// 批量入队时部分失败：保留已成功 gid 与每条失败的 URI/异常。
class PartialAddUrisException implements Exception {
  PartialAddUrisException({required this.addedGids, required this.errors});

  final List<String> addedGids;
  final List<(String uri, Object error)> errors;

  @override
  String toString() {
    final ok = addedGids.length;
    final fail = errors.length;
    final firstErr = errors.isEmpty ? '' : ' first=${errors.first.$2}';
    return 'PartialAddUrisException: $ok 成功 / $fail 失败$firstErr';
  }
}
