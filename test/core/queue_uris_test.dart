import 'package:aria2down/aria2/client/aria2_client.dart';
import 'package:aria2down/aria2/client/rpc_methods.dart';
import 'package:aria2down/aria2/client/rpc_transport.dart';
import 'package:aria2down/core/queue_uris.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements Aria2RpcTransport {
  @override
  Future<Object?> call(String method, List<dynamic> params) async {
    if (method == RpcMethods.tellActive) return <Map<String, dynamic>>[];
    if (method == RpcMethods.tellWaiting) return <Map<String, dynamic>>[];
    if (method == RpcMethods.addUri) return 'gid1';
    throw UnimplementedError(method);
  }
}

void main() {
  test('queueUrisToAria2 adds new uri', () async {
    final client = Aria2Client(transport: _FakeTransport());
    final r = await queueUrisToAria2(client, ['https://a/b']);
    expect(r.added, 1);
    expect(r.skipped, 0);
  });
}
