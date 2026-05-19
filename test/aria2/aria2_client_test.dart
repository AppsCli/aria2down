import 'package:aria2down/aria2/client/aria2_client.dart';
import 'package:aria2down/aria2/client/rpc_methods.dart';
import 'package:aria2down/aria2/client/rpc_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements Aria2RpcTransport {
  _FakeTransport(this._handler);
  final Future<Object?> Function(String method, List<dynamic> params) _handler;

  @override
  Future<Object?> call(String method, List<dynamic> params) =>
      _handler(method, params);
}

void main() {
  test('Aria2Client.getVersion 解析结果', () async {
    final client = Aria2Client(
      transport: _FakeTransport((method, params) async {
        expect(method, RpcMethods.getVersion);
        expect(params, isEmpty);
        return {'version': '1.37.0', 'enabledFeatures': <String>[]};
      }),
    );
    final v = await client.getVersion();
    expect(v['version'], '1.37.0');
  });

  test('Aria2Client.addUri 返回 gid', () async {
    final client = Aria2Client(
      transport: _FakeTransport((method, params) async {
        expect(method, RpcMethods.addUri);
        expect(params[0], ['https://a/b']);
        return '2089b05ecca3d829';
      }),
    );
    final gid = await client.addUri(['https://a/b']);
    expect(gid, '2089b05ecca3d829');
  });

  test('Aria2Client.getPeers 返回列表', () async {
    final client = Aria2Client(
      transport: _FakeTransport((method, params) async {
        expect(method, RpcMethods.getPeers);
        expect(params[0], 'gid1');
        return <Map<String, dynamic>>[
          {'ip': '10.0.0.1', 'port': '6881', 'downloadSpeed': '1024'},
        ];
      }),
    );
    final peers = await client.getPeers('gid1');
    expect(peers.length, 1);
    expect(peers.first['ip'], '10.0.0.1');
  });

  test('Aria2Client.forcePause 调用 RPC', () async {
    final client = Aria2Client(
      transport: _FakeTransport((method, params) async {
        expect(method, RpcMethods.forcePause);
        expect(params, ['gid1']);
        return null;
      }),
    );
    await client.forcePause('gid1');
  });

  test('Aria2Client.tellActive 可传 keys', () async {
    final client = Aria2Client(
      transport: _FakeTransport((method, params) async {
        expect(method, RpcMethods.tellActive);
        expect(params, [
          ['gid', 'status'],
        ]);
        return <Map<String, dynamic>>[];
      }),
    );
    final list = await client.tellActive(keys: ['gid', 'status']);
    expect(list, isEmpty);
  });

  test('Aria2Client.removeDownloadResult', () async {
    final client = Aria2Client(
      transport: _FakeTransport((method, params) async {
        expect(method, RpcMethods.removeDownloadResult);
        expect(params, ['gid1']);
        return null;
      }),
    );
    await client.removeDownloadResult('gid1');
  });

  test('Aria2Client.getFiles 返回列表', () async {
    final client = Aria2Client(
      transport: _FakeTransport((method, params) async {
        expect(method, RpcMethods.getFiles);
        expect(params[0], 'gid1');
        return <Map<String, dynamic>>[
          {
            'index': '1',
            'path': '/tmp/a.bin',
            'length': '100',
            'completedLength': '0',
            'selected': 'true',
          },
        ];
      }),
    );
    final files = await client.getFiles('gid1');
    expect(files.length, 1);
    expect(files.first['path'], '/tmp/a.bin');
  });
}
