import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'bindings.dart';
import 'exceptions.dart';

/// High-level wrapper around the singleton libaria2 session.
///
/// Owns the [Aria2NativeBindings] instance plus the active session handle and
/// the [NativeCallable.listener] used to bridge download events.
///
/// Not marked `final` so that integration tests can supply lightweight fakes
/// (`implements Aria2NativeSession`) without standing up the real native
/// library.
class Aria2NativeSession {
  Aria2NativeSession._(this._bindings, this._handle, this._eventBridge);

  final Aria2NativeBindings _bindings;
  int _handle;
  _EventBridge? _eventBridge;

  Aria2NativeBindings get bindings => _bindings;

  int get handle => _handle;

  /// `0` means the session has been closed.
  bool get isAlive => _handle != 0;

  /// Stream of download events translated to aria2 JSON-RPC notification
  /// method names: `aria2.onDownloadStart`, `aria2.onDownloadPause`,
  /// `aria2.onDownloadStop`, `aria2.onDownloadComplete`,
  /// `aria2.onDownloadError`, `aria2.onBtDownloadComplete`.
  Stream<Aria2NativeEvent> get events => _eventBridge!.stream;

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

  /// Open a fresh session. Set [options] to seed aria2 with command-line-style
  /// options (e.g. `dir`, `max-concurrent-downloads`).
  static Future<Aria2NativeSession> open({
    required Aria2NativeBindings bindings,
    Map<String, String> options = const {},
  }) async {
    if (!isAvailable(bindings)) {
      throw const Aria2NativeUnavailableException();
    }
    final initRv = bindings.aria2_ffi_library_init();
    if (initRv != Aria2FfiResult.ok &&
        initRv != Aria2FfiResult.alreadyInitialized) {
      throw Aria2NativeCallException('aria2_ffi_library_init 失败', code: initRv);
    }

    final optsJson = options.isEmpty
        ? ''
        : jsonEncode(options.map((k, v) => MapEntry(k, v)));
    final optsPtr = optsJson.isEmpty ? nullptr : optsJson.toNativeUtf8();
    final handlePtr = calloc<Int64>();
    try {
      final rv = bindings.aria2_ffi_session_new(
          optsPtr.cast<Utf8>(), handlePtr);
      if (rv != Aria2FfiResult.ok) {
        throw Aria2NativeCallException('aria2_ffi_session_new 失败', code: rv);
      }
      final handle = handlePtr.value;
      final session = Aria2NativeSession._(bindings, handle, null);
      session._eventBridge = _EventBridge(bindings, handle);
      session._eventBridge!.attach();
      return session;
    } finally {
      calloc.free(handlePtr);
      if (optsPtr != nullptr) calloc.free(optsPtr);
    }
  }

