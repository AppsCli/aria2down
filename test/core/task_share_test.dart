import 'package:aria2down/core/task_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildTaskShareText joins uris', () {
    final text = buildTaskShareText({
      'gid': 'abc',
      'files': [
        {
          'uris': [
            {'uri': 'https://example.com/file.zip'},
          ],
        },
      ],
    });
    expect(text, 'https://example.com/file.zip');
  });
}
