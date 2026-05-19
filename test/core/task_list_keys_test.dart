import 'package:aria2down/core/task_list_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kTaskListTellKeys includes gid and files', () {
    expect(kTaskListTellKeys, contains('gid'));
    expect(kTaskListTellKeys, contains('files'));
    expect(kTaskListTellKeys.length, greaterThan(8));
  });
}
