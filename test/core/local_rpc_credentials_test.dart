import 'package:aria2down/core/local_rpc_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LocalRpcCredentials httpJsonRpcUri', () {
    const c = LocalRpcCredentials(port: 6800, secret: 'abc');
    expect(c.httpJsonRpcUri.port, 6800);
    expect(c.httpJsonRpcUri.path, '/jsonrpc');
    expect(c.extensionConfigJson, contains('6800'));
  });
}
