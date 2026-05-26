import 'dart:convert';
import 'dart:io';

import 'package:aria2down/core/add_uri_via_local_rpc.dart';
import 'package:aria2down/core/uri_utils.dart';

/// Chrome/Firefox Native Messaging host：stdin 一行 JSON → addUri。
Future<void> main() async {
  final line = stdin.readLineSync();
  if (line == null || line.isEmpty) {
    _fail('empty message');
  }
  try {
    final msg = jsonDecode(line!) as Map<String, dynamic>;
    final raw = '${msg['url'] ?? msg['linkUrl'] ?? ''}'.trim();
    final uris = extractDownloadUrisFromText(raw);
    if (uris.isEmpty) {
      _fail('no url in message');
    }
    try {
      final gids = await addUrisViaStoredCredentials(uris);
      stdout.writeln(
        jsonEncode({
          'ok': true,
          // `gid` 保留为首个 gid，向后兼容旧扩展只读 `gid`；`gids` 为完整列表。
          'gid': gids.isNotEmpty ? gids.first : '',
          'gids': gids,
          'uris': uris,
        }),
      );
    } on PartialAddUrisException catch (e) {
      // 部分成功：保留已入队 gid，同时把失败原因报给扩展，让用户能看到
      // 「3 个链接成功 2 个，1 个失败」这种部分状态。
      stdout.writeln(
        jsonEncode({
          'ok': e.errors.isEmpty,
          'gid': e.addedGids.isNotEmpty ? e.addedGids.first : '',
          'gids': e.addedGids,
          'uris': uris,
          'errors': [
            for (final f in e.errors) {'uri': f.$1, 'error': '${f.$2}'},
          ],
        }),
      );
      if (e.errors.isNotEmpty) exit(1);
    }
  } catch (e) {
    _fail('$e');
  }
}

void _fail(String message) {
  stdout.writeln(jsonEncode({'ok': false, 'error': message}));
  exit(1);
}
