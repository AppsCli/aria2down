import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'bindings.dart';
import 'exceptions.dart';
import 'worker.dart';

/// High-level wrapper around a libaria2 session that runs in a dedicated
/// worker isolate.
///
/// Every entry point is now `Future`-returning even when the underlying FFI
/// call is cheap. The cost is a single inter-isolate hop (~tens of µs); the
/// benefit is that the main / UI isolate is never blocked by libaria2's
/// `DownloadEngine::poll()` which can stall for up to one second waiting for
/// socket I/O.
///
/// Not marked `final` so integration tests can supply lightweight fakes
/// (`implements Aria2NativeSession`) without standing up the real worker.
class Aria2NativeSession {
  Aria2NativeSession._(this._bindings, this._worker, this._events);

  final Aria2NativeBindings _bindings;
  final Aria2NativeWorker? _worker;
  final StreamController<Aria2NativeEvent> _events;
  var _closed = false;

  Aria2NativeBindings get bindings => _bindings;

  /// The numeric handle is kept for diagnostic / logging callers.
  int get handle => _worker == null ? 0 : 1;

  /// `false` once [close] returns.
  bool get isAlive => _worker?.isAlive == true && !_closed;

  /// Stream of download events translated to aria2 JSON-RPC notification
  /// method names: `aria2.onDownloadStart`, `aria2.onDownloadPause`,
  /// `aria2.onDownloadStop`, `aria2.onDownloadComplete`,
  /// `aria2.onDownloadError`, `aria2.onBtDownloadComplete`.
  Stream<Aria2NativeEvent> get events => _events.stream;

  /// Returns `true` when the underlying build actually links libaria2 (vs.
  /// stub-only). Cheap to call.
  static bool isAvailable(Aria2NativeBindings b) =>
      b.aria2_ffi_is_available() != 0;

  /// Reads `libaria2` version string. Empty when running on a stub build.
  static String libraryVersion(Aria2NativeBindings b) {
    final p = b.aria2_ffi_library_version();
    if (p == nullptr) return '';
    try {
      return p.toDartString();
    } finally {
      b.aria2_ffi_free_string(p);
    }
  }

  /// 查询本构建的可选能力集合（去重的字符串集合）。
  ///
  /// 旧 `prebuilt/libaria2.a` + 旧 `aria2_ffi.cc` 编译产物会缺 `aria2_ffi_get_capabilities`
  /// 符号——此时 [`Aria2NativeBindings.aria2_ffi_get_capabilities`] 返回 null，本方法
  /// 同样返回空集合。调用方据此向用户暗示"功能受限，建议 `./scripts/build_libaria2_*.sh`
  /// 重编 prebuilt"。
  ///
  /// 可能出现的元素：
  /// - `"removeDownloadResult"`：能真正清掉 stopped 任务（否则只能软成功）。
  /// - `"listReserved"`、`"listDownloadResults"`：能正确枚举 waiting / stopped。
  /// - `"downloadHandleExt"`：BT 任务详情可见 errorMessage / numSeeders 等顶层字段。
  Future<Set<String>> getCapabilities() async {
    _ensureAlive();
    final raw = await _worker!.send(WorkerOp.getCapabilities);
    if (raw is! String || raw.isEmpty) return const {};
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const {};
    return decoded.map((e) => '$e').where((s) => s.isNotEmpty).toSet();
  }

  /// Open a fresh session in a dedicated worker isolate. Set [options] to
  /// seed aria2 with command-line-style options (e.g. `dir`,
  /// `max-concurrent-downloads`).
  static Future<Aria2NativeSession> open({
    required Aria2NativeBindings bindings,
    Map<String, String> options = const {},
  }) async {
    if (!isAvailable(bindings)) {
      throw const Aria2NativeUnavailableException();
    }
    final worker = await Aria2NativeWorker.spawn(options: options);
    final events = StreamController<Aria2NativeEvent>.broadcast();
    worker.events.listen((raw) {
      if (raw.length < 2) return;
      final ev = Aria2NativeEvent._fromCodes(raw[0], raw[1]);
      if (ev != null && !events.isClosed) events.add(ev);
    });
    return Aria2NativeSession._(bindings, worker, events);
  }

  /// Schedule a graceful (or forced) shutdown and tear down the session.
  Future<void> close({bool force = false}) async {
    if (_closed) return;
    _closed = true;
    final w = _worker;
    if (w != null) {
      await w.close(force: force);
    }
    if (!_events.isClosed) await _events.close();
  }

