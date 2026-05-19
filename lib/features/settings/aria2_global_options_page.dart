import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc_error_message.dart';
import '../../providers/aria2_daemon_provider.dart';

/// 只读展示 aria2 全局选项（`getGlobalOption`）。
class Aria2GlobalOptionsPage extends ConsumerStatefulWidget {
  const Aria2GlobalOptionsPage({super.key});

  @override
  ConsumerState<Aria2GlobalOptionsPage> createState() =>
      _Aria2GlobalOptionsPageState();
}

class _Aria2GlobalOptionsPageState
    extends ConsumerState<Aria2GlobalOptionsPage> {
  Map<String, String>? _options;
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
      final d = await ref.read(aria2DaemonProvider.future);
      final opts = await d.client.getGlobalOption();
      final keys = opts.keys.toList()..sort();
      final sorted = {for (final k in keys) k: opts[k]!};
      if (mounted) {
        setState(() {
          _options = sorted;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _copyAll(AppLocalizations l10n) async {
    final opts = _options;
    if (opts == null) return;
    final lines = [for (final e in _filteredEntries) '${e.key}=${e.value}'];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.copyGlobalOptionsDone)));
    }
  }

  List<MapEntry<String, String>> get _filteredEntries {
    final opts = _options;
    if (opts == null) return [];
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return opts.entries.toList();
    return opts.entries
        .where(
          (e) =>
              e.key.toLowerCase().contains(q) ||
              e.value.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aria2GlobalOptionsTitle),
        actions: [
          if (_options != null)
            IconButton(
              tooltip: l10n.copyGlobalOptions,
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () => _copyAll(l10n),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  formatRpcError(l10n, Exception(_error!)),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: l10n.globalOptionsSearchHint,
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _filteredEntries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = _filteredEntries[i];
                      return ListTile(
                        title: Text(e.key),
                        subtitle: SelectableText(e.value),
                        dense: true,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
