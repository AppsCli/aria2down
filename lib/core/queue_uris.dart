import '../aria2/client/aria2_client.dart';
import 'task_duplicate.dart';
import 'task_list_keys.dart';

/// 向 aria2 入队 URI，并返回添加/跳过数量。
typedef QueueUrisResult = ({int added, int skipped});

Future<QueueUrisResult> queueUrisToAria2(
  Aria2Client client,
  List<String> uris, {
  Map<String, dynamic>? options,
}) async {
  if (uris.isEmpty) {
    return (added: 0, skipped: 0);
  }
  final active = await client.tellActive(keys: kTaskListTellKeys);
  final waiting = await client.tellWaiting(
    offset: 0,
    num: 500,
    keys: kTaskListTellKeys,
  );
  final existing = <Map<String, dynamic>>[...active, ...waiting];
  final (newUris, skipped) = filterNewUris(existing, uris);
  if (newUris.isEmpty) {
    return (added: 0, skipped: skipped);
  }
  await client.addUri(
    newUris,
    options: options == null || options.isEmpty ? null : options,
  );
  return (added: newUris.length, skipped: skipped);
}