  /// Drives the event loop once manually. The worker already does this on
  /// its own cadence; the method is kept for API compatibility but is rarely
  /// needed.
  Future<bool> runOnce() async {
    _ensureAlive();
    final rv = await _worker!.send(WorkerOp.runOnce);
    return rv == true;
  }

  // ----- Download CRUD ----------------------------------------------------

  Future<String> addUri(
    List<String> uris, {
    Map<String, String> options = const {},
    int position = -1,
  }) async {
    _ensureAlive();
    final urisJson = jsonEncode(uris);
    final optsJson = options.isEmpty ? '' : jsonEncode(options);
    final r = await _worker!.send(WorkerOp.addUri, [
      urisJson,
      optsJson,
      position,
    ]);
    return r as String;
  }

  Future<String> addTorrent(
    String torrentBase64, {
    List<String> webSeedUris = const [],
    Map<String, String> options = const {},
    int position = -1,
  }) async {
    _ensureAlive();
    final urisJson = jsonEncode(webSeedUris);
    final optsJson = options.isEmpty ? '' : jsonEncode(options);
    final r = await _worker!.send(WorkerOp.addTorrent, [
      torrentBase64,
      urisJson,
      optsJson,
      position,
    ]);
    return r as String;
  }

  Future<List<String>> addMetalink(
    String metalinkBase64, {
    Map<String, String> options = const {},
    int position = -1,
  }) async {
    _ensureAlive();
    final optsJson = options.isEmpty ? '' : jsonEncode(options);
    final raw = await _worker!.send(WorkerOp.addMetalink, [
      metalinkBase64,
      optsJson,
      position,
    ]);
    final decoded = jsonDecode(raw as String);
    if (decoded is! List) return const <String>[];
    return decoded.map((e) => e.toString()).toList();
  }

  Future<void> remove(String gid, {bool force = false}) async {
    _ensureAlive();
    await _worker!.send(WorkerOp.remove, [gid, force ? 1 : 0]);
  }

  Future<void> pause(String gid, {bool force = false}) async {
    _ensureAlive();
    await _worker!.send(WorkerOp.pause, [gid, force ? 1 : 0]);
  }

  Future<void> pauseAll({bool force = false}) async {
    _ensureAlive();
    await _worker!.send(WorkerOp.pauseAll, [force ? 1 : 0]);
  }

  Future<void> unpause(String gid) async {
    _ensureAlive();
    await _worker!.send(WorkerOp.unpause, [gid]);
  }

  Future<void> unpauseAll() async {
    _ensureAlive();
    await _worker!.send(WorkerOp.unpauseAll);
  }

  Future<void> purgeDownloadResult() async {
    _ensureAlive();
    await _worker!.send(WorkerOp.purgeDownloadResult);
  }

  Future<void> removeDownloadResult(String gid) async {
    _ensureAlive();
    await _worker!.send(WorkerOp.removeDownloadResult, [gid]);
  }

  Future<void> changeOption(String gid, Map<String, String> options) async {
    _ensureAlive();
    final optsJson = jsonEncode(options);
    await _worker!.send(WorkerOp.changeOption, [gid, optsJson]);
  }

  Future<void> changeGlobalOption(Map<String, String> options) async {
    _ensureAlive();
    final optsJson = jsonEncode(options);
    await _worker!.send(WorkerOp.changeGlobalOption, [optsJson]);
  }

  // ----- Queries ----------------------------------------------------------

  Future<Map<String, dynamic>> tellStatus(
    String gid, {
    List<String>? keys,
  }) async {
    _ensureAlive();
    final keysJson = keys == null ? '' : jsonEncode(keys);
    final raw = await _worker!.send(WorkerOp.tellStatus, [gid, keysJson]);
    return _decodeObject(raw as String);
  }

  Future<List<Map<String, dynamic>>> tellActive({List<String>? keys}) async {
    _ensureAlive();
    final keysJson = keys == null ? '' : jsonEncode(keys);
    final raw = await _worker!.send(WorkerOp.tellActive, [keysJson]);
    return _decodeArray(raw as String);
  }

  Future<List<Map<String, dynamic>>> tellWaiting({
    int offset = 0,
    int num = 1000,
    List<String>? keys,
  }) async {
    _ensureAlive();
    final keysJson = keys == null ? '' : jsonEncode(keys);
    final raw = await _worker!.send(WorkerOp.tellWaiting, [
      offset,
      num,
      keysJson,
    ]);
    return _decodeArray(raw as String);
  }

