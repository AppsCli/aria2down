import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../binary/binary_resolver.dart';
import '../client/aria2_client.dart';
import '../client/aria2_exceptions.dart';
import '../client/http_transport.dart';
import '../client/ws_listener.dart';
import '../config/aria2_config_builder.dart';
import '../../data/app_settings.dart';
import 'aria2_daemon.dart';
import 'daemon_state.dart';

/// 在本机启动 `aria2c` 子进程并暴露 RPC 客户端。
final class LocalDaemon implements Aria2Daemon {
  LocalDaemon({
    required this.binaryPath,
    required Directory stateRoot,
    Directory? downloadDirectory,
    this.maxConcurrentDownloads,
    this.maxConnectionPerServer,
    this.globalDownloadLimit,
    this.globalUploadLimit,
  }) : _stateRoot = stateRoot,
       _downloadDirectory = downloadDirectory;

  final String binaryPath;
  final Directory _stateRoot;
  final Directory? _downloadDirectory;
  final int? maxConcurrentDownloads;
  final int? maxConnectionPerServer;
  final String? globalDownloadLimit;
  final String? globalUploadLimit;

  Process? _process;
  int _port = 0;
  late String _secret;
  String? _confPath;
  Aria2Client? _client;
  Aria2HttpTransport? _transport;
  WsAria2Notifier? _ws;
  DaemonState _state = DaemonState.stopped;
  StreamSubscription<String>? _stderrSub;
  bool _userStopped = false;
  Timer? _restartTimer;
  String? _logFilePath;
  static const _restartDelay = Duration(seconds: 3);

  DaemonState get state => _state;

  @override
  int get rpcPort => _port;

  @override
  String get rpcSecret => _secret;

