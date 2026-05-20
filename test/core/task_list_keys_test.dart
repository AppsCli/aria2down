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
  });
}
