import 'dart:async';
import 'dart:io';

import 'package:aria2_native/aria2_native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/app_settings.dart';
import '../client/aria2_client.dart';
import '../client/aria2_exceptions.dart';
import '../client/in_process_transport.dart';
import '../client/ws_listener.dart';
import 'aria2_daemon.dart';
import 'daemon_state.dart';

/// 通过 Dart FFI 在进程内运行 libaria2 的 daemon 实现。
///
/// - 没有真实 RPC 端口；`rpcPort=0`、`rpcHttpUri=embedded://aria2/local`。
/// - 事件回调通过 [_LibraryEventBridge] 适配为 [Aria2RpcNotification] 流。
/// - libaria2 的事件循环 (`aria2_ffi_run_once`) 同步阻塞调用方至多 ~1s，
///   因此 [Aria2NativeSession] 内部把所有 FFI 调用搬到独立 worker isolate，
///   主 isolate（UI 线程）不再被任何 libaria2 调用阻塞。
final class LibraryDaemon implements Aria2Daemon {
  LibraryDaemon({
    required Directory stateRoot,
    Directory? downloadDirectory,
    this.maxConcurrentDownloads,
    this.maxConnectionPerServer,
    this.globalDownloadLimit,
    this.globalUploadLimit,
  }) : _stateRoot = stateRoot,
       _downloadDirectory = downloadDirectory;

  final Directory _stateRoot;
  final Directory? _downloadDirectory;
  final int? maxConcurrentDownloads;
  final int? maxConnectionPerServer;
  final String? globalDownloadLimit;
  final String? globalUploadLimit;

  Aria2NativeSession? _session;
  Aria2Client? _client;
  _LibraryEventBridge? _bridge;
  DaemonState _state = DaemonState.stopped;
  String? _logFilePath;

