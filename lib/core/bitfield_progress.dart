/// 根据 aria2 `tellStatus` 的 hex [bitfield] 估算分块完成比例。
///
/// aria2 文档：每位十六进制字符表示 4 个分块位。
double? pieceCompletionFromBitfield({
  required String? hexBitfield,
  required int numPieces,
}) {
  if (numPieces <= 0 || hexBitfield == null || hexBitfield.isEmpty) {
    return null;
  }
  final hex = hexBitfield.trim();
  var completed = 0;
  for (var i = 0; i < numPieces; i++) {
    final charIndex = i ~/ 4;
    if (charIndex >= hex.length) break;
    final nibble = int.tryParse(hex[charIndex], radix: 16);
    if (nibble == null) continue;
    final bitInNibble = 3 - (i % 4);
    if ((nibble >> bitInNibble) & 1 == 1) {
      completed++;
    }
  }
  return completed / numPieces;
}

/// 字节进度（无 bitfield 时回退）。
double byteCompletion(Object? completed, Object? total) {
  final t = int.tryParse('$total') ?? 0;
  final c = int.tryParse('$completed') ?? 0;
  if (t <= 0) return 0;
  return (c / t).clamp(0.0, 1.0);
}
