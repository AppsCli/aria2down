import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models/task_history_entry.dart';

/// 本地 JSON 文件持久化任务历史（最多 [maxEntries] 条）。
final class TaskHistoryRepository {
  TaskHistoryRepository._();

  static const maxEntries = 500;
  static const _fileName = 'task_history.json';

  static Future<File> _historyFile() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'aria2down'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, _fileName));
  }

  static Future<List<TaskHistoryEntry>> loadAll() async {
    final file = await _historyFile();
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map(
            (e) =>
                TaskHistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList()
        ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    } catch (_) {
      return [];
    }
  }

  static Future<void> upsert(TaskHistoryEntry entry) async {
    if (entry.gid.isEmpty) return;
    final all = await loadAll();
    final next = [entry, ...all.where((e) => e.gid != entry.gid)];
    final trimmed = next.take(maxEntries).toList();
    final file = await _historyFile();
    final encoded = jsonEncode(trimmed.map((e) => e.toJson()).toList());
    await file.writeAsString(encoded, flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', file.path]);
    }
  }

  static Future<void> upsertMany(Iterable<TaskHistoryEntry> entries) async {
    var all = await loadAll();
    for (final entry in entries) {
      if (entry.gid.isEmpty) continue;
      all = [entry, ...all.where((e) => e.gid != entry.gid)];
    }
    all.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    final trimmed = all.take(maxEntries).toList();
    final file = await _historyFile();
    await file.writeAsString(
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }

  static Future<void> clear() async {
    final file = await _historyFile();
    if (await file.exists()) {
      await file.delete();
    }
  }
}
