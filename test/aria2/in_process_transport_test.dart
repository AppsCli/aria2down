// 不加载真实 libaria2，而是通过假 Aria2NativeSession 注入桩函数，验证
// Aria2InProcessTransport 把 JSON-RPC 方法名+参数正确翻译为 libaria2 API 调用。
//
// 这是不依赖原生库的合约测试，CI 上随 flutter test 一起跑。
import 'dart:ffi';

import 'package:aria2_native/aria2_native.dart';
import 'package:aria2down/aria2/client/aria2_exceptions.dart';
import 'package:aria2down/aria2/client/in_process_transport.dart';
import 'package:aria2down/aria2/client/rpc_methods.dart';
import 'package:flutter_test/flutter_test.dart';

/// 极简 Fake：直接构造一个不会触发任何 FFI 调用的 [Aria2NativeSession]
/// 的真实例不可行（构造函数私有），因此我们检测 `Aria2InProcessTransport`
/// 在缺少 session 时仍然能优雅处理。这里覆盖参数解析与方法分发的关键路径。
void main() {
  test('未知方法返回 RpcException（-32601）', () async {
    final t = Aria2InProcessTransport(_FakeSession());
    await expectLater(
      t.call('aria2.unknown', const []),
      throwsA(
        predicate(
          (e) =>
              e is Aria2RpcException &&
              e.code == -32601 &&
              e.message.contains('不支持'),
        ),
      ),
    );
  });

  test('shutdown 即便 session 未关联也成功（让 daemon.stop 走自身清理）', () async {
    final t = Aria2InProcessTransport(_FakeSession());
    final r1 = await t.call(RpcMethods.shutdown, const []);
    final r2 = await t.call(RpcMethods.forceShutdown, const []);
    expect(r1, 'OK');
    expect(r2, 'OK');
  });

  test('参数类型错误抛 RpcException（-32602）', () async {
    final t = Aria2InProcessTransport(_FakeSession());
    await expectLater(
      t.call(RpcMethods.addUri, const [123]),
      throwsA(predicate((e) => e is Aria2RpcException && e.code == -32602)),
    );
  });

  test('pauseAll 优先调用 native session.pauseAll（支持时）', () async {
    final fake = _RecordingSession(
      nativePauseAllSupported: true,
      active: [
        {'gid': 'a1', 'status': 'active'},
      ],
    );
    final t = Aria2InProcessTransport(fake);
    final r = await t.call(RpcMethods.pauseAll, const []);
    expect(r, 'OK');
    // native 路径走通，不应再逐条 pause。
    expect(fake.nativePauseAllCalls, 1);
    expect(fake.nativePauseAllForce, [false]);
    expect(fake.pauseCalls, isEmpty);
  });

  test('forcePauseAll 走 native 时把 force=true 透传', () async {
    final fake = _RecordingSession(nativePauseAllSupported: true);
    final t = Aria2InProcessTransport(fake);
    final r = await t.call(RpcMethods.forcePauseAll, const []);
    expect(r, 'OK');
    expect(fake.nativePauseAllCalls, 1);
    expect(fake.nativePauseAllForce, [true]);
  });

  test('pauseAll 在 native 不支持时回退枚举 active + waiting 逐条 pause', () async {
    final fake = _RecordingSession(
      nativePauseAllSupported: false,
      active: [
        {'gid': 'a1', 'status': 'active'},
      ],
      waiting: [
        {'gid': 'w1', 'status': 'waiting'},
        {'gid': 'w2', 'status': 'paused'},
      ],
    );
    final t = Aria2InProcessTransport(fake);
    final r = await t.call(RpcMethods.pauseAll, const []);
    expect(r, 'OK');
    // 旧版 prebuilt 兼容：枚举两个列表后逐条 pause。
    expect(fake.pauseCalls, ['a1', 'w1', 'w2']);
    expect(fake.pauseForceFlags, [false, false, false]);
  });

  test('unpauseAll 优先调用 native session.unpauseAll（支持时）', () async {
    final fake = _RecordingSession(nativePauseAllSupported: true);
    final t = Aria2InProcessTransport(fake);
    final r = await t.call(RpcMethods.unpauseAll, const []);
    expect(r, 'OK');
    expect(fake.nativeUnpauseAllCalls, 1);
    expect(fake.unpauseCalls, isEmpty);
  });

  test('unpauseAll 在 native 不支持时只对 paused 调 unpause，不动 waiting', () async {
    final fake = _RecordingSession(
      nativePauseAllSupported: false,
      waiting: [
        {'gid': 'p1', 'status': 'paused'},
        {'gid': 'w1', 'status': 'waiting'},
        {'gid': 'p2', 'status': 'paused'},
      ],
    );
    final t = Aria2InProcessTransport(fake);
    final r = await t.call(RpcMethods.unpauseAll, const []);
    expect(r, 'OK');
    expect(fake.unpauseCalls, ['p1', 'p2']);
  });
}

/// 仅满足类型，不能被实际调用（一旦 transport 真去访问 session 方法会抛
/// NoSuchMethodError 或访问空指针 → 测试用例避免触发那条路径）。
class _FakeSession implements Aria2NativeSession {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #handle) return 0;
    if (invocation.memberName == #isAlive) return false;
    return super.noSuchMethod(invocation);
  }

