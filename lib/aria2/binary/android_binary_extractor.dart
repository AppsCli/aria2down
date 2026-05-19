import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 从 Flutter assets 释放预置的 `aria2c`（按 ABI 依次尝试）。
///
/// 资源路径：`assets/android/<abi>/aria2c`（由 `scripts/stage_android_aria2.sh` 填充）。
abstract final class AndroidBinaryExtractor {
  static const _tryAbis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

  static Future<String?> resolveBundledPath() async {
    if (!Platform.isAndroid) return null;

    final support = await getApplicationSupportDirectory();
    final dest = File(p.join(support.path, 'bin', 'aria2c'));
    if (await dest.exists()) {
      return dest.path;
    }
    await dest.parent.create(recursive: true);

    for (final abi in _tryAbis) {
      final assetPath = 'assets/android/$abi/aria2c';
      try {
        final data = await rootBundle.load(assetPath);
        await dest.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
        await Process.run('chmod', ['755', dest.path]);
        return dest.path;
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}
