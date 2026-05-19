import 'package:aria2down/core/uri_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extractDownloadUrisFromText http and magnet', () {
    const text = '''
    https://example.com/a.zip
    magnet:?xt=urn:btih:abc123def4567890123456789012345678901234
    ''';
    final uris = extractDownloadUrisFromText(text);
    expect(uris.length, 2);
    expect(uris.first, startsWith('https://'));
    expect(uris.last, startsWith('magnet:'));
  });

  test('extractDownloadUrisFromText ignores junk', () {
    expect(extractDownloadUrisFromText('not a url'), isEmpty);
  });
}
