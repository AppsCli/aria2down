import 'dart:io';

import 'package:aria2down/core/torrent_metainfo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseTorrentFileList 多文件 torrent', () async {
    final bytes = await File(
      'third_party/aria2/test/url-list-multiFile.torrent',
    ).readAsBytes();
    final list = parseTorrentFileList(bytes);
    expect(list.length, 2);
    expect(list[0].index, 1);
    expect(list[1].index, 2);
    expect(list[0].displayName, contains('aria2c'));
    expect(list[1].displayName, contains('tar.bz2'));
  });

  test('parseTorrentFileList 单文件 torrent', () async {
    final bytes = await File(
      'third_party/aria2/test/single.torrent',
    ).readAsBytes();
    final list = parseTorrentFileList(bytes);
    expect(list.length, 1);
    expect(list.single.index, 1);
    expect(list.single.displayName, isNotEmpty);
  });
}
