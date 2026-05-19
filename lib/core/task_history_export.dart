import 'dart:convert';

import '../data/models/task_history_entry.dart';

/// 导出任务历史为 JSON（剪贴板 / 备份）。
String exportTaskHistoryJson(List<TaskHistoryEntry> entries) {
  final payload = <String, dynamic>{
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'count': entries.length,
    'entries': entries.map((e) => e.toJson()).toList(),
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}