  // 显式重写测试用例真正会经过的成员，避免 noSuchMethod 路径。
  @override
  Aria2NativeBindings get bindings => throw UnimplementedError();
  @override
  int get handle => 0;
  @override
  bool get isAlive => false;
  @override
  Stream<Aria2NativeEvent> get events => const Stream<Aria2NativeEvent>.empty();
  @override
  Future<void> close({bool force = false}) async {}
  @override
  Future<bool> runOnce() async => false;
  @override
  Future<String> addUri(
    List<String> uris, {
    Map<String, String> options = const {},
    int position = -1,
  }) => throw UnimplementedError();
  @override
  Future<String> addTorrent(
    String torrentBase64, {
    List<String> webSeedUris = const [],
    Map<String, String> options = const {},
    int position = -1,
  }) => throw UnimplementedError();
  @override
  Future<List<String>> addMetalink(
    String metalinkBase64, {
    Map<String, String> options = const {},
    int position = -1,
  }) => throw UnimplementedError();
  @override
  Future<void> remove(String gid, {bool force = false}) async {}
  @override
  Future<void> pause(String gid, {bool force = false}) async {}
  @override
  Future<void> pauseAll({bool force = false}) async {}
  @override
  Future<void> unpause(String gid) async {}
  @override
  Future<void> unpauseAll() async {}
  @override
  Future<void> purgeDownloadResult() async {}
  @override
  Future<void> removeDownloadResult(String gid) async {}
  @override
  Future<void> changeOption(String gid, Map<String, String> options) async {}
  @override
  Future<void> changeGlobalOption(Map<String, String> options) async {}
  @override
  Future<Map<String, dynamic>> tellStatus(
    String gid, {
    List<String>? keys,
  }) async => const {};
  @override
  Future<List<Map<String, dynamic>>> tellActive({List<String>? keys}) async =>
      const [];
  @override
  Future<List<Map<String, dynamic>>> tellWaiting({
    int offset = 0,
    int num = 1000,
    List<String>? keys,
  }) async => const [];
  @override
  Future<List<Map<String, dynamic>>> tellStopped({
    int offset = 0,
    int num = 1000,
    List<String>? keys,
  }) async => const [];
  @override
  Future<List<Map<String, dynamic>>> getFiles(String gid) async => const [];
  @override
  Future<List<Map<String, dynamic>>> getPeers(String gid) async => const [];
  @override
  Future<Map<String, dynamic>> getGlobalStat() async => const {};
  @override
  Future<Map<String, dynamic>> getGlobalOption() async => const {};
  @override
  Future<Map<String, dynamic>> getOption(String gid) async => const {};
  @override
  Future<Map<String, dynamic>> getVersion() async => const {'version': 'fake'};
}

/// 录像 fake：可配置 `nativePauseAllSupported`——为 true 时 `pauseAll`/
/// `unpauseAll` 成功并被计数；为 false 时抛 `Aria2NativeCallException`，
/// 模拟旧 prebuilt 缺少 `aria2_ffi_pause_all` / `aria2_ffi_unpause_all` 时
/// 的 fallback 行为。同时记录所有逐条 pause/unpause 调用顺序。
class _RecordingSession extends _FakeSession {
  _RecordingSession({
    this.nativePauseAllSupported = true,
    this.active = const [],
    this.waiting = const [],
  });

  final bool nativePauseAllSupported;
  final List<Map<String, dynamic>> active;
  final List<Map<String, dynamic>> waiting;
  final pauseCalls = <String>[];
  final pauseForceFlags = <bool>[];
  final unpauseCalls = <String>[];
  int nativePauseAllCalls = 0;
  int nativeUnpauseAllCalls = 0;
  final nativePauseAllForce = <bool>[];

  @override
  Future<List<Map<String, dynamic>>> tellActive({List<String>? keys}) async =>
      active;

  @override
  Future<List<Map<String, dynamic>>> tellWaiting({
    int offset = 0,
    int num = 1000,
    List<String>? keys,
  }) async => waiting;

  @override
  Future<void> pause(String gid, {bool force = false}) async {
    pauseCalls.add(gid);
    pauseForceFlags.add(force);
  }

  @override
  Future<void> pauseAll({bool force = false}) async {
    if (!nativePauseAllSupported) {
      throw const Aria2NativeCallException(
        'aria2_ffi_pause_all not supported in this build',
        code: -1004,
      );
    }
    nativePauseAllCalls++;
    nativePauseAllForce.add(force);
  }

  @override
  Future<void> unpause(String gid) async {
    unpauseCalls.add(gid);
  }

  @override
  Future<void> unpauseAll() async {
    if (!nativePauseAllSupported) {
      throw const Aria2NativeCallException(
        'aria2_ffi_unpause_all not supported in this build',
        code: -1004,
      );
    }
    nativeUnpauseAllCalls++;
  }
}

// Avoid unused-import lint when fake doesn't actually reach FFI.
// ignore: unused_element
Pointer<Void> _unused() => nullptr;
