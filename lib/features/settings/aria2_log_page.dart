import 'dart:convert';
import 'dart:io';

import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 查看本机 aria2 日志文件尾部。
class Aria2LogPage extends StatefulWidget {
  const Aria2LogPage({super.key, required this.logPath});

  final String logPath;

  @override
  State<Aria2LogPage> createState() => _Aria2LogPageState();
}

class _Aria2LogPageState extends State<Aria2LogPage> {
  String? _content;
  String? _error;
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final file = File(widget.logPath);
      if (!await file.exists()) {
        if (mounted) {
          setState(() {
            _content = '';
            _loading = false;
          });
        }
        return;
      }
      final lines = await file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      final tail = lines.length > 400
          ? lines.sublist(lines.length - 400)
          : lines;
      if (mounted) {
        setState(() {
          _content = tail.join('\n');
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  String get _displayText {
    final raw = _content ?? '';
    if (_query.trim().isEmpty) return raw;
    final q = _query.trim().toLowerCase();
    return raw
        .split('\n')
        .where((line) => line.toLowerCase().contains(q))
        .join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aria2LogTitle),
        actions: [
          if (_content != null && _content!.isNotEmpty)
            IconButton(
              tooltip: l10n.copyValue,
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _displayText));
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l10n.snackCopied)));
                }
              },
            ),
          IconButton(
            tooltip: l10n.refreshTasks,
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: l10n.aria2LogSearchHint,
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      _displayText.isEmpty
                          ? (_content?.isEmpty ?? true
                                ? l10n.aria2LogEmpty
                                : l10n.aria2LogNoMatch)
                          : _displayText,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
