import 'dart:convert';

import 'package:aria2down/core/local_rpc_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LocalRpcCredentials httpJsonRpcUri', () {
    const c = LocalRpcCredentials(port: 6800, secret: 'abc');
    expect(c.httpJsonRpcUri.port, 6800);
    expect(c.httpJsonRpcUri.path, '/jsonrpc');
    expect(c.extensionConfigJson, contains('6800'));
  });

  test('extensionConfigJson 是合法 JSON 且保留 rpcUrl/secret', () {
    const c = LocalRpcCredentials(port: 6800, secret: 'abc');
    final decoded = jsonDecode(c.extensionConfigJson) as Map<String, dynamic>;
    expect(decoded['secret'], 'abc');
    expect(decoded['rpcUrl'], endsWith(':6800/jsonrpc'));
  });

  test('extensionConfigJson 正确转义包含特殊字符的 secret', () {
    // 含双引号、反斜杠、换行——之前用字符串拼接会生成非法 JSON，jsonDecode
    // 直接抛 FormatException。
    const c = LocalRpcCredentials(port: 6800, secret: 'a"b\\c\nd');
    final decoded = jsonDecode(c.extensionConfigJson) as Map<String, dynamic>;
    expect(decoded['secret'], 'a"b\\c\nd');
  });
}