  @override
  Uri get rpcHttpUri => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: _port,
    path: '/jsonrpc',
  );

  @override
  Uri get rpcWebSocketUri => Uri(
    scheme: 'ws',
    host: InternetAddress.loopbackIPv4.address,
    port: _port,
    path: '/jsonrpc',
  );

  @override
  String? get logFilePath => _logFilePath;

  @override
  Aria2Client get client {
    final c = _client;
    if (c == null) {
      throw const Aria2DaemonException('aria2 尚未启动');
    }
    return c;
  }

  @override
  WsAria2Notifier? get wsNotifier => _ws;

  /// 使用 [AppSettings] 解析二进制路径与下载目录后启动。
  static Future<LocalDaemon> create({required AppSettings settings}) async {
    final resolver = BinaryResolver(overridePath: settings.aria2BinaryPath);
    final path = await resolver.resolve();
    if (path == null) {
      throw const Aria2BinaryNotFoundException();
    }
    final base = await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'aria2down'));
    await root.create(recursive: true);

    Directory? downloadOverride;
    final rawDir = settings.downloadDirectoryOverride?.trim();
    if (rawDir != null && rawDir.isNotEmpty) {
      final d = Directory(rawDir);
      if (await d.exists()) {
        downloadOverride = d;
      }
    }

    return LocalDaemon(
      binaryPath: path,
      stateRoot: root,
      downloadDirectory: downloadOverride,
      maxConcurrentDownloads: settings.maxConcurrentDownloads,
      maxConnectionPerServer: settings.maxConnectionPerServer,
      globalDownloadLimit: settings.globalDownloadLimit,
      globalUploadLimit: settings.globalUploadLimit,
    );
  }

  @override
  Future<void> start() async {
    if (_state == DaemonState.ready) return;
    _userStopped = false;
    _state = DaemonState.starting;

    _port = await _pickFreePort();
    _secret = _generateSecret();

    final stateDir = Directory(p.join(_stateRoot.path, 'state'));
    final confDir = Directory(p.join(_stateRoot.path, 'conf'));
    await stateDir.create(recursive: true);
    await confDir.create(recursive: true);

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

    final confFile = File(p.join(confDir.path, 'aria2.conf'));
    final confText = Aria2ConfigBuilder(
      rpcListenPort: _port,
      rpcSecret: _secret,
      downloadDir: downloadBase.path,
      sessionFilePath: sessionFile.path,
      logFilePath: logFile.path,
      maxConcurrentDownloads: maxConcurrentDownloads,
      maxConnectionPerServer: maxConnectionPerServer,
      globalDownloadLimit: globalDownloadLimit,
      globalUploadLimit: globalUploadLimit,
    ).build();
    await confFile.writeAsString(confText, flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', confFile.path]);
    }
    _confPath = confFile.path;

    final secretFile = File(p.join(_stateRoot.path, 'rpc.secret'));
    await secretFile.writeAsString('$_port\n$_secret', flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', secretFile.path]);
    }

    await _spawnProcess();
    await _waitForRpcReady();
    await _connectWebSocket();

    _state = DaemonState.ready;
  }

  Future<void> _spawnProcess() async {
    final conf = _confPath;
    if (conf == null) {
      throw const Aria2DaemonException('aria2 配置尚未生成');
    }

    await _stderrSub?.cancel();
    _stderrSub = null;
    final proc = _process;
    _process = null;
    if (proc != null) {
      try {
        proc.kill();
      } catch (_) {}
    }

    _process = await Process.start(binaryPath, [
      '--conf-path',
      conf,
    ], mode: ProcessStartMode.normal);

    _stderrSub = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          // ignore: avoid_print
          print('[aria2 stderr] $line');
        });

    unawaited(
      _process!.exitCode.then((code) {
        if (_userStopped || _state == DaemonState.stopping) return;
        _state = DaemonState.failed;
        // ignore: avoid_print
        print('[aria2] process exited unexpectedly: $code');
        _scheduleAutoRestart();
      }),
    );
  }

  void _scheduleAutoRestart() {
    if (_userStopped || _confPath == null) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(_restartDelay, () async {
      if (_userStopped || _confPath == null) return;
      try {
        _state = DaemonState.starting;
        await _ws?.dispose();
        _ws = null;
        _client = null;
        _transport = null;
        await _spawnProcess();
        await _waitForRpcReady();
        await _connectWebSocket();
        _state = DaemonState.ready;
        // ignore: avoid_print
        print('[aria2] auto-restarted');
      } catch (e) {
        // ignore: avoid_print
        print('[aria2] auto-restart failed: $e');
        _scheduleAutoRestart();
      }
    });
  }

  Future<void> _waitForRpcReady() async {
    _transport = Aria2HttpTransport(endpoint: rpcHttpUri, secret: _secret);
    _client = Aria2Client(transport: _transport!);

    const attempts = 50;
    Object? lastError;
    for (var i = 0; i < attempts; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        await _client!.getVersion();
        lastError = null;
        break;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) {
      throw const Aria2DaemonTimeoutException();
    }
  }

  Future<void> _connectWebSocket() async {
    _ws = WsAria2Notifier(endpoint: rpcWebSocketUri, secret: _secret);
    try {
      await _ws!.connect();
      await _ws!.ping();
    } catch (_) {
      await _ws?.dispose();
      _ws = null;
    }
  }

  @override
  Future<void> stop({bool force = false}) async {
    if (_state == DaemonState.stopped) return;
    _userStopped = true;
    _restartTimer?.cancel();
    _restartTimer = null;
    _state = DaemonState.stopping;

    await _stderrSub?.cancel();
    _stderrSub = null;

    final c = _client;
    if (c != null && !force) {
      try {
        await c.shutdown(force: false).timeout(const Duration(seconds: 2));
      } catch (_) {
        /* ignore */
      }
    }

    await _ws?.dispose();
    _ws = null;

    _client = null;
    _transport = null;

    final proc = _process;
    _process = null;
    if (proc != null) {
      try {
        if (force) {
          proc.kill(ProcessSignal.sigkill);
        } else {
          proc.kill();
        }
      } catch (_) {
        /* ignore */
      }
      try {
        await proc.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {
        try {
          proc.kill(ProcessSignal.sigkill);
        } catch (_) {
          /* ignore */
        }
      }
    }

    _state = DaemonState.stopped;
  }

  static Future<int> _pickFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static String _generateSecret() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
