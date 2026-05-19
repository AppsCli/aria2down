/// 将 aria2 `tellStatus` 的 `eta`（秒）格式化为可读字符串。
String? formatEta(Object? raw) {
  final sec = int.tryParse('$raw');
  if (sec == null || sec < 0) return null;
  if (sec == 0) return null;
  if (sec < 60) return '${sec}s';
  final m = sec ~/ 60;
  final s = sec % 60;
  if (m < 60) return s > 0 ? '${m}m ${s}s' : '${m}m';
  final h = m ~/ 60;
  final rm = m % 60;
  return rm > 0 ? '${h}h ${rm}m' : '${h}h';
}
