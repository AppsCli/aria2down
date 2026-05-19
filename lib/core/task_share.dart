import 'format_utils.dart';
import 'reveal_path.dart';

/// 将任务的可分享文本（URI 列表或 BT 名称）合并为单行/多行字符串。
String buildTaskShareText(Map<String, dynamic> task) {
  final uris = extractUrisFromTask(task);
  if (uris.isNotEmpty) {
    return uris.join('\n');
  }
  final name = pickTaskName(task);
  return name.isNotEmpty ? name : '${task['gid']}';
}
