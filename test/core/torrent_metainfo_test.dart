import 'dart:io';

import 'package:aria2down/core/torrent_metainfo.dart';
import 'package:flutter_test/flutter_test.dart';

/// 这两个 .torrent fixture 是从 `third_party/aria2/test/` 复制到
/// `test/fixtures/` 的——主仓直接 commit 这两份小文件（249 B + 463 B）让
/// CI 的 `analyze-test` job 不再需要 `submodules: recursive` 拉整个 aria2
/// 源码，从而把 checkout 时间砍掉 1~2 分钟。
///
/// 来源是 aria2 项目长期稳定的测试种子（多文件 + 单文件两种 layout），
/// 当 aria2 升级时如果想验证最新解析效果，仍可手动从 submodule 同步覆盖。
void main() {
  test('parseTorrentFileList 多文件 torrent', () async {
    final bytes = await File(
      'test/fixtures/url-list-multiFile.torrent',
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
      'test/fixtures/single.torrent',
    ).readAsBytes();
    final list = parseTorrentFileList(bytes);
    expect(list.length, 1);
    expect(list.single.index, 1);
    expect(list.single.displayName, isNotEmpty);
  });
}
