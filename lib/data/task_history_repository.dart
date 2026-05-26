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

  /// 按 gid 删除单条历史记录。返回是否真正删掉了一条。
  ///
  /// 历史 Tab / 详情页历史快照 banner 的「从历史中删除」按钮用此入口：与
  /// aria2 `removeDownloadResult` 不同，这是**纯本地**操作——任务很可能已
  /// 被 `purgeDownloadResult` 清出 session（返回 -1006），用户期望的"删除"
  /// 语义就是把本地条目擦掉。
  ///
  /// 不存在该 gid 时静默返回 false（用户可能在两个页面间手快连点了两次）。
  static Future<bool> deleteByGid(String gid) async {
    if (gid.isEmpty) return false;
    final all = await loadAll();
    final next = all.where((e) => e.gid != gid).toList();
    if (next.length == all.length) return false;
    final file = await _historyFile();
    await file.writeAsString(
      jsonEncode(next.map((e) => e.toJson()).toList()),
      flush: true,
    );
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', file.path]);
    }
    return true;
  }

  /// 查找指定 gid 的本地历史条目。
  ///
  /// 任务详情页在 `tellStatus` 失败（aria2 找不到该任务）时用这个做兜底，
  /// 让用户至少能看到曾经持久化的 name / size / uris / errorMessage 快照
  /// 而不是一个空错误页。找不到返回 null。
  static Future<TaskHistoryEntry?> findByGid(String gid) async {
    if (gid.isEmpty) return null;
    final all = await loadAll();
    for (final e in all) {
      if (e.gid == gid) return e;
    }
    return null;
  }
}
