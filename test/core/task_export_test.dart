import 'dart:convert';

import 'package:aria2down/core/task_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exportTasksSnapshot produces valid JSON with tasks', () {
    final json = exportTasksSnapshot(
      active: [
        {'gid': 'abc', 'status': 'active'},
      ],
      waiting: [],
      stopped: [],
      version: {'version': '1.37.0'},
    );
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    expect(decoded['active'], isA<List>());
    expect((decoded['active'] as List).length, 1);
    expect(decoded['version'], isNotNull);
    expect(decoded['exportedAt'], isA<String>());
  });
}
