import 'dart:async';
import 'dart:convert';

import 'package:aria2down/l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download_dir_picker.dart';
import '../../core/incoming_link.dart';
import '../../core/picked_file_bytes.dart';
import '../../core/platform_hints.dart';
import '../../core/queue_uris.dart';
import '../../core/rpc_error_message.dart';
import '../../core/torrent_metainfo.dart';
import '../../core/uri_utils.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/aria2_daemon_provider.dart';
import '../../providers/pending_payload_provider.dart';

class AddTaskPage extends ConsumerStatefulWidget {
  const AddTaskPage({super.key, this.initialUris = const []});

  /// 来自路由 `/add?uri=` 或扩展深链的预填链接。
  final List<String> initialUris;

  @override
  ConsumerState<AddTaskPage> createState() => _AddTaskPageState();
}

class _AddTaskPageState extends ConsumerState<AddTaskPage> {
  final _urlCtrl = TextEditingController();
  final _uaCtrl = TextEditingController();
  final _headerCtrl = TextEditingController();
  final _cookieCtrl = TextEditingController();
  final _limitCtrl = TextEditingController();

  /// 本次任务的下载目录（仅本次有效，留空走全局 [AppSettings.downloadDirectoryOverride]）。
  ///
  /// 不在「高级选项」之外单设字段是为了不打断用户主流程：URL 粘贴 → 直接 Add；
  /// 需要换位置的用户会自己展开高级选项填入或在 [AppSettings.askDownloadDirEachTime]
  /// 开启时由提交流程弹窗收集。
  final _dirCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialUris.isNotEmpty) {
      _urlCtrl.text = widget.initialUris.join('\n');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainPendingFile());
  }

  @override
  void didUpdateWidget(covariant AddTaskPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialUris.isNotEmpty &&
        !_listEquals(widget.initialUris, oldWidget.initialUris)) {
      _urlCtrl.text = widget.initialUris.join('\n');
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 消费外部唤起投递的 .torrent / .metalink 字节，直接调用 aria2 RPC。
  Future<void> _drainPendingFile() async {
    if (!mounted) return;
    final pending = ref.read(pendingIncomingFileProvider.notifier).consume();
    if (pending == null) return;
    final l10n = AppLocalizations.of(context)!;
    final d = ref.read(aria2DaemonProvider).value;
    if (d == null) {
      ref.read(pendingIncomingFileProvider.notifier).offer(pending);
      return;
    }
    final askResult = await _maybeAskDownloadDir();
    if (askResult.isCancel) return;
    final opts = _buildRpcOptions(overrideDir: askResult.path);
    try {
      final b64 = base64Encode(pending.bytes);
      if (pending.kind == IncomingFileKind.torrent) {
        Set<int>? selected;
        try {
          final entries = parseTorrentFileList(pending.bytes);
          if (entries.length > 1 && mounted) {
            selected = await showDialog<Set<int>>(
              context: context,
              builder: (ctx) => _TorrentFilesDialog(entries: entries),
            );
            if (selected == null) return;
            if (selected.isEmpty) return;
            if (selected.length < entries.length) {
              opts['select-file'] = (selected.toList()..sort()).join(',');
            }
          }
        } catch (e, st) {
          // 解析 .torrent 元信息失败：不影响添加任务本身（会让 aria2 在
          // metadata 阶段自行处理），但需要在终端留痕方便排查"为什么没弹
          // 文件选择对话框"。
          debugPrint('[add_task] parse torrent metainfo failed: $e');
          debugPrintStack(stackTrace: st, label: 'add_task parse-torrent');
        }
        await d.client.addTorrent(b64, options: opts.isEmpty ? null : opts);
      } else {
        await d.client.addMetalink(b64, options: opts.isEmpty ? null : opts);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.snackAdded)));
      }
    } catch (e, st) {
      debugPrint('[add_task] add torrent/metalink failed: $e');
      debugPrintStack(stackTrace: st, label: 'add_task add-file');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatRpcError(l10n, e))));
      }
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _uaCtrl.dispose();
    _headerCtrl.dispose();
    _cookieCtrl.dispose();
    _limitCtrl.dispose();
    _dirCtrl.dispose();
    super.dispose();
  }

  /// 构造 aria2 RPC `options` map。
  ///
  /// `overrideDir` 优先级最高：用户在「本次下载目录」字段或 askEachTime 弹窗
  /// 里临时选定的路径。其次是高级选项里手填的 `_dirCtrl`，最后才回退到全局
  /// 默认 [AppSettings.downloadDirectoryOverride]。空串视为未设置，让 aria2
  /// 用 daemon 的全局 `dir`（即应用启动时算好的下载根目录）。
  Map<String, dynamic> _buildRpcOptions({String? overrideDir}) {
    final o = <String, dynamic>{};
    final settings = ref.read(appSettingsProvider).valueOrNull;
    final dir = resolveDownloadDirForTask(
      overrideDir: overrideDir,
      manualField: _dirCtrl.text,
      globalDefault: settings?.downloadDirectoryOverride,
    );
    if (dir != null && dir.isNotEmpty) {
      o['dir'] = dir;
    }
    final ua = _uaCtrl.text.trim();
    if (ua.isNotEmpty) {
      o['user-agent'] = ua;
    }
    final lim = _limitCtrl.text.trim();
    if (lim.isNotEmpty) {
      o['max-download-limit'] = lim;
    }
    final headers = <String>[];
    for (final line in _headerCtrl.text.split('\n')) {
      final t = line.trim();
      if (t.contains(':')) headers.add(t);
    }
    final cookie = _cookieCtrl.text.trim();
    if (cookie.isNotEmpty) {
      headers.add('Cookie: $cookie');
    }
    if (headers.isNotEmpty) {
      o['header'] = headers.length == 1 ? headers.single : headers;
    }
    return o;
  }

  /// 在用户开启「每次询问下载目录」时，提交任务前先调起跨平台目录选择器。
  ///
  /// 返回 sentinel 区分三种语义：
  /// - `_AskDirResult.skip`：用户已经在「本次下载目录」字段或全局默认里指定
  ///   过路径，**不需要**再弹窗；
  /// - `_AskDirResult.pick(path)`：用户在弹窗里选了/输入了路径；
  /// - `_AskDirResult.cancel`：用户在弹窗里点了「取消」——提交流程应当中止
  ///   而不是 silently 用默认目录。
  Future<_AskDirResult> _maybeAskDownloadDir() async {
    final settings = ref.read(appSettingsProvider).valueOrNull;
    if (settings?.askDownloadDirEachTime != true) {
      return const _AskDirResult.skip();
    }
    // 已经在本次字段填了就不打扰；全局默认存在也直接用——askEachTime 只是为
    // 那些没有固定目录的用户准备的提示，不是强制覆盖。
    final manual = _dirCtrl.text.trim();
    if (manual.isNotEmpty) return const _AskDirResult.skip();
    final globalDefault = settings?.downloadDirectoryOverride?.trim();
    final picked = await pickDownloadDirectory(
      context,
      initialDirectory: (globalDefault != null && globalDefault.isNotEmpty)
          ? globalDefault
          : null,
    );
    if (picked == null) return const _AskDirResult.cancel();
    return _AskDirResult.pick(picked);
  }

  Future<void> _addUris(List<String> uris, AppLocalizations l10n) async {
    final d = ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    final askResult = await _maybeAskDownloadDir();
    if (askResult.isCancel) return;
    final opts = _buildRpcOptions(overrideDir: askResult.path);
    try {
      final result = await queueUrisToAria2(
        d.client,
        uris,
        options: opts.isEmpty ? null : opts,
      );
      if (result.added == 0) {
        if (mounted) {
          // 全失败时显示真正的 RPC 错误，全重复时显示去重提示。
          final msg = result.errors.isNotEmpty
              ? formatRpcError(l10n, result.errors.first.error)
              : l10n.snackAllDuplicates;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(msg)));
        }
        return;
      }
      if (mounted) {
        final skippedTotal = result.skipped + result.errors.length;
        final msg = skippedTotal > 0
            ? l10n.snackAddedWithSkipped(result.added, skippedTotal)
            : (result.added == 1
                  ? l10n.snackAdded
                  : l10n.snackAddedCount(result.added));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e, st) {
      debugPrint('[add_task] _addUris(${uris.length}) failed: $e');
      debugPrintStack(stackTrace: st, label: 'add_task _addUris');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatRpcError(l10n, e))));
      }
    }
  }

  Future<void> _pasteAndAdd() async {
    final l10n = AppLocalizations.of(context)!;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.clipboardEmpty)));
      }
      return;
    }
    final uris = extractDownloadUrisFromText(text);
    if (uris.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.snackInvalidUrl)));
      }
      return;
    }
    await _addUris(uris, l10n);
  }

  Future<void> _pasteFromClipboard() async {
    final l10n = AppLocalizations.of(context)!;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.clipboardEmpty)));
      }
      return;
    }
    final existing = _urlCtrl.text.trim();
    _urlCtrl.text = existing.isEmpty ? text : '$existing\n$text';
    _urlCtrl.selection = TextSelection.collapsed(offset: _urlCtrl.text.length);
  }

  Future<void> _submitUrls() async {
    final l10n = AppLocalizations.of(context)!;
    final uris = extractDownloadUrisFromText(_urlCtrl.text);
    if (uris.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.snackInvalidUrl)));
      return;
    }
    await _addUris(uris, l10n);
    if (mounted) _urlCtrl.clear();
  }

  Future<void> _pickAndAddTorrent() async {
    final l10n = AppLocalizations.of(context)!;
    final d = ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['torrent'],
      withData: true,
    );
    if (pick == null || pick.files.isEmpty) return;
    final bytes = await readPickedFileBytes(pick.files.single);
    if (bytes == null) return;
    try {
      final entries = parseTorrentFileList(bytes);
      Set<int>? selected;
      if (entries.length > 1) {
        if (!mounted) return;
        selected = await showDialog<Set<int>>(
          context: context,
          builder: (ctx) => _TorrentFilesDialog(entries: entries),
        );
        if (selected == null) return;
        if (selected.isEmpty) return;
      }
      final askResult = await _maybeAskDownloadDir();
      if (askResult.isCancel) return;
      final opts = Map<String, dynamic>.from(
        _buildRpcOptions(overrideDir: askResult.path),
      );
      if (entries.length > 1 &&
          selected != null &&
          selected.length < entries.length) {
        opts['select-file'] = (selected.toList()..sort()).join(',');
      }
      final b64 = base64Encode(bytes);
      await d.client.addTorrent(b64, options: opts.isEmpty ? null : opts);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.snackAdded)));
      }
    } catch (e, st) {
      debugPrint('[add_task] pick-and-add torrent failed: $e');
      debugPrintStack(stackTrace: st, label: 'add_task pickTorrent');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatRpcError(l10n, e))));
      }
    }
  }

  Future<void> _pickAndAddMetalink() async {
    final l10n = AppLocalizations.of(context)!;
    final d = ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['metalink', 'meta4'],
      withData: true,
    );
    if (pick == null || pick.files.isEmpty) return;
    final bytes = await readPickedFileBytes(pick.files.single);
    if (bytes == null) return;
    try {
      final askResult = await _maybeAskDownloadDir();
      if (askResult.isCancel) return;
      final b64 = base64Encode(bytes);
      final opts = _buildRpcOptions(overrideDir: askResult.path);
      await d.client.addMetalink(b64, options: opts.isEmpty ? null : opts);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.snackAdded)));
      }
    } catch (e, st) {
      debugPrint('[add_task] pick-and-add metalink failed: $e');
      debugPrintStack(stackTrace: st, label: 'add_task pickMetalink');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatRpcError(l10n, e))));
      }
    }
  }

  Future<void> _pickDirForThisTask() async {
    final picked = await pickDownloadDirectory(
      context,
      initialDirectory: _dirCtrl.text.trim().isNotEmpty
          ? _dirCtrl.text.trim()
          : ref
                .read(appSettingsProvider)
                .valueOrNull
                ?.downloadDirectoryOverride,
    );
    if (picked != null && mounted) {
      setState(() => _dirCtrl.text = picked);
    }
  }

  Widget _buildAdvancedOptions(AppLocalizations l10n) {
    return ExpansionTile(
      title: Text(l10n.advancedOptions),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        TextField(
          controller: _dirCtrl,
          decoration: InputDecoration(
            labelText: l10n.addTaskFieldDownloadDir,
            hintText: l10n.addTaskFieldDownloadDirHint,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: l10n.pickDownloadDirTooltip,
              icon: const Icon(Icons.folder_open_outlined),
              onPressed: _pickDirForThisTask,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _uaCtrl,
          decoration: InputDecoration(
            labelText: l10n.userAgent,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _headerCtrl,
          decoration: InputDecoration(
            labelText: l10n.headersHint,
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          minLines: 2,
          maxLines: 6,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _cookieCtrl,
          decoration: InputDecoration(
            labelText: l10n.cookie,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _limitCtrl,
          decoration: InputDecoration(
            labelText: l10n.speedLimitHint,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(AppLocalizations l10n, {required bool mobile}) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (!mobile)
          FilledButton(onPressed: _submitUrls, child: Text(l10n.addButton)),
        OutlinedButton.icon(
          onPressed: _pasteFromClipboard,
          icon: const Icon(Icons.content_paste_outlined),
          label: Text(l10n.pasteFromClipboard),
        ),
        OutlinedButton.icon(
          onPressed: _pasteAndAdd,
          icon: const Icon(Icons.playlist_add),
          label: Text(l10n.pasteAndAdd),
        ),
        OutlinedButton.icon(
          onPressed: _pickAndAddTorrent,
          icon: const Icon(Icons.file_present_outlined),
          label: Text(l10n.pickTorrent),
        ),
        OutlinedButton.icon(
          onPressed: _pickAndAddMetalink,
          icon: const Icon(Icons.link),
          label: Text(l10n.pickMetalink),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mobile = isMobilePlatform;
    ref.listen<PendingFilePayload?>(pendingIncomingFileProvider, (prev, next) {
      if (next != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _drainPendingFile(),
        );
      }
    });
    final urlField = TextField(
      controller: _urlCtrl,
      decoration: InputDecoration(
        hintText: l10n.hintUrls,
        border: const OutlineInputBorder(),
      ),
      minLines: 4,
      maxLines: 12,
      autofocus: true,
    );
    final sideColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildActionButtons(l10n, mobile: mobile),
        const SizedBox(height: 8),
        Text(l10n.torrentNote, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        _buildAdvancedOptions(l10n),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navAdd)),
      floatingActionButton: mobile
          ? FloatingActionButton.extended(
              onPressed: _submitUrls,
              icon: const Icon(Icons.add),
              label: Text(l10n.addButton),
            )
          : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          final padding = EdgeInsets.fromLTRB(16, 16, 16, mobile ? 88 : 16);
          if (!wide) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [urlField, const SizedBox(height: 12), sideColumn],
              ),
            );
          }
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: urlField),
                const SizedBox(width: 24),
                Expanded(flex: 2, child: sideColumn),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// "每次询问下载目录"弹窗的三态返回：跳过 / 选定 / 取消。
class _AskDirResult {
  const _AskDirResult.skip() : path = null, isCancel = false;
  const _AskDirResult.cancel() : path = null, isCancel = true;
  const _AskDirResult.pick(this.path) : isCancel = false;

  final String? path;
  final bool isCancel;

  bool get isSkip => path == null && !isCancel;
}

class _TorrentFilesDialog extends StatefulWidget {
  const _TorrentFilesDialog({required this.entries});

  final List<TorrentFileEntry> entries;

  @override
  State<_TorrentFilesDialog> createState() => _TorrentFilesDialogState();
}

class _TorrentFilesDialogState extends State<_TorrentFilesDialog> {
  late Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.entries.map((e) => e.index).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.torrentSelectDialogTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: widget.entries.map((e) {
              return CheckboxListTile(
                dense: true,
                value: _selected.contains(e.index),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selected.add(e.index);
                    } else {
                      _selected.remove(e.index);
                    }
                  });
                },
                title: Text(
                  e.displayName,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.dialogCancel),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, Set<int>.from(_selected)),
          child: Text(l10n.torrentSelectDialogConfirm),
        ),
      ],
    );
  }
}
