// Worker isolate that owns the libaria2 session and drives its event loop.
//
// Why an isolate? `aria2_ffi_run_once` synchronously calls
// `DownloadEngine::poll()` which blocks up to ~1 second waiting for socket
// events. If we ran that on the main Dart isolate (where Flutter renders the
// UI), the UI thread would freeze in bursts of several hundred milliseconds.
// Moving every FFI call into a dedicated worker isolate keeps the UI isolate
// responsive while still preserving libaria2's single-threaded API contract:
// all calls into libaria2 are serialized through this one worker, so the
// engine never sees concurrent access.
//
// Communication shape:
//   main → worker: [requestId, opcode, args...]
//   worker → main reply port: [requestId, ok?, payload | error]
//   worker → main event port: [eventCode, gid]
//
// `Aria2NativeSession` exposes async wrappers around these messages.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'bindings.dart';
import 'exceptions.dart';

/// Opcodes exchanged with the worker isolate.
///
/// Kept as small ints (rather than enums) so they cross the isolate boundary
/// as the lightest possible message.
abstract final class WorkerOp {
  static const init = 0;
  static const close = 1;
  static const runOnce = 2;
  static const shutdown = 3;

  static const addUri = 10;
  static const addTorrent = 11;
  static const addMetalink = 12;
  static const remove = 13;
  static const pause = 14;
  static const pauseAll = 15;
  static const unpause = 16;
  static const unpauseAll = 17;
  static const purgeDownloadResult = 18;
  static const removeDownloadResult = 19;
  static const changeOption = 20;
  static const changeGlobalOption = 21;

  static const tellStatus = 30;
  static const tellActive = 31;
  static const tellWaiting = 32;
  static const tellStopped = 33;
  static const getFiles = 34;
  static const getPeers = 35;
  static const getGlobalStat = 36;
  static const getGlobalOption = 37;
  static const getOption = 38;
  static const getVersion = 39;
}

/// Payload sent to `Isolate.spawn` to bootstrap the worker.
class _SpawnPayload {
  const _SpawnPayload({
    required this.bootstrapPort,
    required this.eventPort,
    required this.options,
  });

  final SendPort bootstrapPort;
  final SendPort eventPort;
  final Map<String, String> options;
}

/// Main-isolate facade over the worker. One instance corresponds to one
/// libaria2 session.
class Aria2NativeWorker {
  Aria2NativeWorker._(
    this._isolate,
    this._requestPort,
    this._replies,
    this._eventStream,
    this._replyReceive,
    this._eventReceive,
    this._eventController,
  );

  final Isolate _isolate;
  final SendPort _requestPort;
  final _ReplyDemuxer _replies;
  final Stream<List<int>> _eventStream;
  final ReceivePort _replyReceive;
  final ReceivePort _eventReceive;
  final StreamController<List<int>> _eventController;
  var _closed = false;

  Stream<List<int>> get events => _eventStream;

  bool get isAlive => !_closed;

