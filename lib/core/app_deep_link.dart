/// 应用内「新建任务」深链路径（供 [GoRouter] 与剪贴板分享）。
String buildInAppAddPath(String uri) =>
    '/add?uri=${Uri.encodeComponent(uri.trim())}';

/// 多链接时使用 `uris` 查询参数（换行分隔）。
String buildInAppAddPathForUris(Iterable<String> uris) {
  final list = uris.map((u) => u.trim()).where((u) => u.isNotEmpty).toList();
  if (list.isEmpty) return '/add';
  if (list.length == 1) return buildInAppAddPath(list.single);
  return '/add?uris=${Uri.encodeComponent(list.join('\n'))}';
}
