import 'package:flutter/foundation.dart';

import '../client/aria2_client.dart';
import '../client/ws_listener.dart';

/// 抽象：本地子进程或远程 RPC 端点。
abstract class Aria2Daemon {
  int get rpcPort;
  String get rpcSecret;
  Uri get rpcHttpUri;
  Uri get rpcWebSocketUri;

  Aria2Client get client;

  /// WebSocket 通知（不可用则为 `null`，任务列表将回退轮询）。
  ///
  /// 远程/本机子进程：[WsAria2Notifier]；
  /// 内嵌库：基于 libaria2 事件回调的等价 [Aria2NotificationSource]。
  Aria2NotificationSource? get wsNotifier => null;

  /// 连接代际计数：每次 daemon 内部 client / WS 重建（如 LocalDaemon
  /// auto-restart、RemoteDaemon WS 重连）时自增。UI 层应监听此值，发现变化
  /// 时重新绑定 WS 订阅并重建任何依赖 [client] 的组件（如历史记录器）。
  ///
  /// 默认实现是常量 `ValueListenable<int>`，不会触发任何 listener 回调，
  /// 适合不会内部重建连接的实现（如 [LibraryDaemon]）。
  ValueListenable<int> get connectionGeneration => _kStaticGeneration;

  /// 本机 aria2 日志路径（仅 [LocalDaemon] 有值）。
  String? get logFilePath => null;

  Future<void> start();

  Future<void> stop({bool force = false});
}

/// 常量 0 generation：对不会重建内部连接的 daemon 用此节省一个 ValueNotifier。
///
/// 这是只读 `ValueListenable<int>`，永远返回 0 且不会通知 listener；
/// 共享同一个实例不影响任何调用方（addListener 不会被调用回调）。
final ValueListenable<int> _kStaticGeneration = ValueNotifier<int>(0);
