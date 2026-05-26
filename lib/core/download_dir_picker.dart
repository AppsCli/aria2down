import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../l10n/app_localizations.dart';
import 'platform_hints.dart';

/// 跨平台下载目录选择器：返回 aria2 引擎能直接写入的**本地文件系统路径**。
///
/// 设计取舍按平台沙箱模型分两条腿：
///
/// - **桌面（macOS / Windows / Linux）**：直接调 [getDirectoryPath]，弹系统
///   原生目录选择器。macOS sandbox 通过 `com.apple.security.files.user-
///   selected.read-write` entitlement 自动授权用户选中的目录读写，无需额外
///   持久化书签——一次选定的目录在当前应用生命周期内可读可写，sandbox
///   policy 由系统自动颁发。
///
/// - **移动端（Android / iOS）**：**不弹 SAF**——SAF tree URI 形如
///   `content://com.android.externalstorage.documents/tree/primary%3ADownload`，
///   libaria2 与 `aria2c` 子进程都不识别这种 URI，强行喂进 `dir` 选项会让
///   aria2 在文件分配阶段抛 "Failed to create directory"。取而代之地弹一个
///   自绘 [_MobileDownloadDirSheet]：列出几个**沙箱内可写**的候选目录，并
///   允许用户输入子目录名快速建一个。
///
///   候选清单：
///   - Android: 应用专属外部目录 `getExternalStorageDirectory()` →
///     `/sdcard/Android/data/<pkg>/files`（无需任何运行时权限，**卸载时
///     系统会一并删除**——用户须知）。再加上应用内部 Documents 目录
///     `getApplicationDocumentsDirectory()` → `/data/data/<pkg>/app_flutter`
///     作为备选。
///   - iOS: `getApplicationDocumentsDirectory()`（用户在 Files App 可见）+
///     `getApplicationSupportDirectory()`（更隐蔽，适合后台数据）。
///
///   高级用户可手动输入任意路径——但应用对该路径必须实际具备写权限，否则
///   aria2 启动下载时会报 errno=13。
///
/// 返回 `null` 表示用户取消。空字符串会被视为取消。
Future<String?> pickDownloadDirectory(
  BuildContext context, {
  String? initialDirectory,
}) async {
  final l10n = AppLocalizations.of(context)!;
  if (kIsWeb) {
    // Web 没有"本地下载目录"概念——浏览器决定保存位置。
    return null;
  }
  if (!isMobilePlatform) {
    return _pickDesktopDirectory(initialDirectory: initialDirectory);
  }
  return showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) =>
        _MobileDownloadDirSheet(l10n: l10n, initialDirectory: initialDirectory),
  );
}

Future<String?> _pickDesktopDirectory({String? initialDirectory}) async {
  return getDirectoryPath(initialDirectory: initialDirectory);
}

/// 按优先级解析"本次任务的下载目录"。
///
/// 显式的 [overrideDir]（来自 askEachTime 弹窗 / picker 按钮）> 用户在 Add
/// 高级选项手填的 [manualField] > 设置页全局默认 [globalDefault]。任一字段
/// 为 trim 后空串都视为「未设置」继续往下找。返回 null 表示全部都没填，
/// 让 aria2 daemon 用进程级默认 `dir`（[LibraryDaemon] 启动时算好的根目录）。
///
/// 抽到 [download_dir_picker.dart] 顶级以便：
/// - [AddTaskPage] 在所有提交入口共用；
/// - 单测可直接覆盖优先级与空串处理，不依赖任何 widget 状态。
String? resolveDownloadDirForTask({
  String? overrideDir,
  String? manualField,
  String? globalDefault,
}) {
  for (final v in <String?>[overrideDir, manualField, globalDefault]) {
    final t = v?.trim();
    if (t != null && t.isNotEmpty) return t;
  }
  return null;
}

/// 移动端「沙箱内可写目录」候选 + 自定义子目录 BottomSheet。
class _MobileDownloadDirSheet extends StatefulWidget {
  const _MobileDownloadDirSheet({required this.l10n, this.initialDirectory});

  final AppLocalizations l10n;
  final String? initialDirectory;

