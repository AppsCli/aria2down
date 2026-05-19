import 'package:aria2down/core/format_utils.dart' show pickTaskName;
import 'package:aria2down/core/reveal_path.dart' show extractUrisFromTask;
import 'package:aria2down/data/models/task_history_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TaskHistoryEntry fromTellStatus and toRetryTaskShape', () {
    final st = {
      'gid': 'deadbeef',
      'status': 'complete',
      'totalLength': '1000',
      'completedLength': '1000',
      'dir': '/tmp/dl',
      'files': [
        {
          'uris': [
            {'uri': 'https://example.com/a.zip'},
          ],
        },
      ],
    };
    final entry = TaskHistoryEntry.fromTellStatus(st);
    expect(entry.gid, 'deadbeef');
    expect(entry.name, pickTaskName(st));
    expect(entry.uris, ['https://example.com/a.zip']);

    final retry = entry.toRetryTaskShape();
    expect(extractUrisFromTask(retry), entry.uris);
  });

  test('TaskHistoryEntry JSON round-trip', () {
    final entry = TaskHistoryEntry(
      gid: '1',
      name: 'n',
      status: 'error',
      totalLength: 10,
      completedLength: 0,
      recordedAt: DateTime.utc(2026, 1, 1),
      errorMessage: 'timeout',
    );
    final json = entry.toJson();
    final restored = TaskHistoryEntry.fromJson(json);
    expect(restored.gid, entry.gid);
    expect(restored.errorMessage, 'timeout');
  });
}
