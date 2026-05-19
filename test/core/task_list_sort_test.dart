import 'package:aria2down/core/task_list_sort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sortActiveByDownloadSpeed orders descending', () {
    final list = [
      {'gid': 'a', 'downloadSpeed': '100'},
      {'gid': 'b', 'downloadSpeed': '5000'},
      {'gid': 'c', 'downloadSpeed': '200'},
    ];
    sortActiveByDownloadSpeed(list);
    expect(list.map((e) => e['gid']).toList(), ['b', 'c', 'a']);
  });

  test('sortStoppedByCompletedTimeDesc orders newest first', () {
    final list = [
      {'gid': '1', 'completedTime': '100'},
      {'gid': '2', 'completedTime': '300'},
      {'gid': '3', 'completedTime': '200'},
    ];
    sortStoppedByCompletedTimeDesc(list);
    expect(list.map((e) => e['gid']).toList(), ['2', '3', '1']);
  });
}
