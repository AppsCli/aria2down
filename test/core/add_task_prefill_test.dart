import 'package:aria2down/core/add_task_prefill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parsePrefillUrisFromQuery single uri', () {
    final u = Uri.parse('/add?uri=${Uri.encodeComponent('https://a/b')}');
    expect(parsePrefillUrisFromQuery(u), ['https://a/b']);
  });

  test('parsePrefillUrisFromQuery multiline uris param', () {
    final u = Uri.parse(
      '/add?uris=${Uri.encodeComponent('https://a\nmagnet:?xt=1')}',
    );
    expect(parsePrefillUrisFromQuery(u), ['https://a', 'magnet:?xt=1']);
  });
}
