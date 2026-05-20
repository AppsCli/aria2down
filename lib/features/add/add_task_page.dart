import 'dart:async';
import 'dart:convert';

import 'package:aria2down/l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/picked_file_bytes.dart';
import '../../core/platform_hints.dart';
import '../../core/queue_uris.dart';
import '../../core/rpc_error_message.dart';
import '../../core/torrent_metainfo.dart';
import '../../core/uri_utils.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/aria2_daemon_provider.dart';

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

  @override
  void initState() {
    super.initState();
    if (widget.initialUris.isNotEmpty) {
      _urlCtrl.text = widget.initialUris.join('\n');
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _uaCtrl.dispose();
    _headerCtrl.dispose();
    _cookieCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildRpcOptions() {
    final o = <String, dynamic>{};
    final settings = ref.read(appSettingsProvider).valueOrNull;
    final dir = settings?.downloadDirectoryOverride?.trim();
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

  Future<void> _addUris(List<String> uris, AppLocalizations l10n) async {
    final d = ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    final opts = _buildRpcOptions();
    try {
      final result = await queueUrisToAria2(
        d.client,
        uris,
        options: opts.isEmpty ? null : opts,
      );
      if (result.added == 0) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.snackAllDuplicates)));
        }
        return;
      }
      if (mounted) {
        final msg = result.skipped > 0
            ? l10n.snackAddedWithSkipped(result.added, result.skipped)
            : (result.added == 1
                  ? l10n.snackAdded
                  : l10n.snackAddedCount(result.added));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
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
      final opts = Map<String, dynamic>.from(_buildRpcOptions());
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
    } catch (e) {
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
      final b64 = base64Encode(bytes);
      final opts = _buildRpcOptions();
      await d.client.addMetalink(b64, options: opts.isEmpty ? null : opts);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.snackAdded)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatRpcError(l10n, e))));
      }
    }
  }

  Widget _buildAdvancedOptions(AppLocalizations l10n) {
    return ExpansionTile(
      title: Text(l10n.advancedOptions),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
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