  @override
  State<_MobileDownloadDirSheet> createState() =>
      _MobileDownloadDirSheetState();
}

class _MobileDownloadDirSheetState extends State<_MobileDownloadDirSheet> {
  late final TextEditingController _manualCtrl;
  Future<List<_DirCandidate>>? _candidatesFuture;

  @override
  void initState() {
    super.initState();
    _manualCtrl = TextEditingController(text: widget.initialDirectory ?? '');
    _candidatesFuture = _loadCandidates();
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<List<_DirCandidate>> _loadCandidates() async {
    final out = <_DirCandidate>[];
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        out.add(
          _DirCandidate(
            label: widget.l10n.downloadDirAndroidExternalFiles,
            path: ext.path,
            removableOnUninstall: true,
          ),
        );
      }
      final docs = await getApplicationDocumentsDirectory();
      out.add(
        _DirCandidate(
          label: widget.l10n.downloadDirAndroidAppDocuments,
          path: docs.path,
          removableOnUninstall: true,
        ),
      );
    } else if (Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      out.add(
        _DirCandidate(
          label: widget.l10n.downloadDirIosDocuments,
          path: docs.path,
          removableOnUninstall: false,
        ),
      );
      final support = await getApplicationSupportDirectory();
      out.add(
        _DirCandidate(
          label: widget.l10n.downloadDirIosAppSupport,
          path: support.path,
          removableOnUninstall: false,
        ),
      );
    }
    return out;
  }

  void _useCandidate(_DirCandidate c, {String? subdir}) {
    final base = c.path;
    final resolved = (subdir == null || subdir.trim().isEmpty)
        ? base
        : p.join(base, subdir.trim());
    Navigator.of(context).pop(resolved);
  }

  void _useManualInput() {
    final raw = _manualCtrl.text.trim();
    if (raw.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    return SafeArea(
      child: FutureBuilder<List<_DirCandidate>>(
        future: _candidatesFuture,
        builder: (ctx, snap) {
          final cands = snap.data ?? const <_DirCandidate>[];
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    l10n.downloadDirMobileSheetTitle,
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    l10n.downloadDirMobileSheetNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (snap.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  for (final c in cands)
                    _CandidateTile(
                      candidate: c,
                      l10n: l10n,
                      onUse: (subdir) => _useCandidate(c, subdir: subdir),
                    ),
                  const Divider(height: 24),
                ],
                Text(
                  l10n.downloadDirManualPathLabel,
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _manualCtrl,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: l10n.downloadDirManualPathHint,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.dialogCancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _useManualInput,
                      child: Text(l10n.downloadDirMobileSheetConfirm),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CandidateTile extends StatefulWidget {
  const _CandidateTile({
    required this.candidate,
    required this.l10n,
    required this.onUse,
  });

  final _DirCandidate candidate;
  final AppLocalizations l10n;
  final void Function(String? subdir) onUse;

  @override
  State<_CandidateTile> createState() => _CandidateTileState();
}

class _CandidateTileState extends State<_CandidateTile> {
  final _subdirCtrl = TextEditingController();
  var _expanded = false;

  @override
  void dispose() {
    _subdirCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = widget.candidate;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.folder_outlined, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        c.path,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => widget.onUse(null),
                  child: Text(widget.l10n.downloadDirCandidateUse),
                ),
              ],
            ),
            if (c.removableOnUninstall)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  widget.l10n.downloadDirRemovableOnUninstall,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.tertiary,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (!_expanded)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(widget.l10n.downloadDirCandidateUseSubdir),
                  onPressed: () => setState(() => _expanded = true),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _subdirCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        hintText: widget.l10n.downloadDirSubdirHint,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => widget.onUse(_subdirCtrl.text),
                    child: Text(widget.l10n.downloadDirCandidateUse),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DirCandidate {
  const _DirCandidate({
    required this.label,
    required this.path,
    required this.removableOnUninstall,
  });

  final String label;
  final String path;

  /// 该目录是否会随应用卸载被系统一并清空（Android 应用专属外部存储 / 内
  /// 部沙箱 / iOS 沙箱目录 = true；用户主目录 = false）。
  final bool removableOnUninstall;
}
