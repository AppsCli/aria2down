/// 从 `/add?uri=` 或 `/add?uris=` 查询参数解析预填链接。
List<String> parsePrefillUrisFromQuery(Uri uri) {
  final out = <String>[];
  final single = uri.queryParameters['uri'];
  if (single != null && single.trim().isNotEmpty) {
    out.add(Uri.decodeComponent(single.trim()));
  }
  final multi = uri.queryParameters['uris'];
  if (multi != null && multi.trim().isNotEmpty) {
    for (final line in multi.split(RegExp(r'[\r\n]+'))) {
      final t = Uri.decodeComponent(line.trim());
      if (t.isNotEmpty) out.add(t);
    }
  }
  return out;
}
