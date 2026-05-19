import 'dart:io';

import 'package:aria2down/core/add_uri_via_local_rpc.dart';
import 'package:aria2down/core/uri_utils.dart';

/// 向本机已运行的 aria2 添加下载（读取 `rpc.secret`）。
///
/// 用法：`dart run bin/rpc_add_uri.dart <url> [url2 ...]`
Future<void> main(List<String> args) async {
  final uris = <String>[];
  for (final a in args) {
    uris.addAll(extractDownloadUrisFromText(a));
  }
  if (uris.isEmpty) {
    stderr.writeln(
      '用法: dart run bin/rpc_add_uri.dart <http(s)://...|magnet:...>',
    );
    exit(2);
  }

  try {
    final gid = await addUrisViaStoredCredentials(uris);
    stdout.writeln(gid);
  } catch (e) {
    stderr.writeln('$e');
    exit(1);
  }
}
