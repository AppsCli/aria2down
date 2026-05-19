import 'dart:convert';

import 'package:aria2down/core/task_history_export.dart';
import 'package:aria2down/data/models/task_history_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exportTaskHistoryJson', () {
    final json = exportTaskHistoryJson([
      TaskHistoryEntry(
        gid: 'a',
        name: 'test',
        status: 'complete',
        totalLength: 100,
        completedLength: 100,
        recordedAt: DateTime.utc(2026, 1, 1),
        uris: const ['https://x'],
      ),
    ]);
    final map = jsonDecode(json) as Map<String, dynamic>;
    expect(map['count'], 1);
    expect((map['entries'] as List).length, 1);
  });
}
