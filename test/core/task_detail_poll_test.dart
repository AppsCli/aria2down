import 'package:aria2down/core/task_detail_poll.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('taskDetailPollInterval faster for active', () {
    expect(
      taskDetailPollInterval('active'),
      lessThan(taskDetailPollInterval('complete')),
    );
  });

  test('taskDetailPollInterval paused between active and complete', () {
    expect(
      taskDetailPollInterval('paused').inSeconds,
      greaterThan(taskDetailPollInterval('active').inSeconds),
    );
    expect(
      taskDetailPollInterval('paused').inSeconds,
      lessThan(taskDetailPollInterval('complete').inSeconds),
    );
  });
}
