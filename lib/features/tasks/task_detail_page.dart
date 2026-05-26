import 'dart:async';

import 'package:aria2down/core/bitfield_progress.dart';
import 'package:aria2down/core/bt_announce.dart';
import 'package:aria2down/core/format_utils.dart';
import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../aria2/client/aria2_exceptions.dart';
import '../../core/app_deep_link.dart';
import '../../core/reveal_path.dart';
import '../../core/rpc_error_message.dart';
import '../../core/task_detail_poll.dart';
import '../../core/task_list_keys.dart';
import '../../core/task_share.dart';
import '../../data/task_history_repository.dart';
import '../../providers/aria2_daemon_provider.dart';
import 'task_detail_actions.dart';
import 'task_history_tab.dart';

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
  // 当 aria2 找不到该任务（被 purge / session 重置）时从 TaskHistoryRepository
  // 读取的本地快照——`true` 时 TabBarView 上方挂一条「正在显示历史快照」横
  // 幅，并停掉轮询计时器（继续 tellStatus 也只会再次失败）。
  bool _fromHistorySnapshot = false;

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
              } catch (e, st) {
                // 单条 getPeers 失败不应阻塞整页；UI 仍能展示其余字段，
                // 但日志要明确：之前实现 catch(_){} 会把 -1004 / 非 BT
                // 任务的合法报错也吞掉，排查 peers 列表为空时无从下手。
                debugPrint('[task_detail] getPeers(${widget.gid}) failed: $e');
                debugPrintStack(stackTrace: st, label: 'task_detail getPeers');
                peers = [];
              }
            }
            // 选项几乎不变，首次加载后只在手动刷新时重拉。
            if (!_btOptionsLoaded) {
              try {
                btOpts = await d.client.getOption(widget.gid);
                _btOptionsLoaded = true;
              } catch (e, st) {
                debugPrint('[task_detail] getOption(${widget.gid}) failed: $e');
                debugPrintStack(stackTrace: st, label: 'task_detail getOption');
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
        } catch (e, st) {
          // 任务已不在 session：典型场景是「从历史 Tab 点进来 / 库引擎重启
          // 清空了 downloadResults_」，aria2/FFI 返回 -1006 (ERR_NOT_FOUND)
          // 或 'No such download for GID'。这种情况下尝试从本地历史读取快
          // 照展示，让三个 Tab 仍可用；其他错误（鉴权 / 网络）保留原 banner
          // 走 retry 路径。
          //
          // 关于日志：Aria2LoggingTransport 已对 -1006 / "no such download"
          // 打了一条 `soft failure` 简讯，这里**不再**重复 `debugPrint` +
          // `debugPrintStack`，避免把同一次预期降级在终端喷 6~8 行栈把真正
          // 需要排查的异常淹没；只在判定为「真正失败」（非 not-found）时打
          // 完整栈，并在 fallback 命中后补一行说明。
          final notFound = _isTaskNotFoundError(e);
          if (!notFound) {
            debugPrint('[task_detail] tellStatus(${widget.gid}) failed: $e');
            debugPrintStack(stackTrace: st, label: 'task_detail tellStatus');
          }
          if (_status == null && notFound) {
            final snapshot = await _loadHistorySnapshot(widget.gid);
            if (snapshot != null && mounted) {
              debugPrint(
                '[task_detail] gid=${widget.gid} not in session; '
                'showing local history snapshot.',
              );
              _timer?.cancel();
              setState(() {
                _status = snapshot;
                _error = null;
                _peers = const [];
                _btOptions = null;
                _peersTried = true;
                _fromHistorySnapshot = true;
              });
              return;
            }
          }
          if (mounted) {
            // 关键差异：不再清空 `_status`。如果之前加载过成功的数据，
            // 让用户继续看老数据 + 顶部错误 banner 提示，比"三个 Tab
            // 全消失换一个全屏 'Load failed'"友好得多。只有从未加载过
            // （`_status == null`）时，build 才会落到全屏错误页。
            setState(() {
              _error = '$e';
            });
          }
        }
      } finally {
        _loadInFlight = false;
      }
    });
  }

  /// 是否属于"任务不在 aria2 session 中"语义的错误。
  ///
  /// - FFI 层：`Aria2RpcException` code == -1006 (`ARIA2_FFI_ERR_NOT_FOUND`)。
  /// - aria2 自带 RPC：消息含 `No such download for GID`（远程模式 / 子进程模式）。
  static bool _isTaskNotFoundError(Object e) {
    if (e is Aria2RpcException) {
      if (e.code == -1006) return true;
      final lower = e.message.toLowerCase();
      if (lower.contains('no such download') || lower.contains('not found')) {
        return true;
      }
    }
    return false;
  }

  /// 从 [TaskHistoryRepository] 读 gid 对应的本地快照并合成 tellStatus 形状。
  /// 找不到 / 读取异常一律返回 null（详情页会回退到 banner 重试路径）。
  Future<Map<String, dynamic>?> _loadHistorySnapshot(String gid) async {
    try {
      final entry = await TaskHistoryRepository.findByGid(gid);
      return entry?.toDetailShape();
    } catch (e, st) {
      debugPrint('[task_detail] history fallback load failed: $e');
      debugPrintStack(stackTrace: st, label: 'task_detail history-fallback');
      return null;
    }
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
          if (st != null && resolveRevealPath(st) != null)
            IconButton(
              tooltip: l10n.openFolder,
              icon: const Icon(Icons.folder_open_outlined),
              // 历史快照模式也走这里：`TaskHistoryEntry.toDetailShape` 把
              // `files[0].path` 拼成 `dir/name`，所以 resolveRevealPath
              // 返回真实文件路径，revealPathInFileManager 找不到文件时会
              // 回退到 dirname 打开目录。
              onPressed: () => revealPathInUiWithFeedback(
                context,
                l10n,
                resolveRevealPath(st),
              ),
            ),
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
      body: st == null
          ? _DetailLoadingOrError(
              error: _error,
              l10n: l10n,
              onRetry: _scheduleLoad,
            )
          : Column(
              children: [
                // 软失败 banner：之前的实现把 `_status` 清空，三个 Tab 全
                // 不可见；现在改成上一轮成功的数据继续显示，banner 提示
                // 用户最新一次刷新失败 + 一键重试。日志已在 catch 里打到
                // debugPrint，用户从终端能看到完整异常。
                if (_error != null)
                  _DetailErrorBanner(
                    error: _error!,
                    l10n: l10n,
                    onRetry: _scheduleLoad,
                  ),
                if (_fromHistorySnapshot)
                  _HistorySnapshotBanner(l10n: l10n, gid: widget.gid),
                Expanded(
                  child: TabBarView(
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
                ),
              ],
            ),
      // 历史快照模式下不展示操作栏：aria2 已经不持有该任务，pause/unpause/
      // delete RPC 全都会以 -1006 失败；唯一仍然有效的「重试」已经放在历史
      // Tab 与上方 banner，不必在底部重复一份。
      bottomNavigationBar: (st != null && !_fromHistorySnapshot)
          ? TaskDetailActionBar(
              gid: widget.gid,
              status: st,
              onChanged: _scheduleLoad,
            )
          : null,
    );
  }
}