  /// Schedule a graceful (or forced) shutdown and tear down the session.
  Future<void> close({bool force = false}) async {
    if (!isAlive) return;
    _eventBridge?.dispose();
    _eventBridge = null;
    _bindings.aria2_ffi_shutdown(_handle, force ? 1 : 0);
    // Drain remaining events until run_once reports completion.
    for (var i = 0; i < 50; i++) {
      final rv = _bindings.aria2_ffi_run_once(_handle);
      if (rv <= 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final rv = _bindings.aria2_ffi_session_final(_handle);
    _handle = 0;
    _bindings.aria2_ffi_library_deinit();
    if (rv < 0 && rv != Aria2FfiResult.notInitialized) {
      // Surface libaria2's exit code via logs; not fatal.
      // ignore: avoid_print
      print('[aria2_native] sessionFinal returned $rv');
    }
  }

  /// Drives the event loop once. Returns true if downloads are still in
  /// progress, false when idle, and throws on error.
  bool runOnce() {
    _ensureAlive();
    final rv = _bindings.aria2_ffi_run_once(_handle);
    if (rv < 0) {
      throw Aria2NativeCallException('aria2_ffi_run_once 失败', code: rv);
    }
    return rv == 1;
  }

  // ----- Download CRUD ----------------------------------------------------

  String addUri(List<String> uris,
      {Map<String, String> options = const {}, int position = -1}) {
    _ensureAlive();
    final urisJson = jsonEncode(uris);
    final optsJson = options.isEmpty ? '' : jsonEncode(options);
    return _withStrings([urisJson, optsJson], (ptrs) {
      final out = calloc<Pointer<Utf8>>();
      try {
        final rv = _bindings.aria2_ffi_add_uri(
            _handle, ptrs[0], ptrs[1], position, out);
        if (rv != Aria2FfiResult.ok) {
          throw Aria2NativeCallException('aria2_ffi_add_uri 失败', code: rv);
        }
        return _takeStringPtr(out.value);
      } finally {
        calloc.free(out);
      }
    });
  }

  String addTorrent(String torrentBase64,
      {List<String> webSeedUris = const [],
      Map<String, String> options = const {},
      int position = -1}) {
    _ensureAlive();
    final urisJson = jsonEncode(webSeedUris);
    final optsJson = options.isEmpty ? '' : jsonEncode(options);
    return _withStrings([torrentBase64, urisJson, optsJson], (ptrs) {
      final out = calloc<Pointer<Utf8>>();
      try {
        final rv = _bindings.aria2_ffi_add_torrent(
            _handle, ptrs[0], ptrs[1], ptrs[2], position, out);
        if (rv != Aria2FfiResult.ok) {
          throw Aria2NativeCallException('aria2_ffi_add_torrent 失败', code: rv);
        }
        return _takeStringPtr(out.value);
      } finally {
        calloc.free(out);
      }
    });
  }

  List<String> addMetalink(String metalinkBase64,
      {Map<String, String> options = const {}, int position = -1}) {
    _ensureAlive();
    final optsJson = options.isEmpty ? '' : jsonEncode(options);
    return _withStrings([metalinkBase64, optsJson], (ptrs) {
      final out = calloc<Pointer<Utf8>>();
      try {
        final rv = _bindings.aria2_ffi_add_metalink(
            _handle, ptrs[0], ptrs[1], position, out);
        if (rv != Aria2FfiResult.ok) {
          throw Aria2NativeCallException('aria2_ffi_add_metalink 失败', code: rv);
        }
        final raw = _takeStringPtr(out.value);
        final list = jsonDecode(raw);
        if (list is! List) return const <String>[];
        return list.map((e) => e.toString()).toList();
      } finally {
        calloc.free(out);
      }
    });
  }

  void remove(String gid, {bool force = false}) {
    _ensureAlive();
    _withStrings([gid], (ptrs) {
      final rv = _bindings.aria2_ffi_remove(_handle, ptrs[0], force ? 1 : 0);
      if (rv != Aria2FfiResult.ok) {
        throw Aria2NativeCallException('aria2_ffi_remove 失败', code: rv);
      }
    });
  }

  void pause(String gid, {bool force = false}) {
    _ensureAlive();
    _withStrings([gid], (ptrs) {
      final rv = _bindings.aria2_ffi_pause(_handle, ptrs[0], force ? 1 : 0);
      if (rv != Aria2FfiResult.ok) {
        throw Aria2NativeCallException('aria2_ffi_pause 失败', code: rv);
      }
    });
  }

  void pauseAll({bool force = false}) {
    _ensureAlive();
    final rv = _bindings.aria2_ffi_pause_all(_handle, force ? 1 : 0);
    if (rv != Aria2FfiResult.ok) {
      throw Aria2NativeCallException('aria2_ffi_pause_all 失败', code: rv);
    }
  }

  void unpause(String gid) {
    _ensureAlive();
    _withStrings([gid], (ptrs) {
      final rv = _bindings.aria2_ffi_unpause(_handle, ptrs[0]);
      if (rv != Aria2FfiResult.ok) {
        throw Aria2NativeCallException('aria2_ffi_unpause 失败', code: rv);
      }
    });
  }

  void unpauseAll() {
    _ensureAlive();
    final rv = _bindings.aria2_ffi_unpause_all(_handle);
    if (rv != Aria2FfiResult.ok) {
      throw Aria2NativeCallException('aria2_ffi_unpause_all 失败', code: rv);
    }
  }

  void purgeDownloadResult() {
    _ensureAlive();
    final rv = _bindings.aria2_ffi_purge_download_result(_handle);
    if (rv != Aria2FfiResult.ok) {
      throw Aria2NativeCallException('aria2_ffi_purge_download_result 失败',
          code: rv);
    }
  }

  void removeDownloadResult(String gid) {
    _ensureAlive();
    _withStrings([gid], (ptrs) {
      final rv = _bindings.aria2_ffi_remove_download_result(_handle, ptrs[0]);
      if (rv != Aria2FfiResult.ok) {
        throw Aria2NativeCallException('aria2_ffi_remove_download_result 失败',
            code: rv);
      }
    });
  }

  void changeOption(String gid, Map<String, String> options) {
    _ensureAlive();
    final optsJson = jsonEncode(options);
    _withStrings([gid, optsJson], (ptrs) {
      final rv = _bindings.aria2_ffi_change_option(_handle, ptrs[0], ptrs[1]);
      if (rv != Aria2FfiResult.ok) {
        throw Aria2NativeCallException('aria2_ffi_change_option 失败', code: rv);
      }
    });
  }

  void changeGlobalOption(Map<String, String> options) {
    _ensureAlive();
    final optsJson = jsonEncode(options);
    _withStrings([optsJson], (ptrs) {
      final rv = _bindings.aria2_ffi_change_global_option(_handle, ptrs[0]);
      if (rv != Aria2FfiResult.ok) {
        throw Aria2NativeCallException('aria2_ffi_change_global_option 失败',
            code: rv);
      }
    });
  }

  // ----- Queries ----------------------------------------------------------

  Map<String, dynamic> tellStatus(String gid, {List<String>? keys}) {
    final keysJson = keys == null ? '' : jsonEncode(keys);
    return _readJsonObject('aria2_ffi_tell_status', (out) {
      return _withStrings([gid, keysJson], (ptrs) =>
          _bindings.aria2_ffi_tell_status(_handle, ptrs[0], ptrs[1], out));
    });
  }

  List<Map<String, dynamic>> tellActive({List<String>? keys}) {
    final keysJson = keys == null ? '' : jsonEncode(keys);
    return _readJsonArray('aria2_ffi_tell_active', (out) {
      return _withStrings([keysJson], (ptrs) =>
          _bindings.aria2_ffi_tell_active(_handle, ptrs[0], out));
    });
  }

  List<Map<String, dynamic>> tellWaiting(
      {int offset = 0, int num = 1000, List<String>? keys}) {
    final keysJson = keys == null ? '' : jsonEncode(keys);
    return _readJsonArray('aria2_ffi_tell_waiting', (out) {
      return _withStrings([keysJson], (ptrs) => _bindings
          .aria2_ffi_tell_waiting(_handle, offset, num, ptrs[0], out));
    });
  }

  List<Map<String, dynamic>> tellStopped(
      {int offset = 0, int num = 1000, List<String>? keys}) {
    final keysJson = keys == null ? '' : jsonEncode(keys);
    return _readJsonArray('aria2_ffi_tell_stopped', (out) {
      return _withStrings([keysJson], (ptrs) => _bindings
          .aria2_ffi_tell_stopped(_handle, offset, num, ptrs[0], out));
    });
  }

  List<Map<String, dynamic>> getFiles(String gid) {
    return _readJsonArray('aria2_ffi_get_files', (out) {
      return _withStrings([gid], (ptrs) =>
          _bindings.aria2_ffi_get_files(_handle, ptrs[0], out));
    });
  }

  List<Map<String, dynamic>> getPeers(String gid) {
    return _readJsonArray('aria2_ffi_get_peers', (out) {
      return _withStrings([gid], (ptrs) =>
          _bindings.aria2_ffi_get_peers(_handle, ptrs[0], out));
    });
  }

  Map<String, dynamic> getGlobalStat() {
    return _readJsonObject('aria2_ffi_get_global_stat',
        (out) => _bindings.aria2_ffi_get_global_stat(_handle, out));
  }

  Map<String, dynamic> getGlobalOption() {
    return _readJsonObject('aria2_ffi_get_global_option',
        (out) => _bindings.aria2_ffi_get_global_option(_handle, out));
  }

  Map<String, dynamic> getOption(String gid) {
    return _readJsonObject('aria2_ffi_get_option', (out) {
      return _withStrings([gid], (ptrs) =>
          _bindings.aria2_ffi_get_option(_handle, ptrs[0], out));
    });
  }

  Map<String, dynamic> getVersion() {
    return _readJsonObject('aria2_ffi_get_version',
        (out) => _bindings.aria2_ffi_get_version(_handle, out));
  }

  // ----- Helpers ----------------------------------------------------------

  void _ensureAlive() {
    if (!isAlive) {
      throw const Aria2NativeCallException('aria2_native session 已关闭',
          code: -1006);
    }
  }

  T _withStrings<T>(List<String> values, T Function(List<Pointer<Utf8>>) body) {
    final ptrs = <Pointer<Utf8>>[];
    for (final v in values) {
      ptrs.add(v.isEmpty ? nullptr : v.toNativeUtf8());
    }
    try {
      return body(ptrs);
    } finally {
      for (final p in ptrs) {
        if (p != nullptr) calloc.free(p);
      }
    }
  }

  Map<String, dynamic> _readJsonObject(
      String name, int Function(Pointer<Pointer<Utf8>>) call) {
    final out = calloc<Pointer<Utf8>>();
    try {
      final rv = call(out);
      if (rv != Aria2FfiResult.ok) {
        throw Aria2NativeCallException('$name 失败', code: rv);
      }
      final raw = _takeStringPtr(out.value);
      if (raw.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{};
    } finally {
      calloc.free(out);
    }
  }

  List<Map<String, dynamic>> _readJsonArray(
      String name, int Function(Pointer<Pointer<Utf8>>) call) {
    final out = calloc<Pointer<Utf8>>();
    try {
      final rv = call(out);
      if (rv != Aria2FfiResult.ok) {
        throw Aria2NativeCallException('$name 失败', code: rv);
      }
      final raw = _takeStringPtr(out.value);
      if (raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((e) =>
              e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map))
          .toList();
    } finally {
      calloc.free(out);
    }
  }

  String _takeStringPtr(Pointer<Utf8> p) {
    if (p == nullptr) return '';
    try {
      return p.toDartString();
    } finally {
      _bindings.aria2_ffi_free_string(p);
    }
  }
}

/// Bridges native event callbacks to a Dart broadcast stream.
final class _EventBridge {
  _EventBridge(this._bindings, this._handle);

  final Aria2NativeBindings _bindings;
  final int _handle;
  final _controller = StreamController<Aria2NativeEvent>.broadcast();
  NativeCallable<EventCbNative>? _callable;

  Stream<Aria2NativeEvent> get stream => _controller.stream;

  void attach() {
    _callable = NativeCallable<EventCbNative>.listener(_onEvent);
    final rv = _bindings.aria2_ffi_set_event_callback(
        _handle, _callable!.nativeFunction, nullptr);
    if (rv != Aria2FfiResult.ok) {
      _callable!.close();
      _callable = null;
    }
  }

  void _onEvent(int event, int gid, Pointer<Void> userData) {
    final ev = Aria2NativeEvent._fromCodes(event, gid);
    if (ev != null && !_controller.isClosed) {
      _controller.add(ev);
    }
  }

  Future<void> dispose() async {
    _callable?.close();
    _callable = null;
    if (!_controller.isClosed) await _controller.close();
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
    return Aria2NativeEvent(
      type: type,
      gidHex: gid.toRadixString(16).padLeft(16, '0'),
    );
  }

  final Aria2NativeEventType type;
  final String gidHex;
}
