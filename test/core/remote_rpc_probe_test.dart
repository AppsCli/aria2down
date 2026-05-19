import 'package:aria2down/core/remote_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseRemoteRpcEndpoint for probe input', () {
    final e = parseRemoteRpcEndpoint('127.0.0.1:6800');
    expect(e.host, '127.0.0.1');
    expect(e.port, 6800);
    expect(e.httpJsonRpcUri('/jsonrpc').toString(), contains('127.0.0.1:6800'));
  });
}
