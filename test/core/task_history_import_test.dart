import 'package:aria2down/core/task_history_export.dart';
import 'package:aria2down/core/task_history_import.dart';
import 'package:aria2down/data/models/task_history_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseTaskHistoryEntries from export format', () {
    final exported = exportTaskHistoryJson([
      TaskHistoryEntry(
        gid: 'g1',
        name: 'n',
        status: 'complete',
        totalLength: 1,
        completedLength: 1,
        recordedAt: DateTime.utc(2026, 1, 1),
      ),
    ]);
    final entries = parseTaskHistoryEntries(exported);
    expect(entries.length, 1);
    expect(entries.first.gid, 'g1');
  });
}
