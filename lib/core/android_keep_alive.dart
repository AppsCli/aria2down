import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 前台 Service（P4-03 骨架）：本机 aria2 运行时保持进程不易被杀。
abstract final class AndroidKeepAlive {
  static const _channel = MethodChannel('cloud.iothub.aria2down/keep_alive');

  static Future<void> start() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('start');
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
