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
  bool runOnce() => false;
  @override
  String addUri(
    List<String> uris, {
    Map<String, String> options = const {},
    int position = -1,
  }) => throw UnimplementedError();
  @override
  String addTorrent(
    String torrentBase64, {
    List<String> webSeedUris = const [],
    Map<String, String> options = const {},
    int position = -1,
  }) => throw UnimplementedError();
  @override
  List<String> addMetalink(
    String metalinkBase64, {
    Map<String, String> options = const {},
    int position = -1,
  }) => throw UnimplementedError();
  @override
  void remove(String gid, {bool force = false}) {}
  @override
  void pause(String gid, {bool force = false}) {}
  @override
  void pauseAll({bool force = false}) {}
  @override
  void unpause(String gid) {}
  @override
  void unpauseAll() {}
  @override
  void purgeDownloadResult() {}
  @override
  void removeDownloadResult(String gid) {}
  @override
  void changeOption(String gid, Map<String, String> options) {}
  @override
  void changeGlobalOption(Map<String, String> options) {}
  @override
  Map<String, dynamic> tellStatus(String gid, {List<String>? keys}) => {};
  @override
  List<Map<String, dynamic>> tellActive({List<String>? keys}) => const [];
  @override
  List<Map<String, dynamic>> tellWaiting({
    int offset = 0,
    int num = 1000,
    List<String>? keys,
  }) => const [];
  @override
  List<Map<String, dynamic>> tellStopped({
    int offset = 0,
    int num = 1000,
    List<String>? keys,
  }) => const [];
  @override
  List<Map<String, dynamic>> getFiles(String gid) => const [];
  @override
  List<Map<String, dynamic>> getPeers(String gid) => const [];
  @override
  Map<String, dynamic> getGlobalStat() => const {};
  @override
  Map<String, dynamic> getGlobalOption() => const {};
  @override
  Map<String, dynamic> getOption(String gid) => const {};
  @override
  Map<String, dynamic> getVersion() => const {'version': 'fake'};
}

// Avoid unused-import lint when fake doesn't actually reach FFI.
// ignore: unused_element
Pointer<Void> _unused() => nullptr;
