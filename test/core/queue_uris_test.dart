import 'package:aria2down/aria2/client/aria2_client.dart';
import 'package:aria2down/aria2/client/aria2_exceptions.dart';
import 'package:aria2down/aria2/client/rpc_methods.dart';
import 'package:aria2down/aria2/client/rpc_transport.dart';
import 'package:aria2down/core/queue_uris.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements Aria2RpcTransport {
  _FakeTransport({this.existing = const [], this.addUriHandler});

  final List<Map<String, dynamic>> existing;

  /// Optional override: when set, called instead of producing a stub gid.
  /// Throw inside to simulate per-URI addUri failure.
  final Future<String> Function(String uri)? addUriHandler;
  final addUriCalls = <List<String>>[];

  @override
  Future<Object?> call(String method, List<dynamic> params) async {
    if (method == RpcMethods.tellActive) return existing;
    if (method == RpcMethods.tellWaiting) return <Map<String, dynamic>>[];
    if (method == RpcMethods.addUri) {
      final uris = (params.first as List).map((e) => '$e').toList();
      addUriCalls.add(uris);
      if (addUriHandler != null) {
        return addUriHandler!(uris.single);
      }
      return 'gid${addUriCalls.length}';
    }
    throw UnimplementedError(method);
  }
}

void main() {
  test('queueUrisToAria2 adds new uri', () async {
    final t = _FakeTransport();
    final client = Aria2Client(transport: t);
    final r = await queueUrisToAria2(client, ['https://a/b']);
    expect(r.added, 1);
    expect(r.skipped, 0);
    expect(t.addUriCalls, [
      ['https://a/b'],
    ]);
  });

  test('queueUrisToAria2 creates one task per URI (not mirrors)', () async {
    final t = _FakeTransport();
    final client = Aria2Client(transport: t);
    final r = await queueUrisToAria2(client, [
      'https://a/file1',
      'https://b/file2',
      'magnet:?xt=urn:btih:abc',
    ]);
    expect(r.added, 3);
    expect(r.skipped, 0);
    // 关键不变量：N 个独立 URI -> N 次 addUri 调用，每次只携带一个 URI。
    expect(t.addUriCalls.length, 3);
    for (final call in t.addUriCalls) {
      expect(call.length, 1);
    }
    expect(t.addUriCalls.map((c) => c.single).toList(), [
      'https://a/file1',
      'https://b/file2',
      'magnet:?xt=urn:btih:abc',
    ]);
  });

  test('queueUrisToAria2 skips duplicates from active queue', () async {
    final existing = <Map<String, dynamic>>[
      {
        'gid': 'g',
        'files': [
          {
            'uris': [
              {'uri': 'https://a/dup'},
            ],
          },
        ],
      },
    ];
    final t = _FakeTransport(existing: existing);
    final client = Aria2Client(transport: t);
    final r = await queueUrisToAria2(client, [
      'https://a/dup',
      'https://a/new',
    ]);
    expect(r.added, 1);
    expect(r.skipped, 1);
    expect(t.addUriCalls, [
      ['https://a/new'],
    ]);
  });

  test('queueUrisToAria2 dedups duplicates inside the input list', () async {
    final t = _FakeTransport();
    final client = Aria2Client(transport: t);
    // 同一 URL 出现三次 + 大小写变体 + 前后空格——都应当合并成 1 个任务，
    // 其余两条计入 skipped。修复 A5 之前会产生 4 个独立任务。
    final r = await queueUrisToAria2(client, [
      'https://a/file',
      'https://a/file',
      'HTTPS://A/FILE',
      '  https://a/file  ',
      'https://b/another',
    ]);
    expect(r.added, 2, reason: '相同 URI 仅入队一次，magnet 单独一次');
    expect(r.skipped, 3, reason: '前 4 条只保留 1 条，剩下 3 条算 skipped');
    expect(t.addUriCalls.map((c) => c.single).toList(), [
      'https://a/file',
      'https://b/another',
    ]);
  });

  test('queueUrisToAria2 ignores empty / whitespace-only entries', () async {
    final t = _FakeTransport();
    final client = Aria2Client(transport: t);
    final r = await queueUrisToAria2(client, ['', '   ', 'https://a/x']);
    expect(r.added, 1);
    expect(r.skipped, 2);
    expect(t.addUriCalls, [
      ['https://a/x'],
    ]);
  });

  test('queueUrisToAria2 拒绝无 scheme/不支持的 URI（计入 skipped）', () async {
    final t = _FakeTransport();
    final client = Aria2Client(transport: t);
    // 5 个垃圾 + 1 个有效 + 1 个无 btih 的 magnet（也不合法）。
    final r = await queueUrisToAria2(client, [
      'not-a-url',
      'javascript:alert(1)',
      'about:blank',
      '127.0.0.1', // 缺 scheme
      'data:text/plain,abc',
      'magnet:?xt=urn:tree:tiger:something', // 无 btih
      'https://a/ok',
    ]);
    expect(r.added, 1);
    expect(r.skipped, 6);
    expect(t.addUriCalls, [
      ['https://a/ok'],
    ]);
  });

  test('queueUrisToAria2 部分 addUri 失败时收集到 errors 不中断', () async {
    // 第二条 addUri 抛错；第一、三条正常入队。
    var seq = 0;
    final t = _FakeTransport(
      addUriHandler: (uri) async {
        seq++;
        if (seq == 2) {
          throw const Aria2RpcException('temp blip', code: -1);
        }
        return 'gid$seq';
      },
    );
    final client = Aria2Client(transport: t);
    final r = await queueUrisToAria2(client, [
      'https://a/one',
      'https://b/two',
      'https://c/three',
    ]);
    expect(r.added, 2);
    expect(r.skipped, 0);
    expect(r.errors.length, 1);
    expect(r.errors.first.uri, 'https://b/two');
    expect(r.errors.first.error, isA<Aria2RpcException>());
    // 第二条失败不影响第三条调用——之前实现 await throw 会中断 for 循环。
    expect(t.addUriCalls.map((c) => c.single).toList(), [
      'https://a/one',
      'https://b/two',
      'https://c/three',
    ]);
  });
}
