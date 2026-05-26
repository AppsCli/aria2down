// 验证 Aria2LoggingTransport：成功路径静默，失败路径把方法名/错误码/异常
// 信息推到 debugPrint，并 rethrow 原异常以保留控制流。
import 'package:aria2down/aria2/client/aria2_exceptions.dart';
import 'package:aria2down/aria2/client/logging_transport.dart';
import 'package:aria2down/aria2/client/rpc_transport.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> logs;
  late DebugPrintCallback originalDebugPrint;

  setUp(() {
    logs = <String>[];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
  });

  test('成功路径不写日志，直接透传结果', () async {
    final t = Aria2LoggingTransport(
      _FakeTransport((m, p) async => {'gid': '1'}),
      label: 'unit',
    );
    final r = await t.call('aria2.addUri', const <dynamic>[
      <String>['https://example.com'],
    ]);
    expect(r, {'gid': '1'});
    expect(logs, isEmpty);
  });

  test('失败时打印方法名/错误码/异常并 rethrow', () async {
    final t = Aria2LoggingTransport(
      _FakeTransport(
        (m, p) async => throw const Aria2RpcException('GID not found', code: 1),
      ),
      label: 'unit',
    );
    await expectLater(
      t.call('aria2.tellStatus', const <dynamic>['deadbeef']),
      throwsA(
        predicate(
          (e) =>
              e is Aria2RpcException &&
              e.code == 1 &&
              e.message.contains('GID'),
        ),
      ),
    );
    expect(
      logs.any(
        (l) =>
            l.contains('[aria2:unit]') &&
            l.contains('aria2.tellStatus') &&
            l.contains('code=1') &&
            l.contains('GID not found'),
      ),
      isTrue,
      reason:
          'expected at least one log line with method+code+message; got: $logs',
    );
  });

  test('非 Aria2 异常也被记录并 rethrow', () async {
    final t = Aria2LoggingTransport(
      _FakeTransport((m, p) async => throw StateError('boom')),
      label: 'unit',
    );
    await expectLater(
      t.call('aria2.getVersion', const <dynamic>[]),
      throwsA(isA<StateError>()),
    );
    expect(
      logs.any((l) => l.contains('aria2.getVersion') && l.contains('boom')),
      isTrue,
    );
  });

  test('超长 params 被替换为长度占位（不把整段字符串拷进日志）', () async {
    final huge = 'x' * 5000;
    final t = Aria2LoggingTransport(
      _FakeTransport((m, p) async => throw const Aria2RpcException('oops')),
      label: 'unit',
    );
    await expectLater(
      t.call('aria2.addTorrent', <dynamic>[huge]),
      throwsA(isA<Aria2RpcException>()),
    );
    final line = logs.firstWhere((l) => l.contains('aria2.addTorrent'));
    // 日志整体长度远小于 huge.length——之前实现会先把整段字符串拼到 raw
    // 再 substring(0,160)，新实现直接发现 String 太长就替换成占位符。
    expect(line.length, lessThan(huge.length));
    // 占位符必须包含真实长度，方便排查；不再以「N chars」结尾。
    expect(line, contains('<String len=5000>'));
    // 不能把原始内容（连续 'x'）真的拷过来。
    expect(line, isNot(contains('x' * 200)));
  });

  test('嵌套 List 内的超长字符串也只露出长度占位', () async {
    final huge = 'y' * 4096;
    final t = Aria2LoggingTransport(
      _FakeTransport((m, p) async => throw const Aria2RpcException('oops')),
      label: 'unit',
    );
    await expectLater(
      t.call('aria2.addUri', <dynamic>[
        <String>[huge],
      ]),
      throwsA(isA<Aria2RpcException>()),
    );
    final line = logs.firstWhere((l) => l.contains('aria2.addUri'));
    expect(line, contains('<String len=4096>'));
    expect(line, isNot(contains('y' * 200)));
  });

  test('Map 参数走「keys 计数」占位，不展开内容', () async {
    final t = Aria2LoggingTransport(
      _FakeTransport((m, p) async => throw const Aria2RpcException('oops')),
      label: 'unit',
    );
    await expectLater(
      t.call('aria2.changeGlobalOption', <dynamic>[
        {'dir': '/tmp', 'header': 'Authorization: secret-token-xxxxx'},
      ]),
      throwsA(isA<Aria2RpcException>()),
    );
    final line = logs.firstWhere((l) => l.contains('changeGlobalOption'));
    expect(line, contains('<Map keys=2>'));
    expect(line, isNot(contains('secret-token')));
  });

  test('已知软失败（code=-1006）仅一行简讯，不打栈也不展开 params', () async {
    final t = Aria2LoggingTransport(
      _FakeTransport(
        (m, p) async =>
            throw const Aria2RpcException('aria2_ffi_tell_status', code: -1006),
      ),
      label: 'unit',
    );
    await expectLater(
      t.call('aria2.tellStatus', const <dynamic>[
        '634bcc07bd0668c4',
        <String>['gid', 'status', 'totalLength'],
      ]),
      throwsA(predicate((e) => e is Aria2RpcException && e.code == -1006)),
    );
    // 软失败简讯：一行带 method+code+message+soft failure 标记。
    final softLine = logs.singleWhere(
      (l) =>
          l.contains('aria2.tellStatus') &&
          l.contains('code=-1006') &&
          l.contains('soft failure'),
    );
    // 不展开 params（不应再出现 `params=...` 摘要）：避免把整段 keys 数组喷
    // 出来。
    expect(softLine, isNot(contains('params=')));
    // 不应触发 debugPrintStack —— 没有以 `[aria2:unit] aria2.tellStatus` 单
    // 独前缀的额外栈帧行（debugPrintStack 会把 stack frames 单独 print）。
    expect(
      logs.where(
        (l) =>
            l != softLine &&
            l.contains('aria2.tellStatus') &&
            !l.contains('soft failure'),
      ),
      isEmpty,
      reason: 'soft failure must not trigger debugPrintStack; got: $logs',
    );
  });

  test('"No such download" 文本（远程 / 子进程模式）同样降级为单行简讯', () async {
    final t = Aria2LoggingTransport(
      _FakeTransport(
        (m, p) async => throw const Aria2RpcException(
          'No such download for GID#deadbeef',
          code: 1,
        ),
      ),
      label: 'unit',
    );
    await expectLater(
      t.call('aria2.tellStatus', const <dynamic>['deadbeef']),
      throwsA(isA<Aria2RpcException>()),
    );
    final softLine = logs.singleWhere(
      (l) => l.contains('aria2.tellStatus') && l.contains('soft failure'),
    );
    expect(softLine, isNot(contains('params=')));
  });

  test('非软失败仍打完整栈 + params 摘要（避免误降级真正异常）', () async {
    final t = Aria2LoggingTransport(
      _FakeTransport(
        (m, p) async => throw const Aria2RpcException('Unauthorized', code: 1),
      ),
      label: 'unit',
    );
    await expectLater(
      t.call('aria2.getVersion', const <dynamic>[]),
      throwsA(isA<Aria2RpcException>()),
    );
    expect(
      logs.any(
        (l) =>
            l.contains('aria2.getVersion') &&
            l.contains('params=') &&
            !l.contains('soft failure'),
      ),
      isTrue,
      reason: '普通错误必须保留 params 摘要并触发栈打印；got: $logs',
    );
  });
}

class _FakeTransport implements Aria2RpcTransport {
  _FakeTransport(this._handler);

  final Future<Object?> Function(String method, List<dynamic> params) _handler;

  @override
  Future<Object?> call(String method, List<dynamic> params) =>
      _handler(method, params);
}
