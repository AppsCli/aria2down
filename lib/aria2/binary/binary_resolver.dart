import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'android_binary_extractor.dart';

/// 解析本机 `aria2c` 路径（PATH 或显式覆盖）。
final class BinaryResolver {
  BinaryResolver({this.overridePath});

  /// 用户指定绝对路径（后续设置页写入）。
  final String? overridePath;

  /// 与 [Platform.resolvedExecutable] 同目录的 `aria2c` 候选路径（不含存在性检查）。
  static String bundledCandidatePath() {
    final exe = Platform.resolvedExecutable;
    final dir = p.dirname(exe);
    return p.join(dir, Platform.isWindows ? 'aria2c.exe' : 'aria2c');
  }

  /// 移动平台尚未内嵌二进制时返回 `null`。
  Future<String?> resolve() async {
    if (kIsWeb) return null;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return null;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidBinaryExtractor.resolveBundledPath();
    }
    final override = overridePath?.trim();
    if (override != null && override.isNotEmpty) {
      final f = File(override);
      if (await f.exists()) return f.path;
    }
    final bundled = File(bundledCandidatePath());
    if (await bundled.exists()) {
      return bundled.path;
    }
    final name = Platform.isWindows ? 'aria2c.exe' : 'aria2c';
    final envPath = Platform.environment['PATH'];
    if (envPath == null || envPath.isEmpty) return null;
    final sep = Platform.isWindows ? ';' : ':';
    for (final entry in envPath.split(sep)) {
      final dir = entry.trim();
      if (dir.isEmpty) continue;
      final candidate = p.join(dir, name);
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }
}
