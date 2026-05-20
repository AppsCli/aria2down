import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 从外部唤起入口投递过来的本地/内容文件 URI 中读取字节。
///
/// - `file://...`：所有原生平台 + Linux/Windows 直接读取磁盘文件。
/// - `content://...`（仅 Android）：通过 [MethodChannel] 走 ContentResolver
///   读取字节（受 `Intent.FLAG_GRANT_READ_URI_PERMISSION` 临时授权约束）。
///
/// 失败返回 `null`，由 UI 兜底为「请用文件选择器再来一次」。
class IncomingFileLoader {
  IncomingFileLoader._();

  static const MethodChannel _channel = MethodChannel(
    'cloud.iothub.aria2down/incoming_link',
  );

  static Future<Uint8List?> readBytes(String uriString) async {
    final uri = Uri.tryParse(uriString);
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();

    if (scheme == 'file') {
      try {
        return await File(uri.toFilePath()).readAsBytes();
      } catch (_) {
        return null;
      }
    }

    if (scheme == 'content' &&
        defaultTargetPlatform == TargetPlatform.android) {
      try {
        final res = await _channel.invokeMethod<Uint8List>('readContent', {
          'uri': uriString,
        });
        return res;
      } catch (_) {
        return null;
      }
    }

    return null;
  }
}