  static Future<Aria2NativeWorker> spawn({
    required Map<String, String> options,
  }) async {
    final bootstrap = ReceivePort();
    final events = ReceivePort();
    final isolate = await Isolate.spawn<_SpawnPayload>(
      _entry,
      _SpawnPayload(
        bootstrapPort: bootstrap.sendPort,
        eventPort: events.sendPort,
        options: options,
      ),
      debugName: 'aria2_native_worker',
    );

    // First message from the worker is either the request SendPort (on
    // success) or a `[error, message, code?]` triple if libaria2 failed to
    // initialise.
    final bootstrapIter = StreamIterator(bootstrap);
    if (!await bootstrapIter.moveNext()) {
      isolate.kill(priority: Isolate.immediate);
      events.close();
      throw const Aria2NativeUnavailableException();
    }
    final first = bootstrapIter.current;
    await bootstrapIter.cancel();
    bootstrap.close();
    if (first is List && first.isNotEmpty && first[0] == 'error') {
      isolate.kill(priority: Isolate.immediate);
      events.close();
      final msg = first.length > 1 ? '${first[1]}' : 'aria2 worker init 失败';
      final code = first.length > 2 && first[2] is int ? first[2] as int : -1;
      if (code == -1001) {
        throw const Aria2NativeUnavailableException();
      }
      throw Aria2NativeCallException(msg, code: code);
    }
    if (first is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      events.close();
      throw const Aria2NativeCallException(
        'aria2 worker 返回的握手消息异常',
        code: -1005,
      );
    }
    final requestPort = first;
    final replies = _ReplyDemuxer();
    // Replies arrive on a separate port so that the bootstrap port can be
    // closed once handshake completes.
    final replyReceive = ReceivePort();
    replyReceive.listen((msg) => replies.dispatch(msg));
    // Tell the worker which port to send replies on. The worker has already
    // queued user messages behind this one because Dart preserves send order.
    requestPort.send(['_setReplyPort', replyReceive.sendPort]);

    // Convert the raw event ReceivePort into a broadcast Stream<List<int>>
    // so multiple listeners can attach (e.g. event bridge + diagnostics).
    final eventController = StreamController<List<int>>.broadcast();
    events.listen((msg) {
      if (msg is List) {
        eventController.add(msg.cast<int>());
      }
    });

    return Aria2NativeWorker._(
      isolate,
      requestPort,
      replies,
      eventController.stream,
      replyReceive,
      events,
      eventController,
    );
  }

  /// Send an opcode + JSON args, get back the JSON payload (already decoded).
  Future<Object?> send(int op, [List<Object?> args = const []]) {
    if (_closed) {
      throw const Aria2NativeCallException('aria2 worker 已关闭', code: -1006);
    }
    return _sendUnchecked(op, args);
  }

  Future<Object?> _sendUnchecked(int op, List<Object?> args) {
    final id = _replies.next();
    final completer = _replies.expect(id);
    _requestPort.send([id, op, ...args]);
    return completer.future;
  }

  /// Stop the worker. Should always be awaited so libaria2 cleans up.
  Future<void> close({bool force = false}) async {
    if (_closed) return;
    try {
      await _sendUnchecked(WorkerOp.close, [
        force ? 1 : 0,
      ]).timeout(const Duration(seconds: 30), onTimeout: () => null);
    } catch (_) {
      // Ignore — we are tearing down.
    }
    _closed = true;
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _replies.dispose();
    _replyReceive.close();
    _eventReceive.close();
    if (!_eventController.isClosed) {
      await _eventController.close();
    }
  }
}

class _ReplyDemuxer {
  final _completers = <int, Completer<Object?>>{};
  var _next = 1;
  var _disposed = false;

  int next() => _next++;

  Completer<Object?> expect(int id) {
    final c = Completer<Object?>();
    _completers[id] = c;
    return c;
  }

  void dispatch(Object? msg) {
    if (msg is! List || msg.length < 2) return;
    final id = msg[0];
    if (id is! int) return;
    final completer = _completers.remove(id);
    if (completer == null || completer.isCompleted) return;
    final ok = msg[1];
    if (ok == true) {
      completer.complete(msg.length > 2 ? msg[2] : null);
    } else {
      final errMsg = msg.length > 2 ? '${msg[2]}' : 'aria2 worker 调用失败';
      final code = msg.length > 3 && msg[3] is int ? msg[3] as int : -1005;
      completer.completeError(Aria2NativeCallException(errMsg, code: code));
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final c in _completers.values) {
      if (!c.isCompleted) {
        c.completeError(
          const Aria2NativeCallException('aria2 worker 已关闭，请求被丢弃', code: -1006),
        );
      }
    }
    _completers.clear();
  }
}

// ---------------------------------------------------------------------------
// Worker isolate body
// ---------------------------------------------------------------------------

