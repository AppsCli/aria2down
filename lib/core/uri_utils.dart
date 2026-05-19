/// 从任意文本中提取可交给 aria2 的链接。
List<String> extractDownloadUrisFromText(String text) {
  final out = <String>[];
  final seen = <String>{};

  void add(String raw) {
    final t = raw.trim();
    if (t.isEmpty || seen.contains(t)) return;
    if (_isValidDownloadUri(t)) {
      seen.add(t);
      out.add(t);
    }
  }

  for (final line in text.split(RegExp(r'[\r\n]+'))) {
    for (final part in line.split(RegExp(r'[\s,;]+'))) {
      add(part);
    }
  }

  // 行内未分隔的 magnet
  final magnetRe = RegExp(r'magnet:\?[^\s"<>]+', caseSensitive: false);
  for (final m in magnetRe.allMatches(text)) {
    add(m.group(0)!);
  }

  final urlRe = RegExp(
    r'https?://[^\s"<>]+|ftp://[^\s"<>]+|sftp://[^\s"<>]+',
    caseSensitive: false,
  );
  for (final m in urlRe.allMatches(text)) {
    add(m.group(0)!);
  }

  return out;
}

bool _isValidDownloadUri(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return false;
  if (t.startsWith('magnet:?')) {
    return t.toLowerCase().contains('btih');
  }
  final u = Uri.tryParse(t);
  if (u == null || !u.hasScheme || u.host.isEmpty) return false;
  const ok = {'http', 'https', 'ftp', 'sftp'};
  return ok.contains(u.scheme.toLowerCase());
}