/// 仅在「首次加载就失败」(`_status == null`) 时显示的全屏分支：未失败时圆环，
/// 失败时卡片化错误信息 + 重试按钮。已成功加载过的情况由 [_DetailErrorBanner]
/// 覆盖，TabBarView 始终保留可用。
class _DetailLoadingOrError extends StatelessWidget {
  const _DetailLoadingOrError({
    required this.error,
    required this.l10n,
    required this.onRetry,
  });

  final String? error;
  final AppLocalizations l10n;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 36,
                  color: scheme.error,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.taskDetailLoadFailed(''),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: scheme.errorContainer.withValues(alpha: 0.3),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: SelectableText(
                    formatRpcError(l10n, Exception(error!)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 历史快照模式 banner：aria2 已不持有该任务，但本地历史里有快照。展示一条
/// 明确说明 + 「从历史中删除」/「返回任务列表」两个按钮——让用户知道当前是
/// 只读视图，并能直接擦掉这条「看上去删不掉」的历史。
class _HistorySnapshotBanner extends ConsumerWidget {
  const _HistorySnapshotBanner({required this.l10n, required this.gid});

  final AppLocalizations l10n;
  final String gid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Card(
        color: scheme.tertiaryContainer.withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              Icon(Icons.history, color: scheme.tertiary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.taskDetailHistorySnapshotBanner,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.historyDeleteTooltip,
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final removed = await confirmDeleteHistoryEntry(
                    context,
                    ref,
                    gid,
                  );
                  if (removed && context.mounted) {
                    // 历史里没了，详情页继续停留没有意义——把当前路由弹掉
                    // 回到任务列表 / 历史 Tab，刷新由 invalidate 处理。
                    Navigator.of(context).maybePop();
                  }
                },
              ),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(l10n.taskDetailBackToList),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 已有缓存数据但本轮刷新失败时显示的顶部错误条。比之前那套「直接整页错误」
/// 友好得多：用户仍能浏览旧数据 + 一键重试；错误详情在终端 `debugPrint` 里。
class _DetailErrorBanner extends StatelessWidget {
  const _DetailErrorBanner({
    required this.error,
    required this.l10n,
    required this.onRetry,
  });

  final String error;
  final AppLocalizations l10n;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Card(
        color: scheme.errorContainer.withValues(alpha: 0.45),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: scheme.error, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  formatRpcError(l10n, Exception(error)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
              TextButton(onPressed: onRetry, child: Text(l10n.retry)),
            ],
          ),
        ),
      ),
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
    // aria2 把 infoHash 放在 tellStatus 响应 top-level，不在 bittorrent 子结构里。
    // 注意：magnet 链刚加入时，aria2 已经能读出 infoHash 但 `bittorrent`（来自
    // .torrent metadata）可能还是空——这两个字段彼此独立，单独判 infoHash 即可。
    final infoHash = status['infoHash'];
    if (infoHash is String && infoHash.isNotEmpty) {
      rows.add((l10n.taskDetailFieldInfoHash, infoHash, true));
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
    } catch (e, st) {
      debugPrint(
        '[task_detail] changeOption(${widget.gid}, select-file=${indices.join(',')}) failed: $e',
      );
      debugPrintStack(stackTrace: st, label: 'task_detail changeOption');
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
