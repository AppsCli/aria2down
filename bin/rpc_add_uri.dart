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
    final gids = await addUrisViaStoredCredentials(uris);
    for (final g in gids) {
      stdout.writeln(g);
    }
  } on PartialAddUrisException catch (e) {
    // 部分成功：stdout 输出成功的 gid，stderr 列出失败明细并以 1 退出，
    // 方便调用方按行解析两路输出。
    for (final g in e.addedGids) {
      stdout.writeln(g);
    }
    for (final f in e.errors) {
      stderr.writeln('FAILED ${f.$1}: ${f.$2}');
    }
    exit(1);
  } catch (e) {
    stderr.writeln('$e');
    exit(1);
  }
}