  static Future<LibraryDaemon> create({required AppSettings settings}) async {
    final base = await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'aria2down'));
    await root.create(recursive: true);

    Directory? downloadOverride;
    final rawDir = settings.downloadDirectoryOverride?.trim();
    if (rawDir != null && rawDir.isNotEmpty) {
      final d = Directory(rawDir);
      if (await d.exists()) downloadOverride = d;
    }

    return LibraryDaemon(
      stateRoot: root,
      downloadDirectory: downloadOverride,
      maxConcurrentDownloads: settings.maxConcurrentDownloads,
      maxConnectionPerServer: settings.maxConnectionPerServer,
      globalDownloadLimit: settings.globalDownloadLimit,
      globalUploadLimit: settings.globalUploadLimit,
    );
  }

  DaemonState get state => _state;

  @override
  int get rpcPort => 0;

  @override
  String get rpcSecret => '';

  @override
  Uri get rpcHttpUri => Uri(scheme: 'embedded', host: 'aria2', path: '/local');

  @override
  Uri get rpcWebSocketUri =>
      Uri(scheme: 'embedded', host: 'aria2', path: '/local');

  @override
  String? get logFilePath => _logFilePath;

  @override
  Aria2Client get client {
    final c = _client;
    if (c == null) {
      throw const Aria2DaemonException('aria2 库模式尚未启动');
    }
    return c;
  }

  @override
  Aria2NotificationSource? get wsNotifier => _bridge;

  @override
  Future<void> start() async {
    if (_state == DaemonState.ready) return;
    _state = DaemonState.starting;

    final stateDir = Directory(p.join(_stateRoot.path, 'state'));
    await stateDir.create(recursive: true);
    final sessionFile = File(p.join(stateDir.path, 'aria2.session'));
    if (!await sessionFile.exists()) {
      await sessionFile.create(recursive: false);
    }
    final logFile = File(p.join(stateDir.path, 'aria2.log'));
    _logFilePath = logFile.path;
    final downloadBase =
        _downloadDirectory ??
        await getDownloadsDirectory() ??
        Directory(p.join(_stateRoot.path, 'downloads'));
    await downloadBase.create(recursive: true);

    final options = <String, String>{
      'dir': _posix(downloadBase.path),
      'input-file': _posix(sessionFile.path),
      'save-session': _posix(sessionFile.path),
      'save-session-interval': '30',
      'continue': 'true',
      'min-split-size': '1M',
      'disk-cache': '64M',
      'file-allocation': 'prealloc',
      'seed-time': '0',
      // macOS App Sandbox / iOS 下 c-ares 拿不到系统 DNS 配置（mDNSResponder
      // 走 XPC，c-ares 直接读 /etc/resolv.conf 又只看到回环 stub），结果是
      // `Could not contact DNS servers`。关掉异步 DNS 走 getaddrinfo 即可；
      // 同时给一组兜底服务器，确保即便用户显式打开 async-dns 也能解。
      'async-dns': 'false',
      'async-dns-server': '1.1.1.1,8.8.8.8,223.5.5.5,119.29.29.29',
      'log': _posix(logFile.path),
      'log-level': 'warn',
      'console-log-level': 'warn',
      'enable-rpc': 'false',
      if (maxConnectionPerServer != null)
        'max-connection-per-server': '$maxConnectionPerServer'
      else
        'max-connection-per-server': '16',
      if (maxConcurrentDownloads != null && maxConcurrentDownloads! > 0)
        'max-concurrent-downloads': '$maxConcurrentDownloads',
      if (globalDownloadLimit != null && globalDownloadLimit!.trim().isNotEmpty)
        'max-overall-download-limit': globalDownloadLimit!.trim(),
      if (globalUploadLimit != null && globalUploadLimit!.trim().isNotEmpty)
        'max-overall-upload-limit': globalUploadLimit!.trim(),
    };
    options['split'] = options['max-connection-per-server']!;

    try {
      final bindings = await Aria2NativeLoader.load();
      if (!Aria2NativeSession.isAvailable(bindings)) {
        _state = DaemonState.failed;
        throw const Aria2NativeUnavailableException();
      }
      _session = await Aria2NativeSession.open(
        bindings: bindings,
        options: options,
      );
    } on Aria2NativeException catch (e) {
      _state = DaemonState.failed;
      throw Aria2DaemonException('libaria2 启动失败: ${e.message}');
    }

    _bridge = _LibraryEventBridge(_session!.events);
    _client = Aria2Client(transport: Aria2InProcessTransport(_session!));

    _state = DaemonState.ready;
  }

  @override
  Future<void> stop({bool force = false}) async {
    if (_state == DaemonState.stopped) return;
    _state = DaemonState.stopping;

    await _bridge?.dispose();
    _bridge = null;

    final s = _session;
    _session = null;
    if (s != null) {
      try {
        await s.close(force: force);
      } catch (_) {
        // 已经在停止流程，忽略二次错误。
      }
    }

    _client = null;
    _state = DaemonState.stopped;
  }

  static String _posix(String path) => p.normalize(path).replaceAll('\\', '/');
}

/// 把 [Aria2NativeEvent] 适配为 [Aria2RpcNotification] 流，让现有 UI
/// 代码可零改动消费内嵌引擎事件。
final class _LibraryEventBridge implements Aria2NotificationSource {
  _LibraryEventBridge(this._upstream) {
    _sub = _upstream.listen(
      (ev) {
        final mapped = _map(ev);
        if (mapped != null && !_controller.isClosed) {
          _controller.add(mapped);
        }
      },
      onError: (Object e, StackTrace st) {
        if (!_controller.isClosed) _controller.addError(e, st);
      },
    );
  }

  final Stream<Aria2NativeEvent> _upstream;
  StreamSubscription<Aria2NativeEvent>? _sub;
  final _controller = StreamController<Aria2RpcNotification>.broadcast();

  @override
  Stream<Aria2RpcNotification> get notifications => _controller.stream;

  Aria2RpcNotification? _map(Aria2NativeEvent ev) {
    return Aria2RpcNotification.parse(ev.type.rpcMethod, ev.gidHex);
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    if (!_controller.isClosed) await _controller.close();
  }
}
