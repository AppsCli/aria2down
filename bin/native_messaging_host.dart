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
    final gid = await addUrisViaStoredCredentials(uris);
    stdout.writeln(jsonEncode({'ok': true, 'gid': gid, 'uris': uris}));
  } catch (e) {
    _fail('$e');
  }
}

void _fail(String message) {
  stdout.writeln(jsonEncode({'ok': false, 'error': message}));
  exit(1);
}
