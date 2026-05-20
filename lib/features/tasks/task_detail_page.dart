import 'dart:async';

import 'package:aria2down/core/bitfield_progress.dart';
import 'package:aria2down/core/bt_announce.dart';
import 'package:aria2down/core/format_utils.dart';
import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_deep_link.dart';
import '../../core/reveal_path.dart';
import '../../core/task_detail_poll.dart';
import '../../core/task_list_keys.dart';
import '../../core/task_share.dart';
import '../../providers/aria2_daemon_provider.dart';
import 'task_detail_actions.dart';

/// aria2 `getOption` 中与 BT 相关的常用键（任务级生效值）。
const _kBtOptionDisplayKeys = ['enable-dht', 'enable-dht6', 'bt-enable-lpd'];

/// 单任务详情：概览、文件列表、BitTorrent（announce + peers）。
class TaskDetailPage extends ConsumerStatefulWidget {
  const TaskDetailPage({super.key, required this.gid});

  final String gid;

  @override
  ConsumerState<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends ConsumerState<TaskDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Timer? _timer;
  Map<String, dynamic>? _status;
  List<Map<String, dynamic>> _peers = [];
  Map<String, String>? _btOptions;
  String? _error;
  bool _peersTried = false;
  String? _pollStatusKey;
  bool _loadInFlight = false;
  bool _btOptionsLoaded = false;
  int _peersTickCounter = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _scheduleLoad();
    _restartPollTimer('active');
  }

  void _restartPollTimer(String status) {
    _pollStatusKey = status;
    _timer?.cancel();
    final interval = taskDetailPollInterval(status);
    _timer = Timer.periodic(interval, (_) => _scheduleLoad());
  }

  void _scheduleLoad() {
    if (_loadInFlight) return;
    _loadInFlight = true;
    scheduleMicrotask(() async {
      try {
        final d = ref.read(aria2DaemonProvider).value;
        if (d == null || !mounted) return;
        try {
          final st = await d.client.tellStatus(
            widget.gid,
            keys: kTaskDetailTellKeys,
          );
          List<Map<String, dynamic>> peers = _peers;
          final isBt = st['bittorrent'] != null;
          Map<String, String>? btOpts = _btOptions;
          if (isBt) {
            // 仅在 Peers Tab 可见或每 5 轮拉一次 peers，避免常驻刷新拖慢 UI。
            final peersTabActive = _tabs.index == 2;
            final shouldFetchPeers =
                peersTabActive || (_peersTickCounter++ % 5 == 0);
            if (shouldFetchPeers) {
              try {
                peers = await d.client.getPeers(widget.gid);
              } catch (_) {
                peers = [];
              }
            }
            // 选项几乎不变，首次加载后只在手动刷新时重拉。
            if (!_btOptionsLoaded) {
              try {
                btOpts = await d.client.getOption(widget.gid);
                _btOptionsLoaded = true;
              } catch (_) {
                // 保留上一轮选项，避免界面闪烁
              }
            }
          } else {
            peers = [];
            btOpts = null;
            _btOptionsLoaded = false;
          }
          if (!mounted) return;
          final status = '${st['status'] ?? ''}';
          if (status != _pollStatusKey) {
            _restartPollTimer(status);
          }
          setState(() {
            _status = st;
            _peers = peers;
            _btOptions = btOpts;
            _error = null;
            _peersTried = true;
          });
        } catch (e) {
          if (mounted) {
            setState(() {
              _error = '$e';
              _status = null;
              _btOptions = null;
            });
          }
        }
      } finally {
        _loadInFlight = false;
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  static bool _parseBool(Object? v) {
    if (v == true) return true;
    final s = '$v'.toLowerCase();
    return s == 'true' || s == '1';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final st = _status;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (st != null)
            IconButton(
              tooltip: l10n.taskShare,
              icon: const Icon(Icons.share_outlined),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: buildTaskShareText(st)),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l10n.snackCopied)));
                }
              },
            ),
          if (st != null && extractUrisFromTask(st).isNotEmpty) ...[
            IconButton(
              tooltip: l10n.copyAddTaskLink,
              icon: const Icon(Icons.link),
              onPressed: () async {
                final uris = extractUrisFromTask(st);
                final path = buildInAppAddPathForUris(uris);
                await Clipboard.setData(ClipboardData(text: path));
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l10n.snackCopied)));
                }
              },
            ),
            IconButton(
              tooltip: l10n.copyTaskUris,
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () async {
                final uris = extractUrisFromTask(st);
                await Clipboard.setData(ClipboardData(text: uris.join('\n')));
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l10n.snackCopied)));
                }
              },
            ),
          ],
        ],
        title: Text(
          st != null ? pickTaskName(st) : l10n.taskDetailTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: l10n.taskDetailTabOverview),
            Tab(text: l10n.taskDetailTabFiles),
            Tab(text: l10n.taskDetailTabTorrent),
          ],
        ),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.taskDetailLoadFailed(_error!),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : st == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _OverviewTab(l10n: l10n, status: st),
                _FilesTab(
                  gid: widget.gid,
                  l10n: l10n,
                  status: st,
                  fmtBytes: formatBytes,
                  onApplied: _scheduleLoad,
                ),
                _TorrentTab(
                  l10n: l10n,
                  status: st,
                  peers: _peers,
                  peersTried: _peersTried,
                  btOptions: _btOptions,
                  fmtSpeed: formatSpeed,
                ),
              ],
            ),
      bottomNavigationBar: st != null
          ? TaskDetailActionBar(status: st, onChanged: _scheduleLoad)
          : null,
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.l10n, required this.status});

  final AppLocalizations l10n;
  final Map<String, dynamic> status;

  Future<void> _copy(BuildContext context, String value) async {
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.snackCopied)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final np = int.tryParse('${status['numPieces']}') ?? 0;
    final bf = status['bitfield'] as String?;
    final pieceRatio = pieceCompletionFromBitfield(
      hexBitfield: bf,
      numPieces: np,
    );
    final byteRatio = byteCompletion(
      status['completedLength'],
      status['totalLength'],
    );
    final progress = pieceRatio ?? byteRatio;

    final err = status['errorMessage'];
    final errStr = err is String && err.isNotEmpty ? err : null;

    final rows = <(String, String, bool)>[
      (l10n.taskDetailFieldGid, '${status['gid'] ?? ''}', true),
      (l10n.taskDetailFieldStatus, '${status['status'] ?? ''}', false),
      if (errStr != null) (l10n.taskDetailFieldError, errStr, true),
      (l10n.taskDetailFieldDir, '${status['dir'] ?? ''}', true),
      (l10n.taskDetailFieldTotal, formatBytes(status['totalLength']), false),
      (
        l10n.taskDetailFieldCompleted,
        formatBytes(status['completedLength']),
        false,
      ),
      (
        l10n.taskDetailFieldUploadLength,
        formatBytes(status['uploadLength']),
        false,
      ),
      (
        l10n.taskDetailFieldDownloadSpeed,
        formatSpeed(status['downloadSpeed']),
        false,
      ),
      (
        l10n.taskDetailFieldUploadSpeed,
        formatSpeed(status['uploadSpeed']),
        false,
      ),
      (
        l10n.taskDetailFieldConnections,
        '${status['connections'] ?? '0'}',
        false,
      ),
    ];
    final pl = status['pieceLength'];
    if (np > 0 && pl != null && '$pl'.isNotEmpty) {
      rows.add((
        l10n.taskDetailFieldPieces,
        l10n.taskDetailPieceSummary('$np', formatBytes(pl)),
        false,
      ));
      if (pieceRatio != null) {
        rows.add((
          l10n.taskDetailPieceProgress,
          '${(pieceRatio * 100).toStringAsFixed(1)}%',
          false,
        ));
      }
    }
    if (bf is String && bf.isNotEmpty) {
      final s = bf.length > 128 ? '${bf.substring(0, 128)}…' : bf;
      rows.add((l10n.taskDetailFieldBitfield, s, true));
    }
    final bt = status['bittorrent'];
    if (bt is Map && bt['infoHash'] != null) {
      rows.add((l10n.taskDetailFieldInfoHash, '${bt['infoHash']}', true));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (progress > 0 || np > 0) ...[
          Text(
            l10n.taskDetailOverallProgress,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
          const SizedBox(height: 16),
        ],
        for (final (k, v, copyable) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(k, style: Theme.of(context).textTheme.labelLarge),
                ),
                Expanded(child: SelectableText(v)),
                if (copyable && v.isNotEmpty)
                  IconButton(
                    tooltip: l10n.copyValue,
                    icon: const Icon(Icons.copy_outlined, size: 20),
                    onPressed: () => _copy(context, v),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FilesTab extends ConsumerStatefulWidget {
  const _FilesTab({
    required this.gid,
    required this.l10n,
    required this.status,
    required this.fmtBytes,
    required this.onApplied,
  });

  final String gid;
  final AppLocalizations l10n;
  final Map<String, dynamic> status;
  final String Function(Object?) fmtBytes;
  final VoidCallback onApplied;

  @override
  ConsumerState<_FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends ConsumerState<_FilesTab> {
  final Map<int, bool> _selectedByIndex = {};
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _syncFromStatus(widget.status);
  }

  @override
  void didUpdateWidget(covariant _FilesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty) {
      _syncFromStatus(widget.status);
    }
  }

  void _syncFromStatus(Map<String, dynamic> status) {
    _selectedByIndex.clear();
    final files = status['files'];
    if (files is! List) return;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      if (f is! Map) continue;
      final m = Map<String, dynamic>.from(f);
      final idx = int.tryParse('${m['index'] ?? i + 1}') ?? (i + 1);
      final sel = m['selected'];
      final on =
          sel == true ||
          sel == 'true' ||
          sel == 1 ||
          sel == '1' ||
          '$sel'.toLowerCase() == 'true';
      _selectedByIndex[idx] = on;
    }
  }

  static bool _isBtMultiFileSelectable(Map<String, dynamic> status) {
    if (status['bittorrent'] == null) return false;
    final files = status['files'];
    if (files is! List || files.length < 2) return false;
    final st = '${status['status'] ?? ''}';
    return st == 'active' || st == 'waiting' || st == 'paused';
  }

  Future<void> _applySelection() async {
    final l10n = widget.l10n;
    final indices =
        _selectedByIndex.entries
            .where((e) => e.value)
            .map((e) => e.key)
            .toList()
          ..sort();
    if (indices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.taskDetailNeedOneFileSelected)),
      );
      return;
    }
    final d = ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    try {
      await d.client.changeOption(widget.gid, {
        'select-file': indices.join(','),
      });
      if (!mounted) return;
      setState(() => _dirty = false);
      widget.onApplied();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.taskDetailFileSelectionSaved)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.taskDetailFileSelectionApplyFailed('$e')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final status = widget.status;
    final fmtBytes = widget.fmtBytes;
    final files = status['files'];
    if (files is! List || files.isEmpty) {
      return Center(child: Text(l10n.taskDetailNoFiles));
    }

    final selectable = _isBtMultiFileSelectable(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selectable) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              l10n.taskDetailSelectFilesHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (_dirty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: FilledButton(
                onPressed: _applySelection,
                child: Text(l10n.taskDetailApplyFileSelection),
              ),
            ),
        ],
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: files.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final f = files[i];
              if (f is! Map) return const SizedBox.shrink();
              final m = Map<String, dynamic>.from(f);
              final path = '${m['path'] ?? ''}';
              final len = fmtBytes(m['length']);
              final done = fmtBytes(m['completedLength']);
              final idx = int.tryParse('${m['index'] ?? i + 1}') ?? (i + 1);
              final sel = m['selected'];
              final serverOn =
                  sel == true ||
                  sel == 'true' ||
                  sel == 1 ||
                  sel == '1' ||
                  '$sel'.toLowerCase() == 'true';
              final showCheck = selectable;
              final checkValue = showCheck
                  ? (_selectedByIndex[idx] ?? serverOn)
                  : serverOn;

              return ListTile(
                leading: showCheck
                    ? Checkbox(
                        value: checkValue,
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _selectedByIndex[idx] = v;
                            _dirty = true;
                          });
                        },
                      )
                    : Icon(
                        serverOn
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 20,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                title: Text(path, maxLines: 3),
                subtitle: Text(
                  !showCheck && sel != null
                      ? l10n.taskDetailFileProgressSelected(done, len, '$sel')
                      : l10n.taskDetailFileProgress(done, len),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TorrentTab extends StatelessWidget {
  const _TorrentTab({
    required this.l10n,
    required this.status,
    required this.peers,
    required this.peersTried,
    required this.btOptions,
    required this.fmtSpeed,
  });

  final AppLocalizations l10n;
  final Map<String, dynamic> status;
  final List<Map<String, dynamic>> peers;
  final bool peersTried;
  final Map<String, String>? btOptions;
  final String Function(Object?) fmtSpeed;

  static String _btOptionLabel(AppLocalizations l10n, String key) {
    switch (key) {
      case 'enable-dht':
        return l10n.taskDetailOptionEnableDht;
      case 'enable-dht6':
        return l10n.taskDetailOptionEnableDht6;
      case 'bt-enable-lpd':
        return l10n.taskDetailOptionBtEnableLpd;
      default:
        return key;
    }
  }

  static String _fmtAria2Bool(AppLocalizations l10n, String raw) {
    final t = raw.trim();
    final lower = t.toLowerCase();
    if (lower == 'true' || t == '1') return l10n.taskDetailBoolYes;
    if (lower == 'false' || t == '0') return l10n.taskDetailBoolNo;
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final bt = status['bittorrent'];
    if (bt is! Map) {
      return Center(child: Text(l10n.taskDetailNotTorrent));
    }
    final btm = Map<String, dynamic>.from(bt);
    final name = '${btm['name'] ?? ''}';
    final mode = '${btm['mode'] ?? ''}';
    final tiers = announceTiersFromBittorrent(btm);
    final infoHash = '${status['infoHash'] ?? ''}'.trim();
    final numSeeders = '${status['numSeeders'] ?? ''}'.trim();
    final localSeeder = _TaskDetailPageState._parseBool(status['seeder']);
    final connections = '${status['connections'] ?? ''}'.trim();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            l10n.taskDetailBtMetricsTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (infoHash.isNotEmpty)
          ListTile(
            title: Text(l10n.taskDetailFieldInfoHash),
            subtitle: SelectableText(infoHash),
          ),
        if (numSeeders.isNotEmpty)
          ListTile(
            title: Text(l10n.taskDetailFieldNumSeeders),
            subtitle: Text(numSeeders),
          ),
        ListTile(
          title: Text(l10n.taskDetailFieldLocalSeeder),
          subtitle: Text(
            localSeeder ? l10n.taskDetailBoolYes : l10n.taskDetailBoolNo,
          ),
        ),
        if (connections.isNotEmpty)
          ListTile(
            title: Text(l10n.taskDetailFieldBtConnections),
            subtitle: Text(connections),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            l10n.taskDetailTrackerRpcNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (btOptions != null &&
            _kBtOptionDisplayKeys.any((k) => btOptions!.containsKey(k))) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              l10n.taskDetailBtRpcOptionsTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.taskDetailBtRpcOptionsNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final key in _kBtOptionDisplayKeys)
            if (btOptions!.containsKey(key))
              ListTile(
                title: Text(_btOptionLabel(l10n, key)),
                subtitle: Text(_fmtAria2Bool(l10n, btOptions![key]!)),
              ),
        ],
        if (name.isNotEmpty)
          ListTile(
            title: Text(l10n.taskDetailTorrentName),
            subtitle: SelectableText(name),
          ),
        if (mode.isNotEmpty)
          ListTile(
            title: Text(l10n.taskDetailTorrentMode),
            subtitle: Text(mode),
          ),
        ListTile(
          title: Text(l10n.taskDetailAnnounceList),
          subtitle: tiers.isEmpty
              ? Text(l10n.taskDetailNoAnnounces)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var ti = 0; ti < tiers.length; ti++) ...[
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: ti == 0 ? 6 : 10,
                          top: ti == 0 ? 0 : 4,
                        ),
                        child: Text(
                          l10n.taskDetailAnnounceTier(ti + 1),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      for (final u in tiers[ti])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: SelectableText(u),
                        ),
                    ],
                  ],
                ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            l10n.taskDetailPeersTitle(peers.length),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (!peersTried)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          )
        else if (peers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.taskDetailPeersEmpty),
          )
        else
          ...peers.map((p) {
            final ip = '${p['ip'] ?? ''}';
            final port = '${p['port'] ?? ''}';
            final sub = [
              if (p['downloadSpeed'] != null)
                '${l10n.taskDetailPeerDown}: ${fmtSpeed(p['downloadSpeed'])}',
              if (p['uploadSpeed'] != null)
                '${l10n.taskDetailPeerUp}: ${fmtSpeed(p['uploadSpeed'])}',
            ].join(' · ');
            return ListTile(
              dense: true,
              title: Text('$ip:$port'),
              subtitle: sub.isEmpty ? null : Text(sub),
            );
          }),
      ],
    );
  }
}
