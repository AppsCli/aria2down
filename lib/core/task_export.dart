import 'dart:convert';

/// 将任务列表导出为 JSON（用于剪贴板/调试）。
String exportTasksSnapshot({
  required List<Map<String, dynamic>> active,
  required List<Map<String, dynamic>> waiting,
  required List<Map<String, dynamic>> stopped,
  Map<String, dynamic>? globalStat,
  Map<String, dynamic>? version,
}) {
  final payload = <String, dynamic>{
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'active': active,
    'waiting': waiting,
    'stopped': stopped,
    if (globalStat != null) 'globalStat': globalStat,
    if (version != null) 'version': version,
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}
