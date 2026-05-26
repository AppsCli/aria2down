import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';

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

/// 「打开下载位置」UI 一站式入口：
///
/// - `path == null` 显示「无法定位文件」snackbar；
/// - Web 端复制路径到剪贴板并 toast「已复制」；
/// - 桌面端正常调用 [revealPathInFileManager]，失败时 toast；
/// - 移动端目录场景弹一个 BottomSheet 让用户复制路径（系统文件管理器
///   不支持通过 intent 打开任意本地目录，只能这样兜底）。
///
/// 三处调用点共用：任务列表卡片 / 任务详情页 AppBar / 历史 Tab 列表项。
Future<void> revealPathInUiWithFeedback(
  BuildContext context,
  AppLocalizations l10n,
  String? path,
) async {
  if (path == null || path.trim().isEmpty) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(l10n.openFolderFailed)));
    return;
  }
  if (kIsWeb) {
    await Clipboard.setData(ClipboardData(text: path));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.openFolderWebCopied)));
    return;
  }
  final r = await revealPathInFileManager(path);
  if (!context.mounted) return;
  switch (r) {
    case RevealPathResult.ok:
      break;
    case RevealPathResult.unsupportedFolderOnMobile:
      await _showMobilePathSheet(context, l10n, path);
      break;
    case RevealPathResult.failed:
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.openFileFailed)));
      break;
    case RevealPathResult.unsupportedPlatform:
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.openFolderFailed)));
      break;
  }
}

Future<void> _showMobilePathSheet(
  BuildContext context,
  AppLocalizations l10n,
  String path,
) async {
  final messenger = ScaffoldMessenger.of(context);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.mobilePathSheetTitle,
            style: Theme.of(ctx).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          SelectableText(path),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: path));
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.mobilePathCopied)),
              );
            },
            icon: const Icon(Icons.copy_outlined),
            label: Text(l10n.copyPath),
          ),
        ],
      ),
    ),
  );
}
