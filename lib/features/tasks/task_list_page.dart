import 'dart:async';

import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../aria2/client/aria2_client.dart' show GlobalStat;
import '../../aria2/client/ws_listener.dart';
import '../../aria2/daemon/aria2_daemon.dart';
import '../../core/eta_format.dart';
import '../../core/format_utils.dart';
import '../../core/platform_hints.dart';
import '../../core/reveal_path.dart';
import '../../core/app_deep_link.dart';
import '../../core/rpc_error_message.dart';
import '../../core/task_export.dart';
import '../../core/task_history_export.dart';
import '../../core/task_list_keys.dart';
import '../../core/uri_utils.dart';
import '../../core/task_history_recorder.dart';
import '../../core/task_list_sort.dart';
import '../../data/models/task_history_entry.dart';
import '../../providers/app_background_provider.dart';
import '../../providers/aria2_daemon_provider.dart';
import '../../core/queue_uris.dart';
import '../../core/task_history_import.dart';
import '../../providers/task_badge_provider.dart';
import '../../providers/task_history_provider.dart';
import '../../providers/task_refresh_provider.dart';
import 'task_context_sheet.dart';
import 'task_history_tab.dart';

class TaskListPage extends ConsumerStatefulWidget {
  const TaskListPage({super.key});

  @override
  ConsumerState<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends ConsumerState<TaskListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Timer? _timer;
  Timer? _searchDebounce;
  int _pollIntervalSec = 8;
  ProviderSubscription<AsyncValue<Aria2Daemon>>? _daemonListen;
  StreamSubscription<Aria2RpcNotification>? _wsSub;
  int? _wsBoundPort;
  TaskHistoryRecorder? _historyRecorder;

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _searchVisible = false;

  List<Map<String, dynamic>> _active = [];
  List<Map<String, dynamic>> _waiting = [];
  List<Map<String, dynamic>> _stopped = [];
  GlobalStatView? _global;
  Map<String, dynamic>? _version;
  String? _loadError;
  bool _refreshing = false;
  bool _tickInFlight = false;
  bool _tickCoalesce = false;
  bool _tickCoalesceManual = false;
  Timer? _tickDebounce;
  final _manualTickWaiters = <Completer<void>>[];
  int? _activeSig;
  int? _waitingSig;
  int? _stoppedSig;
  int? _globalSig;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _scheduleTick();
    _restartPollTimer(wsConnected: false);

    ref.listenManual(taskRefreshSignalProvider, (prev, next) {
      if (prev != next) _scheduleTick(manual: true);
    });