void _entry(_SpawnPayload payload) {
  final binding = Aria2NativeBindings(openAria2NativeLibrary());

  if (binding.aria2_ffi_is_available() == 0) {
    payload.bootstrapPort.send(['error', 'libaria2 未链接到本构建', -1001]);
    return;
  }

  final initRv = binding.aria2_ffi_library_init();
  if (initRv != 0 && initRv != -1003 /* ALREADY_INITIALIZED */ ) {
    payload.bootstrapPort.send(['error', 'aria2_ffi_library_init 失败', initRv]);
    return;
  }

  final optsJson = payload.options.isEmpty ? '' : jsonEncode(payload.options);
  final optsPtr = optsJson.isEmpty ? nullptr : optsJson.toNativeUtf8();
  final handlePtr = calloc<Int64>();
  int handle;
  try {
    final rv = binding.aria2_ffi_session_new(optsPtr.cast<Utf8>(), handlePtr);
    if (rv != 0) {
      payload.bootstrapPort.send(['error', 'aria2_ffi_session_new 失败', rv]);
      return;
    }
    handle = handlePtr.value;
  } finally {
    calloc.free(handlePtr);
    if (optsPtr != nullptr) calloc.free(optsPtr);
  }

  // NativeCallable.listener delivers on this isolate. We just forward to the
  // event port so the main isolate sees the event.
  final callable = NativeCallable<EventCbNative>.listener((
    int event,
    int gid,
    Pointer<Void> userData,
  ) {
    payload.eventPort.send([event, gid]);
  });
  binding.aria2_ffi_set_event_callback(
    handle,
    callable.nativeFunction,
    nullptr,
  );

  final requestPort = ReceivePort();
  // Hand the request port back so the main isolate can send messages.
  // The reply port arrives later via a `_setReplyPort` message.
  payload.bootstrapPort.send(requestPort.sendPort);

  // ---- Run-loop scheduling ------------------------------------------------
  //
  // Self-adaptive cadence: when libaria2 reports active downloads we tick at
  // ~80ms (fast enough for smooth speed updates without dominating the CPU);
  // when idle, fall back to 800ms. After a mutating RPC we kick a quick tick
  // so addUri/pause/etc are reflected immediately.
  const activeInterval = Duration(milliseconds: 80);
  const idleInterval = Duration(milliseconds: 800);
  Timer? runTimer;
  var running = true;

  void scheduleRunOnce(Duration delay) {
    runTimer?.cancel();
    if (!running) return;
    runTimer = Timer(delay, () {
      if (!running) return;
      var next = idleInterval;
      try {
        final rv = binding.aria2_ffi_run_once(handle);
        next = rv == 1 ? activeInterval : idleInterval;
      } catch (_) {
        // Single-tick errors are non-fatal; back off to idle cadence.
      }
      scheduleRunOnce(next);
    });
  }

  // Bring the loop online immediately so DNS / setup work starts ticking.
  scheduleRunOnce(const Duration(milliseconds: 1));

  SendPort? replyPort;

  void reply(int id, bool ok, [Object? payload, int? code]) {
    if (replyPort == null) return;
    if (ok) {
      replyPort!.send([id, true, payload]);
    } else {
      replyPort!.send([id, false, payload, code ?? -1005]);
    }
  }

  void kick() {
    // Schedule next runOnce ASAP without dropping the current outstanding
    // timer if it's already very near.
    scheduleRunOnce(const Duration(milliseconds: 5));
  }

  requestPort.listen((msg) {
    if (msg is List && msg.isNotEmpty && msg[0] == '_setReplyPort') {
      replyPort = msg[1] as SendPort;
      return;
    }
    if (msg is! List || msg.length < 2) return;
    final id = msg[0] as int;
    final op = msg[1] as int;
    try {
      switch (op) {
        case WorkerOp.close:
          final force = msg.length > 2 && msg[2] == 1;
          running = false;
          runTimer?.cancel();
          runTimer = null;
          try {
            binding.aria2_ffi_shutdown(handle, force ? 1 : 0);
          } catch (_) {}
          for (var i = 0; i < 50; i++) {
            final rv = binding.aria2_ffi_run_once(handle);
            if (rv <= 0) break;
          }
          try {
            binding.aria2_ffi_session_final(handle);
          } catch (_) {}
          callable.close();
          reply(id, true, null);
          binding.aria2_ffi_library_deinit();
          requestPort.close();
          return;

        case WorkerOp.runOnce:
          final rv = binding.aria2_ffi_run_once(handle);
          if (rv < 0) {
            reply(id, false, 'aria2_ffi_run_once', rv);
          } else {
            reply(id, true, rv == 1);
          }
          return;

        case WorkerOp.shutdown:
          final force = msg.length > 2 && msg[2] == 1;
          final rv = binding.aria2_ffi_shutdown(handle, force ? 1 : 0);
          if (rv != 0) {
            reply(id, false, 'aria2_ffi_shutdown', rv);
          } else {
            reply(id, true, null);
          }
          return;

        case WorkerOp.addUri:
          final urisJson = msg[2] as String;
          final optsJson = msg[3] as String;
          final position = msg[4] as int;
          _withUtf8Strings([urisJson, optsJson], (ptrs) {
            final out = calloc<Pointer<Utf8>>();
            try {
              final rv = binding.aria2_ffi_add_uri(
                handle,
                ptrs[0],
                ptrs[1],
                position,
                out,
              );
              if (rv != 0) {
                reply(id, false, 'aria2_ffi_add_uri', rv);
              } else {
                reply(id, true, _takeStringPtr(binding, out.value));
              }
            } finally {
              calloc.free(out);
            }
          });
          kick();
          return;

        case WorkerOp.addTorrent:
          final torrent = msg[2] as String;
          final urisJson = msg[3] as String;
          final optsJson = msg[4] as String;
          final position = msg[5] as int;
          _withUtf8Strings([torrent, urisJson, optsJson], (ptrs) {
            final out = calloc<Pointer<Utf8>>();
            try {
              final rv = binding.aria2_ffi_add_torrent(
                handle,
                ptrs[0],
                ptrs[1],
                ptrs[2],
                position,
                out,
              );
              if (rv != 0) {
                reply(id, false, 'aria2_ffi_add_torrent', rv);
              } else {
                reply(id, true, _takeStringPtr(binding, out.value));
              }
            } finally {
              calloc.free(out);
            }
          });
          kick();
          return;

        case WorkerOp.addMetalink:
          final metalink = msg[2] as String;
          final optsJson = msg[3] as String;
          final position = msg[4] as int;
          _withUtf8Strings([metalink, optsJson], (ptrs) {
            final out = calloc<Pointer<Utf8>>();
            try {
              final rv = binding.aria2_ffi_add_metalink(
                handle,
                ptrs[0],
                ptrs[1],
                position,
                out,
              );
              if (rv != 0) {
                reply(id, false, 'aria2_ffi_add_metalink', rv);
              } else {
                reply(id, true, _takeStringPtr(binding, out.value));
              }
            } finally {
              calloc.free(out);
            }
          });
          kick();
          return;

        case WorkerOp.remove:
          final gid = msg[2] as String;
          final force = msg[3] as int;
          _withUtf8Strings([gid], (ptrs) {
            final rv = binding.aria2_ffi_remove(handle, ptrs[0], force);
            if (rv != 0) {
              reply(id, false, 'aria2_ffi_remove', rv);
            } else {
              reply(id, true, null);
            }
          });
          kick();
          return;

        case WorkerOp.pause:
          final gid = msg[2] as String;
          final force = msg[3] as int;
          _withUtf8Strings([gid], (ptrs) {
            final rv = binding.aria2_ffi_pause(handle, ptrs[0], force);
            if (rv != 0) {
              reply(id, false, 'aria2_ffi_pause', rv);
            } else {
              reply(id, true, null);
            }
          });
          kick();
          return;

        case WorkerOp.pauseAll:
          final force = msg[2] as int;
          final rv = binding.aria2_ffi_pause_all(handle, force);
          if (rv != 0) {
            reply(id, false, 'aria2_ffi_pause_all', rv);
          } else {
            reply(id, true, null);
          }
          kick();
          return;

        case WorkerOp.unpause:
          final gid = msg[2] as String;
          _withUtf8Strings([gid], (ptrs) {
            final rv = binding.aria2_ffi_unpause(handle, ptrs[0]);
            if (rv != 0) {
              reply(id, false, 'aria2_ffi_unpause', rv);
            } else {
              reply(id, true, null);
            }
          });
          kick();
          return;

        case WorkerOp.unpauseAll:
          final rv = binding.aria2_ffi_unpause_all(handle);
          if (rv != 0) {
            reply(id, false, 'aria2_ffi_unpause_all', rv);
          } else {
            reply(id, true, null);
          }
          kick();
          return;

        case WorkerOp.purgeDownloadResult:
          final rv = binding.aria2_ffi_purge_download_result(handle);
          if (rv != 0) {
            reply(id, false, 'aria2_ffi_purge_download_result', rv);
          } else {
            reply(id, true, null);
          }
          kick();
          return;

        case WorkerOp.removeDownloadResult:
          final gid = msg[2] as String;
          _withUtf8Strings([gid], (ptrs) {
            final rv = binding.aria2_ffi_remove_download_result(
              handle,
              ptrs[0],
            );
            if (rv != 0) {
              reply(id, false, 'aria2_ffi_remove_download_result', rv);
            } else {
              reply(id, true, null);
            }
          });
          kick();
          return;

        case WorkerOp.changeOption:
          final gid = msg[2] as String;
          final optsJson = msg[3] as String;
          _withUtf8Strings([gid, optsJson], (ptrs) {
            final rv = binding.aria2_ffi_change_option(
              handle,
              ptrs[0],
              ptrs[1],
            );
            if (rv != 0) {
              reply(id, false, 'aria2_ffi_change_option', rv);
            } else {
              reply(id, true, null);
            }
          });
          kick();
          return;

        case WorkerOp.changeGlobalOption:
          final optsJson = msg[2] as String;
          _withUtf8Strings([optsJson], (ptrs) {
            final rv = binding.aria2_ffi_change_global_option(handle, ptrs[0]);
            if (rv != 0) {
              reply(id, false, 'aria2_ffi_change_global_option', rv);
            } else {
              reply(id, true, null);
            }
          });
          kick();
          return;

        case WorkerOp.tellStatus:
          final gid = msg[2] as String;
          final keysJson = msg[3] as String;
          _withUtf8Strings([gid, keysJson], (ptrs) {
            final out = calloc<Pointer<Utf8>>();
            try {
              final rv = binding.aria2_ffi_tell_status(
                handle,
                ptrs[0],
                ptrs[1],
                out,
              );
              if (rv != 0) {
                reply(id, false, 'aria2_ffi_tell_status', rv);
              } else {
                reply(id, true, _takeStringPtr(binding, out.value));
              }
            } finally {
              calloc.free(out);
            }
          });
          return;

        case WorkerOp.tellActive:
          final keysJson = msg[2] as String;
          _withUtf8Strings([keysJson], (ptrs) {
            final out = calloc<Pointer<Utf8>>();
            try {
              final rv = binding.aria2_ffi_tell_active(handle, ptrs[0], out);
              if (rv != 0) {
                reply(id, false, 'aria2_ffi_tell_active', rv);
              } else {
                reply(id, true, _takeStringPtr(binding, out.value));
              }
            } finally {
              calloc.free(out);
            }
          });
          return;

        case WorkerOp.tellWaiting:
          final offset = msg[2] as int;
          final num = msg[3] as int;
          final keysJson = msg[4] as String;
          _withUtf8Strings([keysJson], (ptrs) {
            final out = calloc<Pointer<Utf8>>();
            try {
              final rv = binding.aria2_ffi_tell_waiting(
                handle,
                offset,
                num,
                ptrs[0],
                out,
              );
              if (rv != 0) {
                reply(id, false, 'aria2_ffi_tell_waiting', rv);
              } else {
                reply(id, true, _takeStringPtr(binding, out.value));
              }
            } finally {
              calloc.free(out);
            }
          });
          return;

        case WorkerOp.tellStopped:
          final offset = msg[2] as int;
          final num = msg[3] as int;
          final keysJson = msg[4] as String;
          _withUtf8Strings([keysJson], (ptrs) {
            final out = calloc<Pointer<Utf8>>();
            try {
              final rv = binding.aria2_ffi_tell_stopped(
                handle,
                offset,
                num,
                ptrs[0],
                out,
              );
              if (rv != 0) {
                reply(id, false, 'aria2_ffi_tell_stopped', rv);
              } else {
                reply(id, true, _takeStringPtr(binding, out.value));
              }
            } finally {
              calloc.free(out);
            }
          });
          return;

        case WorkerOp.getFiles:
          final gid = msg[2] as String;
          _withUtf8Strings([gid], (ptrs) {
            final out = calloc<Pointer<Utf8>>();
            try {
              final rv = binding.aria2_ffi_get_files(handle, ptrs[0], out);
              if (rv != 0) {
                reply(id, false, 'aria2_ffi_get_files', rv);
              } else {
                reply(id, true, _takeStringPtr(binding, out.value));
              }
            } finally {
              calloc.free(out);
            }
          });
          return;

        case WorkerOp.getPeers:
          final gid = msg[2] as String;
          _withUtf8Strings([gid], (ptrs) {
            final out = calloc<Pointer<Utf8>>();
            try {
              final rv = binding.aria2_ffi_get_peers(handle, ptrs[0], out);
              if (rv != 0) {
                reply(id, false, 'aria2_ffi_get_peers', rv);
              } else {
                reply(id, true, _takeStringPtr(binding, out.value));
              }
            } finally {
              calloc.free(out);
            }
          });
          return;

        case WorkerOp.getGlobalStat:
          final out = calloc<Pointer<Utf8>>();
          try {
            final rv = binding.aria2_ffi_get_global_stat(handle, out);
            if (rv != 0) {
              reply(id, false, 'aria2_ffi_get_global_stat', rv);
            } else {
              reply(id, true, _takeStringPtr(binding, out.value));
            }
          } finally {
            calloc.free(out);
          }
          return;

        case WorkerOp.getGlobalOption:
          final out = calloc<Pointer<Utf8>>();
          try {
            final rv = binding.aria2_ffi_get_global_option(handle, out);
            if (rv != 0) {
              reply(id, false, 'aria2_ffi_get_global_option', rv);
            } else {
              reply(id, true, _takeStringPtr(binding, out.value));
            }
          } finally {
            calloc.free(out);
          }
          return;

        case WorkerOp.getOption:
          final gid = msg[2] as String;
          _withUtf8Strings([gid], (ptrs) {
            final out = calloc<Pointer<Utf8>>();
            try {
              final rv = binding.aria2_ffi_get_option(handle, ptrs[0], out);
              if (rv != 0) {
                reply(id, false, 'aria2_ffi_get_option', rv);
              } else {
                reply(id, true, _takeStringPtr(binding, out.value));
              }
            } finally {
              calloc.free(out);
            }
          });
          return;

        case WorkerOp.getVersion:
          final out = calloc<Pointer<Utf8>>();
          try {
            final rv = binding.aria2_ffi_get_version(handle, out);
            if (rv != 0) {
              reply(id, false, 'aria2_ffi_get_version', rv);
            } else {
              reply(id, true, _takeStringPtr(binding, out.value));
            }
          } finally {
            calloc.free(out);
          }
          return;
      }
    } catch (e) {
      reply(id, false, '$e', -1005);
    }
  });
}

void _withUtf8Strings(
  List<String> values,
  void Function(List<Pointer<Utf8>>) body,
) {
  final ptrs = <Pointer<Utf8>>[];
  for (final v in values) {
    ptrs.add(v.isEmpty ? nullptr : v.toNativeUtf8());
  }
  try {
    body(ptrs);
  } finally {
    for (final p in ptrs) {
      if (p != nullptr) calloc.free(p);
    }
  }
}

String _takeStringPtr(Aria2NativeBindings binding, Pointer<Utf8> p) {
  if (p == nullptr) return '';
  try {
    return p.toDartString();
  } finally {
    binding.aria2_ffi_free_string(p);
  }
}
