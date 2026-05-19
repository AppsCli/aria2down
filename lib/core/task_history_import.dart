import 'dart:convert';

import '../data/models/task_history_entry.dart';
import '../data/task_history_repository.dart';

/// 解析任务历史 JSON（不写盘）。
List<TaskHistoryEntry> parseTaskHistoryEntries(String raw) {
  final decoded = jsonDecode(raw);
  final List<dynamic> items;
  if (decoded is Map<String, dynamic>) {
    final e = decoded['entries'];
    if (e is! List) {
      throw const FormatException('missing entries array');
    }
    items = e;
  } else if (decoded is List) {
    items = decoded;
  } else {
    throw const FormatException('unsupported history JSON');
  }
  return [
    for (final item in items)
      if (item is Map)
        TaskHistoryEntry.fromJson(Map<String, dynamic>.from(item)),
  ];
}

/// 从 JSON 导入任务历史（支持 `exportTaskHistoryJson` 格式或纯数组）。
Future<int> importTaskHistoryFromJson(String raw) async {
  final entries = parseTaskHistoryEntries(raw);
  if (entries.isEmpty) return 0;
  await TaskHistoryRepository.upsertMany(entries);
  return entries.length;
}
