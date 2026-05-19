import 'package:aria2down/core/bitfield_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pieceCompletionFromBitfield 全完成', () {
    // 4 pieces -> 1 hex char (4 bits used)
    final r = pieceCompletionFromBitfield(hexBitfield: 'f', numPieces: 4);
    expect(r, 1.0);
  });

  test('byteCompletion', () {
    expect(byteCompletion(50, 100), 0.5);
    expect(byteCompletion(0, 0), 0);
  });
}
