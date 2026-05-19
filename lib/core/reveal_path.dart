import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;

/// 从 [tellStatus] 返回的任务结构中尽量提取可再次 [addUri] 的链接。
List<String> extractUrisFromTask(Map<String, dynamic> task) {
  final out = <String>[];
  final files = task['files'];
  if (files is! List) return out;
  for (final f in files) {
    if (f is! Map) continue;
    final uris = f['uris'];
    if (uris is! List) continue;
    for (final u in uris) {
      if (u is Map && u['uri'] is String) {
        final s = (u['uri'] as String).trim();
        if (s.isNotEmpty) out.add(s);
      }
    }
  }
  return out;
}

/// 任务中第一个本地文件路径（可能尚未完成写入）。
String? firstDownloadedPath(Map<String, dynamic> task) {
  final files = task['files'];
  if (files is! List || files.isEmpty) return null;
  final f = files.first;
  if (f is! Map) return null;
  final path = f['path'];
  if (path is! String || path.isEmpty) return null;
  return path;
}

/// 用于在文件管理器中打开的路径：优先具体文件，其次任务 `dir`。
String? resolveRevealPath(Map<String, dynamic> task) {
  final fp = firstDownloadedPath(task);
  if (fp != null && fp.isNotEmpty) return fp;
  final d = task['dir'];
  if (d is String && d.isNotEmpty) return d;
  return null;
}

/// 在系统文件管理器中展示路径（尽量选中文件）。
///
/// Web 平台无法调用本机文件管理器；请在 UI 层对 [resolveRevealPath] 的返回值使用
/// `Clipboard.setData`（参见 `TaskListPage`）。
Future<RevealPathResult> revealPathInFileManager(String fileOrDirPath) async {
  if (kIsWeb) {
    return RevealPathResult.unsupportedPlatform;
  }

  if (Platform.isAndroid || Platform.isIOS) {
    return _revealOnMobile(fileOrDirPath);
  }

  if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
    return RevealPathResult.unsupportedPlatform;
  }

  final normalized = p.normalize(fileOrDirPath);
  final type = await FileSystemEntity.type(normalized);

  if (Platform.isWindows) {
    if (type == FileSystemEntityType.file) {
      await Process.run('explorer', ['/select,$normalized']);
    } else if (type == FileSystemEntityType.directory) {
      await Process.run('explorer', [normalized]);
    } else {
      final parent = p.dirname(normalized);
      if (parent != normalized) {
        await Process.run('explorer', [parent]);
      }
    }
    return RevealPathResult.ok;
  }

  if (Platform.isMacOS) {
    if (type == FileSystemEntityType.file) {
      await Process.run('open', ['-R', normalized]);
    } else if (type == FileSystemEntityType.directory) {
      await Process.run('open', [normalized]);
    } else {
      final parent = p.dirname(normalized);
      if (parent != normalized) {
        await Process.run('open', [parent]);
      }
    }
    return RevealPathResult.ok;
  }

  // Linux
  if (type == FileSystemEntityType.directory) {
    await Process.run('xdg-open', [normalized]);
  } else {
    final parent = p.dirname(normalized);
    if (parent != normalized) {
      await Process.run('xdg-open', [parent]);
    }
  }
  return RevealPathResult.ok;
}

Future<RevealPathResult> _revealOnMobile(String fileOrDirPath) async {
  final normalized = p.normalize(fileOrDirPath);
  final type = await FileSystemEntity.type(normalized);

  if (type == FileSystemEntityType.directory) {
    return RevealPathResult.unsupportedFolderOnMobile;
  }

  if (type != FileSystemEntityType.file) {
    return RevealPathResult.failed;
  }

  final result = await OpenFile.open(normalized);
  return result.type == ResultType.done
      ? RevealPathResult.ok
      : RevealPathResult.failed;
}

enum RevealPathResult {
  ok,
  unsupportedPlatform,

  /// 移动设备上无法可靠地在「文件管理器」中只打开目录。
  unsupportedFolderOnMobile,
  failed,
}
