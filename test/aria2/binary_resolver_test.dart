import 'dart:io';

import 'package:aria2down/aria2/binary/binary_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('bundledCandidatePath 以 aria2c 结尾', () {
    final c = BinaryResolver.bundledCandidatePath();
    expect(
      c,
      Platform.isWindows ? endsWith(r'aria2c.exe') : endsWith('aria2c'),
    );
    expect(p.isAbsolute(c), isTrue);
  });
}
