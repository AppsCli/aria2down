import 'package:aria2down/core/remote_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parse host:port', () {
    final e = parseRemoteRpcEndpoint('192.168.1.10:6800');
    expect(e.host, '192.168.1.10');
    expect(e.port, 6800);
    expect(e.useTls, false);
  });

  test('parse http URL with path', () {
    final e = parseRemoteRpcEndpoint('http://nas.local:6800/jsonrpc');
    expect(e.host, 'nas.local');
    expect(e.port, 6800);
    expect(
      e.httpJsonRpcUri('/jsonrpc').toString(),
      'http://nas.local:6800/jsonrpc',
    );
  });

  test('parse https implies TLS', () {
    final e = parseRemoteRpcEndpoint('https://example.com:443/jsonrpc');
    expect(e.useTls, true);
    expect(e.wsScheme, 'wss');
  });
}
