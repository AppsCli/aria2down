// ignore_for_file: public_member_api_docs, non_constant_identifier_names
//
// Hand-written FFI bindings for the C ABI declared in src/aria2_ffi.h.
//
// We do not auto-generate these via ffigen on every build to keep the package
// self-contained (no toolchain dependency at pub-get time). Whenever the
// header changes, the file below should be kept in sync. The signatures here
// are stable C ABI — the C++ libaria2 details live behind the shim.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Resolves the shared library exposed by the `aria2_native` Flutter plugin.
///
/// Behaviour mirrors the standard FFI plugin template:
/// - iOS / macOS: symbols are statically linked into the application binary,
///   so we use [DynamicLibrary.process].
/// - Android / Linux: open `libaria2_native.so` via the platform loader.
/// - Windows: `aria2_native.dll` next to the app executable.
///
/// Falls back to a build-time injectable [DynamicLibrary] when the host is
/// not one of the above (e.g. unit tests on a desktop Dart VM where we want
/// to inject a stub).
DynamicLibrary openAria2NativeLibrary({DynamicLibrary? override}) {
  if (override != null) return override;
  if (Platform.isIOS || Platform.isMacOS) {
    return DynamicLibrary.process();
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('libaria2_native.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('aria2_native.dll');
  }
  throw UnsupportedError('aria2_native not supported on this platform.');
}

/// Lazy-resolved low-level bindings. Construct once and reuse.
final class Aria2NativeBindings {
  Aria2NativeBindings(DynamicLibrary dl) : _dl = dl;

  final DynamicLibrary _dl;

  late final aria2_ffi_is_available = _dl
      .lookupFunction<Int32 Function(), int Function()>('aria2_ffi_is_available');

  late final aria2_ffi_library_version = _dl.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('aria2_ffi_library_version');

  late final aria2_ffi_free_string = _dl.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('aria2_ffi_free_string');

  late final aria2_ffi_library_init = _dl
      .lookupFunction<Int32 Function(), int Function()>('aria2_ffi_library_init');

  late final aria2_ffi_library_deinit = _dl
      .lookupFunction<Int32 Function(), int Function()>('aria2_ffi_library_deinit');

  late final aria2_ffi_session_new = _dl.lookupFunction<
      Int32 Function(Pointer<Utf8>, Pointer<Int64>),
      int Function(Pointer<Utf8>, Pointer<Int64>)>('aria2_ffi_session_new');

  late final aria2_ffi_session_final = _dl.lookupFunction<
      Int32 Function(Int64),
      int Function(int)>('aria2_ffi_session_final');

  late final aria2_ffi_run_once = _dl.lookupFunction<
      Int32 Function(Int64),
      int Function(int)>('aria2_ffi_run_once');

  late final aria2_ffi_shutdown = _dl.lookupFunction<
      Int32 Function(Int64, Int32),
      int Function(int, int)>('aria2_ffi_shutdown');

  late final aria2_ffi_set_event_callback = _dl.lookupFunction<
      Int32 Function(Int64, Pointer<NativeFunction<EventCbNative>>, Pointer<Void>),
      int Function(int, Pointer<NativeFunction<EventCbNative>>, Pointer<Void>)>(
      'aria2_ffi_set_event_callback');

  late final aria2_ffi_add_uri = _dl.lookupFunction<
      Int32 Function(
          Int64, Pointer<Utf8>, Pointer<Utf8>, Int32, Pointer<Pointer<Utf8>>),
      int Function(
          int, Pointer<Utf8>, Pointer<Utf8>, int, Pointer<Pointer<Utf8>>)>(
      'aria2_ffi_add_uri');

  late final aria2_ffi_add_torrent = _dl.lookupFunction<
      Int32 Function(Int64, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32,
          Pointer<Pointer<Utf8>>),
      int Function(int, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int,
          Pointer<Pointer<Utf8>>)>('aria2_ffi_add_torrent');

  late final aria2_ffi_add_metalink = _dl.lookupFunction<
      Int32 Function(
          Int64, Pointer<Utf8>, Pointer<Utf8>, Int32, Pointer<Pointer<Utf8>>),
      int Function(
          int, Pointer<Utf8>, Pointer<Utf8>, int, Pointer<Pointer<Utf8>>)>(
      'aria2_ffi_add_metalink');

  late final aria2_ffi_remove = _dl.lookupFunction<
      Int32 Function(Int64, Pointer<Utf8>, Int32),
      int Function(int, Pointer<Utf8>, int)>('aria2_ffi_remove');

  late final aria2_ffi_pause = _dl.lookupFunction<
      Int32 Function(Int64, Pointer<Utf8>, Int32),
      int Function(int, Pointer<Utf8>, int)>('aria2_ffi_pause');

  late final aria2_ffi_pause_all = _dl.lookupFunction<
      Int32 Function(Int64, Int32),
      int Function(int, int)>('aria2_ffi_pause_all');

  late final aria2_ffi_unpause = _dl.lookupFunction<
      Int32 Function(Int64, Pointer<Utf8>),
      int Function(int, Pointer<Utf8>)>('aria2_ffi_unpause');

  late final aria2_ffi_unpause_all = _dl.lookupFunction<
      Int32 Function(Int64),
      int Function(int)>('aria2_ffi_unpause_all');

  late final aria2_ffi_purge_download_result = _dl.lookupFunction<
      Int32 Function(Int64),
      int Function(int)>('aria2_ffi_purge_download_result');

  late final aria2_ffi_remove_download_result = _dl.lookupFunction<
      Int32 Function(Int64, Pointer<Utf8>),
      int Function(int, Pointer<Utf8>)>('aria2_ffi_remove_download_result');

  late final aria2_ffi_change_position = _dl.lookupFunction<
      Int32 Function(Int64, Pointer<Utf8>, Int32, Int32),
      int Function(int, Pointer<Utf8>, int, int)>('aria2_ffi_change_position');

  late final aria2_ffi_change_option = _dl.lookupFunction<
      Int32 Function(Int64, Pointer<Utf8>, Pointer<Utf8>),
      int Function(int, Pointer<Utf8>, Pointer<Utf8>)>('aria2_ffi_change_option');

  late final aria2_ffi_change_global_option = _dl.lookupFunction<
      Int32 Function(Int64, Pointer<Utf8>),
      int Function(int, Pointer<Utf8>)>('aria2_ffi_change_global_option');

  late final aria2_ffi_tell_status = _dl.lookupFunction<
      Int32 Function(
          Int64, Pointer<Utf8>, Pointer<Utf8>, Pointer<Pointer<Utf8>>),
      int Function(
          int, Pointer<Utf8>, Pointer<Utf8>, Pointer<Pointer<Utf8>>)>(
      'aria2_ffi_tell_status');

  late final aria2_ffi_tell_active = _dl.lookupFunction<
      Int32 Function(Int64, Pointer<Utf8>, Pointer<Pointer<Utf8>>),
      int Function(int, Pointer<Utf8>, Pointer<Pointer<Utf8>>)>(
      'aria2_ffi_tell_active');

  late final aria2_ffi_tell_waiting = _dl.lookupFunction<
      Int32 Function(
          Int64, Int32, Int32, Pointer<Utf8>, Pointer<Pointer<Utf8>>),
      int Function(
          int, int, int, Pointer<Utf8>, Pointer<Pointer<Utf8>>)>(
      'aria2_ffi_tell_waiting');

  late final aria2_ffi_tell_stopped = _dl.lookupFunction<
      Int32 Function(
          Int64, Int32, Int32, Pointer<Utf8>, Pointer<Pointer<Utf8>>),
      int Function(
          int, int, int, Pointer<Utf8>, Pointer<Pointer<Utf8>>)>(
      'aria2_ffi_tell_stopped');

  late final aria2_ffi_get_files = _dl.lookupFunction<
      Int32 Function(Int64, Pointer<Utf8>, Pointer<Pointer<Utf8>>),
      int Function(int, Pointer<Utf8>, Pointer<Pointer<Utf8>>)>(
      'aria2_ffi_get_files');

  late final aria2_ffi_get_peers = _dl.lookupFunction<
      Int32 Function(Int64, Pointer<Utf8>, Pointer<Pointer<Utf8>>),
      int Function(int, Pointer<Utf8>, Pointer<Pointer<Utf8>>)>(
      'aria2_ffi_get_peers');

  late final aria2_ffi_get_global_stat = _dl.lookupFunction<
      Int32 Function(Int64, Pointer<Pointer<Utf8>>),
      int Function(int, Pointer<Pointer<Utf8>>)>('aria2_ffi_get_global_stat');

  late final aria2_ffi_get_global_option = _dl.lookupFunction<
      Int32 Function(Int64, Pointer<Pointer<Utf8>>),
      int Function(int, Pointer<Pointer<Utf8>>)>('aria2_ffi_get_global_option');

  late final aria2_ffi_get_option = _dl.lookupFunction<
      Int32 Function(Int64, Pointer<Utf8>, Pointer<Pointer<Utf8>>),
      int Function(int, Pointer<Utf8>, Pointer<Pointer<Utf8>>)>(
      'aria2_ffi_get_option');

  late final aria2_ffi_get_version = _dl.lookupFunction<
      Int32 Function(Int64, Pointer<Pointer<Utf8>>),
      int Function(int, Pointer<Pointer<Utf8>>)>('aria2_ffi_get_version');
}

/// Native signature for the event callback bridge.
typedef EventCbNative = Void Function(Int32, Uint64, Pointer<Void>);

/// Result codes used by the shim.
abstract final class Aria2FfiResult {
  static const ok = 0;
  static const unavailable = -1001;
  static const notInitialized = -1002;
  static const alreadyInitialized = -1003;
  static const invalidArgument = -1004;
  static const internal = -1005;
  static const notFound = -1006;
  static const runtime = -1007;
}
