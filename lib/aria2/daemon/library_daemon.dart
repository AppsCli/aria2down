import 'dart:async';
import 'dart:io';

import 'package:aria2_native/aria2_native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/app_settings.dart';
import '../client/aria2_client.dart';
import '../client/aria2_exceptions.dart';
import '../client/in_process_transport.dart';
import '../client/logging_transport.dart';
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
///
/// 标注为 `base class` 而非 `final`：禁止外部 implements（避免 misuse 错过
/// 内部状态字段），但允许测试中 extends 写一个轻量 fake（仅覆盖 capabilities
/// 等用于 provider 路径的 getter）。
base class LibraryDaemon implements Aria2Daemon {
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
  // 库引擎一次启动后不会内部重建 client/WS，所以这个 ValueNotifier 永远停在
  // 0；保留对外接口对齐 Aria2Daemon 即可（UI 不会因此重绑订阅）。
  final ValueNotifier<int> _connectionGeneration = ValueNotifier<int>(0);
  // 启动时一次性查询：旧 prebuilt 缺哪些能力。UI 据此向用户提示「请重编
  // libaria2」。
  Set<String> _capabilities = const <String>{};

  /// 本构建实际启用的可选 capability 列表（参见 [Aria2NativeSession.getCapabilities]）。
  ///
  /// 空集合 = 用的是未打补丁的旧 prebuilt，「删除已完成 / 列等待任务 / BT 顶层
  /// 字段」会走 Dart 侧软兜底而非真实 native 路径。
  Set<String> get capabilities => _capabilities;

  static Future<LibraryDaemon> create({required AppSettings settings}) async {
    final base = await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'aria2down'));
    await root.create(recursive: true);

    Directory? downloadOverride;
    final rawDir = settings.downloadDirectoryOverride?.trim();
    if (rawDir != null && rawDir.isNotEmpty) {
      final d = Directory(rawDir);
      // 库引擎也尊重用户配置：目录不存在时尝试创建，避免静默回退到默认 Downloads。
      if (!await d.exists()) {
        try {
          await d.create(recursive: true);
        } catch (_) {
          /* 创建失败时回退到默认 */
        }
      }
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

  /// 清理 ADR-010 之前子进程模式残留的 `rpc.secret`（升级到内嵌库后该文件
  /// 不再被任何代码写入，留在 stateRoot 里会让早期的 CLI 工具误以为本机有
  /// 一个监听 RPC 端口的 aria2c）。本身是幂等操作，下次启动若发现则一次
  /// 删除完毕。
  Future<void> _purgeStaleSecretFile() async {
    try {
      final f = File(p.join(_stateRoot.path, 'rpc.secret'));
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      /* ignore */
    }
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
  ValueListenable<int> get connectionGeneration => _connectionGeneration;

  @override
  Future<void> start() async {
    if (_state == DaemonState.ready) return;
    _state = DaemonState.starting;

    // 兼容老安装：把 ADR-010 之前 LocalDaemon 写下的 rpc.secret 清掉，
    // 避免任何依赖该文件的旧 CLI / Native Messaging 流程误连下线的端口。
    await _purgeStaleSecretFile();

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
    _client = Aria2Client(
      transport: Aria2LoggingTransport(
        Aria2InProcessTransport(_session!),
        label: 'library',
      ),
    );

    _state = DaemonState.ready;

    // 能力集查询走异步路径，**不阻塞** daemon ready：之前实现把
    // `await getCapabilities()` 放在 _client 创建之前，一旦 worker 因任
    // 何原因（例如 native 初始化慢）多花几秒，UI 就会感知到 daemon 启动
    // 拖延、任务详情页 tellStatus 排在队列后面看似"加载失败"。capability
    // 仅影响 UI 提示（降级 banner），不影响任何 RPC 路径正确性——丢失或
    // 延迟拉到都是软降级，所以可以 fire-and-forget。
    unawaited(_loadCapabilitiesAsync());
  }

  Future<void> _loadCapabilitiesAsync() async {
    // 5s 超时双保险：默认 worker.send 已有 60s timeout，但 capabilities 是
    // 启动期诊断信息，多等几十秒毫无价值；超时就当零能力。
    try {
      _capabilities = await _session!.getCapabilities().timeout(
        const Duration(seconds: 5),
      );
    } catch (e, st) {
      // ignore: avoid_print
      print('[library_daemon] getCapabilities failed (soft-degraded): $e');
      // ignore: avoid_print
      print('$st');
      _capabilities = const <String>{};
    }
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
