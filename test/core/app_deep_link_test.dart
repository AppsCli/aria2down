import 'package:aria2down/core/app_deep_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildInAppAddPath encodes uri', () {
    expect(
      buildInAppAddPath('https://example.com/a b'),
      '/add?uri=${Uri.encodeComponent('https://example.com/a b')}',
    );
  });

  test('buildInAppAddPathForUris multiple', () {
    final p = buildInAppAddPathForUris(['https://a', 'magnet:?xt=1']);
    expect(p, startsWith('/add?uris='));
    expect(Uri.decodeComponent(p.split('=').last), 'https://a\nmagnet:?xt=1');
  });
}
