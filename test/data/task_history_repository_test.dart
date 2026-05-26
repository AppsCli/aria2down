import 'dart:io';

import 'package:aria2down/core/format_utils.dart' show pickTaskName;
import 'package:aria2down/core/reveal_path.dart' show extractUrisFromTask;
import 'package:aria2down/data/models/task_history_entry.dart';
import 'package:aria2down/data/task_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// 把 `path_provider` 重定向到临时目录，让纯单测能驱动
/// `TaskHistoryRepository`（默认实现写 ApplicationSupportDirectory，需要平
/// 台插件）。tearDown 时把临时目录连同 task_history.json 一并清理。
class _TempPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempPathProvider(this.root);
  final Directory root;

  @override
  Future<String?> getApplicationSupportPath() async => root.path;
}

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

  group('TaskHistoryRepository.deleteByGid', () {
    late Directory tempRoot;
    late PathProviderPlatform originalPlatform;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      originalPlatform = PathProviderPlatform.instance;
      tempRoot = await Directory.systemTemp.createTemp('aria2down_test_');
      PathProviderPlatform.instance = _TempPathProvider(tempRoot);
    });

    tearDown(() async {
      PathProviderPlatform.instance = originalPlatform;
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('删除存在的 gid → 返回 true，且 loadAll 不再含该条', () async {
      final entries = [
        TaskHistoryEntry(
          gid: 'aaa',
          name: 'A',
          status: 'complete',
          totalLength: 1,
          completedLength: 1,
          recordedAt: DateTime.utc(2026, 5, 26, 10),
        ),
        TaskHistoryEntry(
          gid: 'bbb',
          name: 'B',
          status: 'error',
          totalLength: 1,
          completedLength: 0,
          recordedAt: DateTime.utc(2026, 5, 26, 11),
        ),
      ];
      await TaskHistoryRepository.upsertMany(entries);

      final removed = await TaskHistoryRepository.deleteByGid('aaa');
      expect(removed, isTrue);

      final remaining = await TaskHistoryRepository.loadAll();
      expect(remaining.map((e) => e.gid).toList(), ['bbb']);
    });

    test('删除不存在的 gid → 返回 false，且 loadAll 不变', () async {
      final entry = TaskHistoryEntry(
        gid: 'ccc',
        name: 'C',
        status: 'complete',
        totalLength: 1,
        completedLength: 1,
        recordedAt: DateTime.utc(2026, 5, 26),
      );
      await TaskHistoryRepository.upsert(entry);

      final removed = await TaskHistoryRepository.deleteByGid('not-there');
      expect(removed, isFalse);

      final remaining = await TaskHistoryRepository.loadAll();
      expect(remaining.map((e) => e.gid).toList(), ['ccc']);
    });

    test('空 gid 直接返回 false，不读盘', () async {
      final removed = await TaskHistoryRepository.deleteByGid('');
      expect(removed, isFalse);
      // 历史文件不应被意外创建
      final historyFile = File(
        p.join(tempRoot.path, 'aria2down', 'task_history.json'),
      );
      expect(await historyFile.exists(), isFalse);
    });

    test('删除最后一条后文件存在但内容为 []，仍可继续 upsert', () async {
      await TaskHistoryRepository.upsert(
        TaskHistoryEntry(
          gid: 'only',
          name: 'O',
          status: 'complete',
          totalLength: 1,
          completedLength: 1,
          recordedAt: DateTime.utc(2026, 5, 26),
        ),
      );
      expect(await TaskHistoryRepository.deleteByGid('only'), isTrue);
      expect(await TaskHistoryRepository.loadAll(), isEmpty);

      // 再写一条，确认不会被遗留状态影响。
      await TaskHistoryRepository.upsert(
        TaskHistoryEntry(
          gid: 'next',
          name: 'N',
          status: 'complete',
          totalLength: 1,
          completedLength: 1,
          recordedAt: DateTime.utc(2026, 5, 27),
        ),
      );
      final after = await TaskHistoryRepository.loadAll();
      expect(after.map((e) => e.gid).toList(), ['next']);
    });
  });
}