    _daemonListen = ref.listenManual(aria2DaemonProvider, (prev, next) {
      next.whenData((daemon) {
        if (!mounted) return;
        if (_wsBoundPort == daemon.rpcPort) return;
        _wsBoundPort = daemon.rpcPort;
        _version = null;
        unawaited(_wsSub?.cancel());
        _wsSub = null;
        _historyRecorder = TaskHistoryRecorder(daemon.client);
        final ws = daemon.wsNotifier;
        _restartPollTimer(wsConnected: ws != null);
        if (ws != null) {
          _wsSub = ws.notifications.listen((n) {
            if (!mounted) return;
            unawaited(_historyRecorder?.onNotification(n));
            _scheduleTick(debounced: true);
          });
        }
      });
    }, fireImmediately: true);
  }

  void _restartPollTimer({required bool wsConnected}) {
    final inBackground = ref.read(appInBackgroundProvider);
    final sec = inBackground && isMobilePlatform ? 60 : (wsConnected ? 30 : 8);
    if (sec == _pollIntervalSec && _timer != null) return;
    _pollIntervalSec = sec;
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: _pollIntervalSec), (_) {
      _scheduleTick();
    });
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> items) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((t) {
      final name = pickTaskName(t).toLowerCase();
      final gid = '${t['gid']}'.toLowerCase();
      return name.contains(q) || gid.contains(q);
    }).toList();
  }

  Future<void> _scheduleTick({bool manual = false, bool debounced = false}) {
    if (debounced && !manual) {
      _tickDebounce?.cancel();
      _tickDebounce = Timer(const Duration(milliseconds: 400), () {
        _tickDebounce = null;
        if (mounted) unawaited(_scheduleTick());
      });
      return Future<void>.value();
    }
    if (_tickInFlight) {
      _tickCoalesce = true;
      if (manual) {
        _tickCoalesceManual = true;
        final waiter = Completer<void>();
        _manualTickWaiters.add(waiter);
        return waiter.future;
      }
      return Future<void>.value();
    }
    return _runTick(manual: manual);
  }

  void _completeManualTickWaiters() {
    for (final waiter in _manualTickWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _manualTickWaiters.clear();
  }

  Future<void> _runTick({required bool manual}) async {
    _tickInFlight = true;
    if (manual && mounted) setState(() => _refreshing = true);
    try {
      final async = ref.read(aria2DaemonProvider);
      final d = async.value;
      if (d == null || !mounted) {
        if (manual && mounted) setState(() => _refreshing = false);
        return;
      }
      final fetchVersion = _version == null || manual;
      final futures = <Future<dynamic>>[
        d.client.tellActive(keys: kTaskListTellKeys),
        d.client.tellWaiting(
          offset: 0,
          num: kTaskListTellWaitingMax,
          keys: kTaskListTellKeys,
        ),
        d.client.tellStopped(offset: 0, num: 50, keys: kTaskListTellKeys),
        d.client.getGlobalStat(),
      ];
      if (fetchVersion) {
        futures.add(d.client.getVersion());
      }
      final results = await Future.wait(futures);
      final stopped = results[2] as List<Map<String, dynamic>>;
      await _historyRecorder?.onStoppedList(stopped);
      if (!mounted) return;
      final active = List<Map<String, dynamic>>.from(
        results[0] as List<Map<String, dynamic>>,
      );
      final waiting = results[1] as List<Map<String, dynamic>>;
      final stoppedSorted = List<Map<String, dynamic>>.from(stopped);
      sortActiveByDownloadSpeed(active);
      sortStoppedByCompletedTimeDesc(stoppedSorted);
      final version = fetchVersion
          ? results[4] as Map<String, dynamic>
          : _version;
      final newGlobal = GlobalStatView.from(results[3] as GlobalStat);

      final activeSig = _taskListSignature(active);
      final waitingSig = _taskListSignature(waiting);
      final stoppedSig = _taskListSignature(stoppedSorted);
      final globalSig = newGlobal.signature;
      final unchanged =
          _loadError == null &&
          activeSig == _activeSig &&
          waitingSig == _waitingSig &&
          stoppedSig == _stoppedSig &&
          globalSig == _globalSig &&
          (!fetchVersion || identical(version, _version));

      if (unchanged) {
        if (manual && mounted) setState(() => _refreshing = false);
      } else {
        setState(() {
          _loadError = null;
          _active = active;
          _waiting = waiting;
          _stopped = stoppedSorted;
          _activeSig = activeSig;
          _waitingSig = waitingSig;
          _stoppedSig = stoppedSig;
          _global = newGlobal;
          _globalSig = globalSig;
          _version = version;
          if (manual) _refreshing = false;
        });
      }
      final notifier = ref.read(taskActiveCountProvider.notifier);
      if (notifier.state != active.length) {
        notifier.state = active.length;
      }
      if (manual) {
        ref.invalidate(taskHistoryProvider);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = '$e';
          if (manual) _refreshing = false;
        });
      }
    } finally {
      _tickInFlight = false;
      if (_tickCoalesce && mounted) {
        final coalesceManual = _tickCoalesceManual;
        _tickCoalesce = false;
        _tickCoalesceManual = false;
        await _runTick(manual: coalesceManual);
      } else {
        _completeManualTickWaiters();
      }
    }
  }

  Future<void> _retryTask(Map<String, dynamic> task) async {
    final l10n = AppLocalizations.of(context)!;
    final uris = extractUrisFromTask(task);
    if (uris.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.snackNothingToRetry)));
      return;
    }
    final d = ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    final opts = <String, dynamic>{};
    final dir = task['dir'];
    if (dir is String && dir.isNotEmpty) {
      opts['dir'] = dir;
    }
    try {
      await d.client.addUri(uris, options: opts.isEmpty ? null : opts);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.snackRetryQueued)));
      }
      _scheduleTick(manual: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatRpcError(l10n, e))));
      }
    }
  }

  Future<void> _pasteAndQueueFromClipboard() async {
    final l10n = AppLocalizations.of(context)!;
    final d = ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final uris = extractDownloadUrisFromText(data?.text ?? '');
    if (uris.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.snackInvalidUrl)));
      }
      return;
    }
    try {
      final result = await queueUrisToAria2(d.client, uris);
      if (!mounted) return;
      if (result.added == 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.snackAllDuplicates)));
        return;
      }
      final msg = result.skipped > 0
          ? l10n.snackAddedWithSkipped(result.added, result.skipped)
          : (result.added == 1
                ? l10n.snackAdded
                : l10n.snackAddedCount(result.added));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      _scheduleTick(manual: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatRpcError(l10n, e))));
      }
    }
  }

  Future<void> _importHistoryFromClipboard(AppLocalizations l10n) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text?.trim();
    if (raw == null || raw.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.clipboardEmpty)));
      }
      return;
    }
    try {
      final n = await importTaskHistoryFromJson(raw);
      ref.invalidate(taskHistoryProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.historyImportDone(n))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.historyImportFailed('$e'))));
      }
    }
  }

  Future<void> _openAddFromClipboard() async {
    final l10n = AppLocalizations.of(context)!;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final uris = extractDownloadUrisFromText(data?.text ?? '');
    if (uris.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.snackInvalidUrl)));
      }
      return;
    }
    if (!mounted) return;
    context.go(buildInAppAddPathForUris(uris));
  }

  Future<void> _exportHistory(AppLocalizations l10n) async {
    final entries = await ref.read(taskHistoryProvider.future);
    final json = exportTaskHistoryJson(entries);
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.batchExportHistoryDone)));
    }
  }

  Future<void> _retryHistory(TaskHistoryEntry entry) async {
    await _retryTask(entry.toRetryTaskShape());
  }

  Future<void> _batchAction(Future<void> Function() action) async {
    final l10n = AppLocalizations.of(context)!;
    final d = ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.snackBatchDone)));
      }
      _scheduleTick(manual: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(formatRpcError(l10n, e))));
      }
    }
  }

  Future<void> _exportSnapshot(AppLocalizations l10n) async {
    final json = exportTasksSnapshot(
      active: _active,
      waiting: _waiting,
      stopped: _stopped,
      version: _version,
    );
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.batchExportTasksDone)));
    }
  }

  Future<void> _openFolder(Map<String, dynamic> task) async {
    final l10n = AppLocalizations.of(context)!;
    final path = resolveRevealPath(task);
    if (path == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.openFolderFailed)));
      return;
    }
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: path));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.openFolderWebCopied)));
      return;
    }
    final r = await revealPathInFileManager(path);
    if (!mounted) return;
    switch (r) {
      case RevealPathResult.ok:
        break;
      case RevealPathResult.unsupportedFolderOnMobile:
        await _showMobilePathSheet(path, l10n);
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

  Future<void> _showMobilePathSheet(String path, AppLocalizations l10n) async {
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

  @override
  void dispose() {
    _daemonListen?.close();
    unawaited(_wsSub?.cancel());
    _timer?.cancel();
    _tickDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final d = ref.watch(aria2DaemonProvider).value;
    final wsOn = d?.wsNotifier != null;

    final compact = isCompactLayout(context);
    final mobile = isMobilePlatform;

    return Scaffold(
      floatingActionButton: mobile
          ? FloatingActionButton(
              onPressed: () => context.go('/add'),
              tooltip: l10n.navAdd,
              child: const Icon(Icons.add),
            )
          : null,
      appBar: AppBar(
        title: _searchVisible
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.searchTasksHint,
                  border: InputBorder.none,
                ),
                onChanged: (v) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 250),
                    () {
                      if (!mounted) return;
                      if (v == _searchQuery) return;
                      setState(() => _searchQuery = v);
                    },
                  );
                },
              )
            : Text(l10n.tasksTitle),
        actions: [
          PopupMenuButton<String>(
            tooltip: l10n.tasksBatchMenu,
            onSelected: (key) async {
              final d = ref.read(aria2DaemonProvider).value;
              if (d == null) return;
              switch (key) {
                case 'pause_all':
                  await _batchAction(d.client.pauseAll);
                case 'unpause_all':
                  await _batchAction(d.client.unpauseAll);
                case 'purge_stopped':
                  await _batchAction(() async {
                    await d.client.purgeDownloadResult();
                    ref.invalidate(taskHistoryProvider);
                  });
                case 'force_pause_all':
                  await _batchAction(d.client.forcePauseAll);
                case 'remove_stopped':
                  await _batchAction(() async {
                    for (final t in List<Map<String, dynamic>>.from(_stopped)) {
                      final gid = '${t['gid']}';
                      if (gid.isEmpty) continue;
                      try {
                        await d.client.remove(gid, force: true);
                      } catch (_) {}
                    }
                  });
                case 'clear_stopped_results':
                  await _batchAction(() async {
                    for (final t in List<Map<String, dynamic>>.from(_stopped)) {
                      final gid = '${t['gid']}';
                      if (gid.isEmpty) continue;
                      try {
                        await d.client.removeDownloadResult(gid);
                      } catch (_) {}
                    }
                  });
                case 'export_snapshot':
                  await _exportSnapshot(l10n);
                case 'export_history':
                  await _exportHistory(l10n);
                case 'import_history':
                  await _importHistoryFromClipboard(l10n);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'pause_all',
                child: Text(l10n.batchPauseAll),
              ),
              PopupMenuItem(
                value: 'force_pause_all',
                child: Text(l10n.batchForcePauseAll),
              ),
              PopupMenuItem(
                value: 'unpause_all',
                child: Text(l10n.batchUnpauseAll),
              ),
              PopupMenuItem(
                value: 'purge_stopped',
                child: Text(l10n.batchPurgeStopped),
              ),
              PopupMenuItem(
                value: 'remove_stopped',
                child: Text(l10n.batchRemoveStopped),
              ),
              PopupMenuItem(
                value: 'clear_stopped_results',
                child: Text(l10n.batchClearStoppedResults),
              ),
              PopupMenuItem(
                value: 'export_snapshot',
                child: Text(l10n.batchExportTasks),
              ),
              if (_tabs.index == 3) ...[
                PopupMenuItem(
                  value: 'export_history',
                  child: Text(l10n.batchExportHistory),
                ),
                PopupMenuItem(
                  value: 'import_history',
                  child: Text(l10n.batchImportHistory),
                ),
              ],
            ],
          ),
          if (!compact) ...[
            IconButton(
              tooltip: l10n.pasteAndQueue,
              icon: const Icon(Icons.playlist_add_check),
              onPressed: _pasteAndQueueFromClipboard,
            ),
            IconButton(
              tooltip: l10n.pasteAndAdd,
              icon: const Icon(Icons.playlist_add),
              onPressed: _openAddFromClipboard,
            ),
          ],
          IconButton(
            tooltip: l10n.searchTasks,
            icon: Icon(_searchVisible ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _searchVisible = !_searchVisible;
                if (!_searchVisible) {
                  _searchCtrl.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
          if (_tabs.index == 3)
            IconButton(
              tooltip: l10n.historyClearTitle,
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => confirmClearHistory(context, ref),
            ),
          IconButton(
            tooltip: l10n.refreshTasks,
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _refreshing ? null : () => _scheduleTick(manual: true),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: '${l10n.tabActive} (${_active.length})'),
            Tab(text: '${l10n.tabWaiting} (${_waiting.length})'),
            Tab(text: '${l10n.tabStopped} (${_stopped.length})'),
            Tab(text: l10n.tabHistory),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_global != null)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: InkWell(
                onTap: () async {
                  final text = l10n.speedGlobalExtended(
                    _global!.downFmt,
                    _global!.upFmt,
                    _global!.numActive,
                    _global!.numWaiting,
                    _global!.numStopped,
                  );
                  await Clipboard.setData(ClipboardData(text: text));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l10n.snackCopied)));
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          compact
                              ? l10n.speedGlobal(
                                  _global!.downFmt,
                                  _global!.upFmt,
                                  _global!.numActive,
                                  _global!.numWaiting,
                                )
                              : l10n.speedGlobalExtended(
                                  _global!.downFmt,
                                  _global!.upFmt,
                                  _global!.numActive,
                                  _global!.numWaiting,
                                  _global!.numStopped,
                                ),
                          style: Theme.of(context).textTheme.bodyMedium,
                          maxLines: compact ? 2 : null,
                          overflow: compact ? TextOverflow.ellipsis : null,
                        ),
                      ),
                      if (!compact && _version != null)
                        Text(
                          l10n.aria2Version('${_version!['version'] ?? ''}'),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (_loadError != null)
            MaterialBanner(
              content: Text(formatRpcError(l10n, Exception(_loadError!))),
              leading: Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              actions: [
                TextButton(
                  onPressed: () => _scheduleTick(manual: true),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Text(
              wsOn ? l10n.wsConnected : l10n.wsPolling,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _buildTaskTab(
                      _filter(_active),
                      l10n.emptyActive,
                      showRetry: false,
                    ),
                    _buildTaskTab(
                      _filter(_waiting),
                      l10n.emptyWaiting,
                      showRetry: false,
                    ),
                    _buildTaskTab(
                      _filter(_stopped),
                      l10n.emptyStopped,
                      showRetry: true,
                    ),
                    TaskHistoryTab(
                      searchQuery: _searchQuery,
                      onRetry: _retryHistory,
                      onRefresh: () async {
                        ref.invalidate(taskHistoryProvider);
                        await _scheduleTick(manual: true);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskTab(
    List<Map<String, dynamic>> items,
    String emptyLabel, {
    required bool showRetry,
  }) {
    final narrow = !isWideLayout(context);
    return RefreshIndicator(
      onRefresh: () => _scheduleTick(manual: true),
      child: _TaskListView(
        items: items,
        emptyLabel: emptyLabel,
        l10n: AppLocalizations.of(context)!,
        showRetry: showRetry,
        enableSwipeActions: narrow || isMobilePlatform,
        compactTiles: isCompactLayout(context),
        onAddTask: () => context.go('/add'),
        onRetry: _retryTask,
        onOpenFolder: _openFolder,
        onAfterAction: () => _scheduleTick(),
        onPause: _pauseTask,
        onUnpause: _unpauseTask,
        onRemove: _removeTask,
      ),
    );
  }

  Future<void> _pauseTask(String gid) async {
    final d = ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    try {
      await d.client.pause(gid);
      unawaited(_scheduleTick());
    } catch (_) {}
  }

  Future<void> _unpauseTask(String gid) async {
    final d = ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    try {
      await d.client.unpause(gid);
      unawaited(_scheduleTick());
    } catch (_) {}
  }

  Future<void> _removeTask(String gid) async {
    final d = ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    try {
      await d.client.remove(gid, force: true);
      unawaited(_scheduleTick());
    } catch (_) {}
  }
}

class GlobalStatView {
  GlobalStatView({
    required this.downFmt,
    required this.upFmt,
    required this.numActive,
    required this.numWaiting,
    required this.numStopped,
  });

  factory GlobalStatView.from(GlobalStat stat) {
    return GlobalStatView(
      downFmt: formatSpeed(stat.downloadSpeed),
      upFmt: formatSpeed(stat.uploadSpeed),
      numActive: stat.numActive,
      numWaiting: stat.numWaiting,
      numStopped: stat.numStopped,
    );
  }

  final String downFmt;
  final String upFmt;
  final int numActive;
  final int numWaiting;
  final int numStopped;

  /// 用于跨轮 diff 的轻量签名（不含格式化字符串以外的数据）。
  int get signature =>
      Object.hash(downFmt, upFmt, numActive, numWaiting, numStopped);
}

/// 计算任务列表轻量签名，用于跳过无变化的 setState。
///
/// 只采样进度/状态字段，BT 大字段不参与计算（列表已不含 `bitfield`）。
int _taskListSignature(List<Map<String, dynamic>> items) {
  if (items.isEmpty) return 0;
  var hash = items.length;
  for (final t in items) {
    hash = Object.hash(
      hash,
      t['gid'],
      t['status'],
      t['totalLength'],
      t['completedLength'],
      t['downloadSpeed'],
      t['uploadSpeed'],
      t['eta'],
      t['errorMessage'],
    );
  }
  return hash;
}

class _TaskListView extends StatelessWidget {
  const _TaskListView({
    required this.items,
    required this.emptyLabel,
    required this.l10n,
    required this.showRetry,
    required this.enableSwipeActions,
    required this.compactTiles,
    required this.onAddTask,
    required this.onRetry,
    required this.onOpenFolder,
    required this.onAfterAction,
    required this.onPause,
    required this.onUnpause,
    required this.onRemove,
  });

  final List<Map<String, dynamic>> items;
  final String emptyLabel;
  final AppLocalizations l10n;
  final bool showRetry;
  final bool enableSwipeActions;
  final bool compactTiles;
  final VoidCallback onAddTask;
  final Future<void> Function(Map<String, dynamic> task) onRetry;
  final Future<void> Function(Map<String, dynamic> task) onOpenFolder;
  final VoidCallback onAfterAction;
  final Future<void> Function(String gid) onPause;
  final Future<void> Function(String gid) onUnpause;
  final Future<void> Function(String gid) onRemove;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.25,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emptyLabel),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onAddTask,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.navAdd),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    final colors = Theme.of(context).colorScheme;
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: items.length,
      addAutomaticKeepAlives: false,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final t = items[i];
        return _TaskListTile(
          key: ValueKey('${t['gid']}'),
          task: t,
          l10n: l10n,
          colors: colors,
          showRetry: showRetry,
          enableSwipeActions: enableSwipeActions,
          compactTiles: compactTiles,
          onRetry: onRetry,
          onOpenFolder: onOpenFolder,
          onAfterAction: onAfterAction,
          onPause: onPause,
          onUnpause: onUnpause,
          onRemove: onRemove,
        );
      },
    );
  }
}

class _TaskListTile extends StatelessWidget {
  const _TaskListTile({
    super.key,
    required this.task,
    required this.l10n,
    required this.colors,
    required this.showRetry,
    required this.enableSwipeActions,
    required this.compactTiles,
    required this.onRetry,
    required this.onOpenFolder,
    required this.onAfterAction,
    required this.onPause,
    required this.onUnpause,
    required this.onRemove,
  });

  final Map<String, dynamic> task;
  final AppLocalizations l10n;
  final ColorScheme colors;
  final bool showRetry;
  final bool enableSwipeActions;
  final bool compactTiles;
  final Future<void> Function(Map<String, dynamic> task) onRetry;
  final Future<void> Function(Map<String, dynamic> task) onOpenFolder;
  final VoidCallback onAfterAction;
  final Future<void> Function(String gid) onPause;
  final Future<void> Function(String gid) onUnpause;
  final Future<void> Function(String gid) onRemove;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final gid = '${t['gid']}';
    final status = '${t['status'] ?? ''}';
    final total = int.tryParse('${t['totalLength']}') ?? 0;
    final done = int.tryParse('${t['completedLength']}') ?? 0;
    final name = pickTaskName(t);
    final progress = total > 0 ? done / total : 0.0;
    final canOpen = resolveRevealPath(t) != null;
    final canRetry = showRetry && extractUrisFromTask(t).isNotEmpty;
    final eta = formatEta(t['eta']);
    final speed = int.tryParse('${t['downloadSpeed']}') ?? 0;
    final statusLine = [
      status,
      if (speed > 0) formatSpeed(speed),
      if (eta != null) eta,
    ].join(' · ');
    final errMsg = t['errorMessage'];
    final errorText = errMsg is String && errMsg.isNotEmpty ? errMsg : null;

    final tile = ListTile(
      onTap: () => context.push('/tasks/detail/$gid'),
      onLongPress: () => showTaskContextSheet(
        context,
        task: t,
        onOpenFolder: canOpen ? () => onOpenFolder(t) : null,
        onAfterAction: onAfterAction,
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            compactTiles ? statusLine : '$statusLine\n$gid',
            maxLines: compactTiles ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                errorText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.error, fontSize: 12),
              ),
            ),
          LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
        ],
      ),
      trailing: enableSwipeActions
          ? Icon(Icons.chevron_right, color: colors.outline)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canOpen)
                  IconButton(
                    tooltip: l10n.openFolder,
                    icon: const Icon(Icons.folder_open_outlined),
                    onPressed: () => onOpenFolder(t),
                  ),
                if (canRetry)
                  IconButton(
                    tooltip: l10n.retry,
                    icon: const Icon(Icons.refresh),
                    onPressed: () => onRetry(t),
                  ),
                if (status == 'active' || status == 'waiting')
                  IconButton(
                    icon: const Icon(Icons.pause),
                    onPressed: () => onPause(gid),
                  ),
                if (status == 'paused')
                  IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => onUnpause(gid),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onRemove(gid),
                ),
              ],
            ),
    );

    if (!enableSwipeActions) return tile;

    return Dismissible(
      key: ValueKey('dismiss_$gid'),
      direction: showRetry
          ? DismissDirection.endToStart
          : DismissDirection.horizontal,
      background: Container(
        color: colors.primaryContainer,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: Icon(
          status == 'paused' ? Icons.play_arrow : Icons.pause,
          color: colors.onPrimaryContainer,
        ),
      ),
      secondaryBackground: Container(
        color: colors.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline, color: colors.onErrorContainer),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (status == 'paused') {
            await onUnpause(gid);
          } else if (status == 'active' || status == 'waiting') {
            await onPause(gid);
          }
          return false;
        }
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.swipeDeleteTitle),
            content: Text(l10n.swipeDeleteMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.dialogCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.delete),
              ),
            ],
          ),
        );
        return ok ?? false;
      },
      onDismissed: (_) => onRemove(gid),
      child: tile,
    );
  }
}
