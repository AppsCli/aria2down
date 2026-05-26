// TaskHistoryEntry 序列化容错回归测试。
//
// 修复 #11 前 `fromJson` 用 `as int?` 强转 totalLength / completedLength —
// 任何把数值字段当字符串写入的历史 JSON（手动编辑 / 旧版本导出 / 直接转储
// aria2 RPC 响应）都会触发 TypeError 让整条历史无法反序列化。修复后改走
// `int.tryParse('$v')`，统一接受 int / num / 字符串 / 带空白 / null。

import 'package:aria2down/data/models/task_history_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromJson 接受 int 数值字段（向后兼容旧版本导出）', () {
    final e = TaskHistoryEntry.fromJson({
      'gid': 'g1',
      'name': 't',
      'status': 'complete',
      'totalLength': 12345,
      'completedLength': 12345,
      'recordedAt': '2024-01-01T00:00:00Z',
    });
    expect(e.totalLength, 12345);
    expect(e.completedLength, 12345);
  });

  test('fromJson 接受字符串数值字段（手编 JSON / RPC 原样转储）', () {
    final e = TaskHistoryEntry.fromJson({
      'gid': 'g1',
      'name': 't',
      'status': 'complete',
      'totalLength': '12345',
      'completedLength': '1024',
      'recordedAt': '2024-01-01T00:00:00Z',
    });
    expect(e.totalLength, 12345);
    expect(e.completedLength, 1024);
  });

  test('fromJson 接受 num（含浮点表达 1.0）数值字段', () {
    final e = TaskHistoryEntry.fromJson({
      'gid': 'g1',
      'name': 't',
      'status': 'complete',
      'totalLength': 12345.0,
      'completedLength': 0,
      'recordedAt': '2024-01-01T00:00:00Z',
    });
    expect(e.totalLength, 12345);
    expect(e.completedLength, 0);
  });

  test('fromJson 缺失/空字符串数值字段时降级到 0', () {
    final e = TaskHistoryEntry.fromJson({
      'gid': 'g1',
      'name': 't',
      'status': 'complete',
      // totalLength 缺失，completedLength 空串
      'completedLength': '',
      'recordedAt': '2024-01-01T00:00:00Z',
    });
    expect(e.totalLength, 0);
    expect(e.completedLength, 0);
  });

  test('toDetailShape 合成 tellStatus 形状的快照用于详情页 fallback', () {
    // 用户从历史 Tab 点进详情页，但任务已经不在 aria2 session 里——详情页
    // 会调 _loadHistorySnapshot → toDetailShape 把历史条目转成 tellStatus
    // 兼容结构，三个 Tab 仍然能渲染（只读快照模式）。
    final e = TaskHistoryEntry(
      gid: '2089b05ecca3d829',
      name: 'movie.mkv',
      status: 'complete',
      totalLength: 1234567,
      completedLength: 1234567,
      recordedAt: DateTime.utc(2025, 1, 1),
      dir: '/Downloads',
      errorMessage: null,
      uris: const ['https://a/movie.mkv', 'https://mirror/movie.mkv'],
      infoHash: null,
    );
    final shape = e.toDetailShape();
    expect(shape['gid'], '2089b05ecca3d829');
    expect(shape['status'], 'complete');
    // tellStatus 数字字段在 aria2 RPC 里是十进制字符串——保持同样形状方便
    // `int.tryParse('${...}')` 直接消费，无需特殊分支。
    expect(shape['totalLength'], '1234567');
    expect(shape['completedLength'], '1234567');
    expect(shape['dir'], '/Downloads');
    final files = shape['files'] as List;
    expect(files.length, 1);
    final f = files.single as Map;
    expect(f['path'], 'movie.mkv'); // pickTaskName 用得上
    final uris = f['uris'] as List;
    expect(uris.length, 2);
    expect((uris.first as Map)['uri'], 'https://a/movie.mkv');
  });

  test('toDetailShape 在 BT 任务上把 infoHash 暴露到顶层与 bittorrent.info', () {
    // task_detail_page 的 Overview Tab 读 status['infoHash']，Torrent Tab 读
    // status['bittorrent']，两路都要喂到——之前 toRetryTaskShape 只塞顶层
    // 让 BT Tab 渲染时缺 bittorrent 字段。
    final e = TaskHistoryEntry(
      gid: 'g1',
      name: 'mybt',
      status: 'complete',
      totalLength: 0,
      completedLength: 0,
      recordedAt: DateTime.utc(2025),
      uris: const [],
      infoHash: 'deadbeef',
    );
    final shape = e.toDetailShape();
    expect(shape['infoHash'], 'deadbeef');
    final bt = shape['bittorrent'] as Map;
    expect((bt['info'] as Map)['name'], 'mybt');
  });

  test('toJson → fromJson roundtrip 对所有字段保持稳定', () {
    final e1 = TaskHistoryEntry(
      gid: 'g1',
      name: 'My Task',
      status: 'complete',
      totalLength: 1024,
      completedLength: 1024,
      recordedAt: DateTime.utc(2025, 1, 1, 12, 30),
      dir: '/tmp',
      errorMessage: null,
      uris: const ['https://a/b', 'magnet:?xt=urn:btih:abc'],
      infoHash: 'deadbeef',
    );
    final e2 = TaskHistoryEntry.fromJson(e1.toJson());
    expect(e2.gid, e1.gid);
    expect(e2.name, e1.name);
    expect(e2.status, e1.status);
    expect(e2.totalLength, e1.totalLength);
    expect(e2.completedLength, e1.completedLength);
    expect(e2.recordedAt.toIso8601String(), e1.recordedAt.toIso8601String());
    expect(e2.dir, e1.dir);
    expect(e2.uris, e1.uris);
    expect(e2.infoHash, e1.infoHash);
  });
}
