import 'package:aria2down/core/eta_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatEta', () {
    expect(formatEta(45), '45s');
    expect(formatEta(125), '2m 5s');
    expect(formatEta(null), isNull);
  });
}
