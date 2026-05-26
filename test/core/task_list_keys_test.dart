import 'package:aria2down/core/task_list_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kTaskListTellKeys is lean for list polling', () {
    expect(kTaskListTellKeys, contains('gid'));
    expect(kTaskListTellKeys, contains('files'));
    expect(kTaskListTellKeys, isNot(contains('bitfield')));
    expect(kTaskListTellKeys, isNot(contains('pieceLength')));
    expect(kTaskListTellKeys, isNot(contains('numPieces')));
    expect(kTaskListTellKeys, isNot(contains('connections')));
  });

  test('kTaskDetailTellKeys includes BT progress fields', () {
    expect(kTaskDetailTellKeys, containsAll(kTaskListTellKeys));
    expect(kTaskDetailTellKeys, contains('bitfield'));
    expect(kTaskDetailTellKeys, contains('connections'));
    // BT 顶层字段：tellStatus 把 infoHash/numSeeders/seeder 放在
    // 响应根而不是 bittorrent 子结构。任务详情 Torrent Tab 需要这些字段。
    expect(kTaskDetailTellKeys, contains('infoHash'));
    expect(kTaskDetailTellKeys, contains('numSeeders'));
    expect(kTaskDetailTellKeys, contains('seeder'));
  });

  test('kTaskHistoryTellKeys carries infoHash for BT history', () {
    expect(kTaskHistoryTellKeys, contains('infoHash'));
  });
}
