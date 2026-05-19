import 'reveal_path.dart';

/// 判断任务列表中是否已包含某下载 URI（粗略匹配）。
bool taskListContainsUri(List<Map<String, dynamic>> tasks, String uri) {
  final normalized = _normalizeUri(uri);
  if (normalized.isEmpty) return false;
  for (final t in tasks) {
    for (final u in extractUrisFromTask(t)) {
      if (_normalizeUri(u) == normalized) return true;
    }
  }
  return false;
}

/// 从列表中过滤掉已存在的 URI，返回 [newUris, skippedCount]。
(List<String> newUris, int skipped) filterNewUris(
  List<Map<String, dynamic>> existingTasks,
  List<String> uris,
) {
  final out = <String>[];
  var skipped = 0;
  for (final u in uris) {
    if (taskListContainsUri(existingTasks, u)) {
      skipped++;
    } else {
      out.add(u);
    }
  }
  return (out, skipped);
}

String _normalizeUri(String raw) => raw.trim().toLowerCase();
