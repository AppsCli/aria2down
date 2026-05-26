// 拆 Tab 后的两路 status 分流必须正交（同一任务不会同时出现在 completed 与
// stopped），未知 status 也不能被两边都丢掉——否则用户在 UI 上看不到 aria2
// 已知存在的任务。

import 'package:aria2down/core/task_list_split.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('filterCompletedTasks', () {
    test('仅返回 status == "complete" 的任务，顺序保留', () {
      final src = <Map<String, dynamic>>[
        {'gid': 'a', 'status': 'complete'},
        {'gid': 'b', 'status': 'error'},
        {'gid': 'c', 'status': 'complete'},
        {'gid': 'd', 'status': 'removed'},
      ];
      final out = filterCompletedTasks(src);
      expect(out.map((e) => e['gid']).toList(), ['a', 'c']);
    });

    test('空 status / 缺 status 字段都不算 complete', () {
      final src = <Map<String, dynamic>>[
        {'gid': 'a', 'status': ''},
        {'gid': 'b'}, // 没有 status 键
        {'gid': 'c', 'status': null},
      ];
      expect(filterCompletedTasks(src), isEmpty);
    });

    test('空输入返回空 list', () {
      expect(filterCompletedTasks(const []), isEmpty);
    });
  });

  group('filterStoppedTasks', () {
    test('返回所有非 "complete" 任务（error / removed / 未知），顺序保留', () {
      final src = <Map<String, dynamic>>[
        {'gid': 'a', 'status': 'complete'},
        {'gid': 'b', 'status': 'error'},
        {'gid': 'c', 'status': 'removed'},
        {'gid': 'd', 'status': 'unknown-future-status'},
      ];
      final out = filterStoppedTasks(src);
      expect(out.map((e) => e['gid']).toList(), ['b', 'c', 'd']);
    });

    test('未知 status 优先落到「已停止」侧避免被丢掉', () {
      // aria2 未来若新增 stopped 子状态（譬如 "expired"），UI 不应该让任务
      // 在两个 Tab 都消失——拆 Tab 是给用户更细的视图，不是让任务隐身。
      final src = <Map<String, dynamic>>[
        {'gid': 'x', 'status': 'expired'},
        {'gid': 'y'},
        {'gid': 'z', 'status': ''},
      ];
      final out = filterStoppedTasks(src);
      expect(out.map((e) => e['gid']).toList(), ['x', 'y', 'z']);
    });
  });

  test('两路互补：任何 status 的任务必恰好出现在其中一路', () {
    final src = <Map<String, dynamic>>[
      {'gid': 'a', 'status': 'complete'},
      {'gid': 'b', 'status': 'error'},
      {'gid': 'c', 'status': 'removed'},
      {'gid': 'd'},
      {'gid': 'e', 'status': 'future'},
    ];
    final completed = filterCompletedTasks(src);
    final stopped = filterStoppedTasks(src);
    expect(completed.length + stopped.length, src.length);
    final completedGids = completed.map((e) => e['gid']).toSet();
    final stoppedGids = stopped.map((e) => e['gid']).toSet();
    expect(
      completedGids.intersection(stoppedGids),
      isEmpty,
      reason: '同一任务不能同时出现在两个 Tab',
    );
  });
}
