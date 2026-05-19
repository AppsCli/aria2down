/// 任务名、字节与速度格式化（UI 与历史记录共用）。
String pickTaskName(Map<String, dynamic> t) {
  final files = t['files'];
  if (files is List && files.isNotEmpty) {
    final first = files.first;
    if (first is Map) {
      final uris = first['uris'];
      if (uris is List && uris.isNotEmpty) {
        final u = uris.first;
        if (u is Map && u['uri'] != null) {
          final uri = '${u['uri']}';
          final slash = uri.lastIndexOf('/');
          if (slash >= 0 && slash < uri.length - 1) {
            return uri.substring(slash + 1);
          }
          return uri;
        }
      }
      if (first['path'] != null) {
        final path = '${first['path']}';
        final sep = path.replaceAll('\\', '/').lastIndexOf('/');
        if (sep >= 0 && sep < path.length - 1) {
          return path.substring(sep + 1);
        }
        return path;
      }
    }
  }
  final bt = t['bittorrent'];
  if (bt is Map && bt['name'] != null) return '${bt['name']}';
  return t['bittorrent'] != null ? 'BitTorrent' : 'Task';
}

String formatBytes(Object? v) {
  final n = int.tryParse('$v') ?? 0;
  if (n < 1024) return '$n B';
  final kb = n / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KiB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MiB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(2)} GiB';
}

String formatSpeed(Object? v) {
  final n = int.tryParse('$v') ?? 0;
  return '${formatBytes(n)}/s';
}