  Future<List<Map<String, dynamic>>> tellStopped({
    int offset = 0,
    int num = 1000,
    List<String>? keys,
  }) async {
    _ensureAlive();
    final keysJson = keys == null ? '' : jsonEncode(keys);
    final raw = await _worker!.send(WorkerOp.tellStopped, [
      offset,
      num,
      keysJson,
    ]);
    return _decodeArray(raw as String);
  }

  Future<List<Map<String, dynamic>>> getFiles(String gid) async {
    _ensureAlive();
    final raw = await _worker!.send(WorkerOp.getFiles, [gid]);
    return _decodeArray(raw as String);
  }

  Future<List<Map<String, dynamic>>> getPeers(String gid) async {
    _ensureAlive();
    final raw = await _worker!.send(WorkerOp.getPeers, [gid]);
    return _decodeArray(raw as String);
  }

  Future<Map<String, dynamic>> getGlobalStat() async {
    _ensureAlive();
    final raw = await _worker!.send(WorkerOp.getGlobalStat);
    return _decodeObject(raw as String);
  }

  Future<Map<String, dynamic>> getGlobalOption() async {
    _ensureAlive();
    final raw = await _worker!.send(WorkerOp.getGlobalOption);
    return _decodeObject(raw as String);
  }

  Future<Map<String, dynamic>> getOption(String gid) async {
    _ensureAlive();
    final raw = await _worker!.send(WorkerOp.getOption, [gid]);
    return _decodeObject(raw as String);
  }

  Future<Map<String, dynamic>> getVersion() async {
    _ensureAlive();
    final raw = await _worker!.send(WorkerOp.getVersion);
    return _decodeObject(raw as String);
  }

  // ----- Helpers ----------------------------------------------------------

  void _ensureAlive() {
    if (!isAlive) {
      throw const Aria2NativeCallException(
        'aria2_native session 已关闭',
        code: -1006,
      );
    }
  }

  Map<String, dynamic> _decodeObject(String raw) {
    if (raw.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _decodeArray(String raw) {
    if (raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .map(
          (e) => e is Map<String, dynamic>
              ? e
              : Map<String, dynamic>.from(e as Map),
        )
        .toList();
  }
}

/// Mirrors `aria2::DownloadEvent` from the libaria2 header.
enum Aria2NativeEventType {
  start(1, 'aria2.onDownloadStart'),
  pause(2, 'aria2.onDownloadPause'),
  stop(3, 'aria2.onDownloadStop'),
  complete(4, 'aria2.onDownloadComplete'),
  error(5, 'aria2.onDownloadError'),
  btComplete(6, 'aria2.onBtDownloadComplete');

  const Aria2NativeEventType(this.code, this.rpcMethod);
  final int code;
  final String rpcMethod;
}

final class Aria2NativeEvent {
  const Aria2NativeEvent({required this.type, required this.gidHex});

  static Aria2NativeEvent? _fromCodes(int eventCode, int gid) {
    Aria2NativeEventType? type;
    for (final e in Aria2NativeEventType.values) {
      if (e.code == eventCode) {
        type = e;
        break;
      }
    }
    if (type == null) return null;
    return Aria2NativeEvent(type: type, gidHex: formatGidAsUnsignedHex16(gid));
  }

  final Aria2NativeEventType type;
  final String gidHex;
}

/// 按 `aria2::gidToHex` 的语义把 64 位 GID 序列化为 16 位小写无符号十六进制。
///
/// libaria2 的 `A2Gid` 是 `uint64_t`，但 Dart `int` 是 64 位有符号整数：高位
/// 为 1 的 GID 会以负数形式抵达 Dart（例如 `0xDE32415CA11488F0` 在
/// SendPort 传递后变成 `-2436189094428901648`）。若直接 `toRadixString(16)`
/// 会得到 `-21cdbea35eeb7710` 这种带负号的串，喂回 `aria2_ffi_tell_status`
/// 后 `hexToGid` 解析失败、`getDownloadHandle` 找不到对应任务，整条链路报
/// `ARIA2_FFI_ERR_NOT_FOUND (-1006)`。
///
/// 这里用无符号右移 + 低 32 位掩码拆成两段无符号 32 位整数再拼回 16 位 hex，
/// 与 aria2 在 RPC 中给客户端的 gid 形态完全一致，确保所有依赖事件 gid 的
/// 调用（任务历史落库、详情页轮询、UI 通知聚合）都能稳定回查到任务。
String formatGidAsUnsignedHex16(int gid) {
  final hi = (gid >>> 32) & 0xFFFFFFFF;
  final lo = gid & 0xFFFFFFFF;
  return '${hi.toRadixString(16).padLeft(8, '0')}'
      '${lo.toRadixString(16).padLeft(8, '0')}';
}
