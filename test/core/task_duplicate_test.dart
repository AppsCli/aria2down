import 'package:aria2down/core/task_duplicate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('taskListContainsUri matches files.uris', () {
    final tasks = [
      {
        'files': [
          {
            'uris': [
              {'uri': 'https://example.com/a.bin'},
            ],
          },
        ],
      },
    ];
    expect(taskListContainsUri(tasks, 'https://example.com/a.bin'), isTrue);
    expect(taskListContainsUri(tasks, 'https://other.com/x'), isFalse);
  });

  test('filterNewUris skips duplicates', () {
    final tasks = [
      {
        'files': [
          {
            'uris': [
              {'uri': 'https://example.com/a'},
            ],
          },
        ],
      },
    ];
    final (added, skipped) = filterNewUris(tasks, [
      'https://example.com/a',
      'https://example.com/b',
    ]);
    expect(added, ['https://example.com/b']);
    expect(skipped, 1);
  });
}
