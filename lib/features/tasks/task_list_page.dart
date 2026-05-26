import 'dart:async';

import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
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
import '../../core/task_list_split.dart';
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
  ProviderSubscription<bool>? _bgListen;
  StreamSubscription<Aria2RpcNotification>? _wsSub;
  // 用 daemon 实例身份判断是否需要重绑 WS：LibraryDaemon 始终 rpcPort==0,
  // 用端口号判断会导致库模式 daemon 重启后事件流仍指向已关闭的旧 bridge。
  Aria2Daemon? _wsBoundDaemon;
  // 缓存当前 WS 是否可用，以便后台/前台切换时重启计时器仍能选对间隔。
  bool _wsConnected = false;
  TaskHistoryRecorder? _historyRecorder;
  // 跟踪 daemon 内部 client/WS 的重建代际：LibraryDaemon 重启或
  // RemoteDaemon WS 重连成功时会自增此值。同一 daemon 对象但 generation
  // 变化时，需要重绑 WS 订阅并以 _最新的_ daemon.client 重建历史记录器。
  ValueListenable<int>? _generationListenable;
  int _lastBoundGeneration = -1;

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _searchVisible = false;

  List<Map<String, dynamic>> _active = [];
  List<Map<String, dynamic>> _waiting = [];

  /// aria2 `tellStopped` 的原始返回（混合 status=complete / error / removed）。
  /// UI 上拆成「已完成」(`_completedView`) 与「已停止」(`_stoppedView`) 两
  /// 个 Tab，但 paged 加载、`onStoppedList` 历史落库、batch action 依然走
  /// 这份完整列表，避免重复拉取。
  List<Map<String, dynamic>> _stopped = [];

  /// 已完成（`status == 'complete'`）的子集，对应「已完成」Tab。
  List<Map<String, dynamic>> get _completedView =>
      filterCompletedTasks(_stopped);

  /// 真正"被停止"的子集（error / removed / 其他非 complete 状态），对应
  /// 「已停止」Tab——之前这里把"成功完成"也算进来，用户找下完的文件总要
  /// 跟一堆失败 / 取消混在一起翻。
  List<Map<String, dynamic>> get _stoppedView => filterStoppedTasks(_stopped);
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

  // Stopped 列表分页参数。
  //
  // 之前实现 `tellStopped(num: 50)` 固定上限，长期运行的实例（大量已完成任务）
  // 看不到 50 条之外的记录。改为按步长 [_stoppedPageStep] 增量加载，最高
  // [_kStoppedFetchLimitMax]——单次 RPC 解析数千条 JSON 已经够慢，再大反而
  // 拖慢列表渲染；超过上限的部分用户可去「历史」Tab 查看本地持久化的副本。
  //
  // 「已加载到末尾」由本轮 `tellStopped` 返回数量是否 < 请求数判定；该位用于
  // 隐藏「加载更多」按钮。
  static const int _kStoppedFetchInitial = 200;
  static const int _kStoppedPageStep = 200;
  static const int _kStoppedFetchLimitMax = 2000;
  int _stoppedFetchLimit = _kStoppedFetchInitial;
  bool _stoppedReachedEnd = false;

  @override
  void initState() {
    super.initState();
    // 5 个 Tab：active / waiting / completed / stopped / history。
    // 「已完成」从原本与 error/removed 混在一起的 stopped 中拆出来——
    // 用户视角下「成功完成」与「失败/被取消」是两类完全不同的任务，
    // 放一起会让用户为了找到刚下完的电影翻一堆 .torrent 报错记录。
    _tabs = TabController(length: 5, vsync: this)
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
        final gen = daemon.connectionGeneration.value;
        if (identical(_wsBoundDaemon, daemon) && _lastBoundGeneration == gen) {
          return;
        }
        // 切换到一个不同的 daemon：解绑旧 generation listener。
        if (!identical(_wsBoundDaemon, daemon)) {
          _generationListenable?.removeListener(_onConnectionGenerationBumped);
          _generationListenable = daemon.connectionGeneration
            ..addListener(_onConnectionGenerationBumped);
          _wsBoundDaemon = daemon;
        }
        _bindToDaemon(daemon);
      });
    }, fireImmediately: true);

    // 应用前台/后台切换时立刻重算轮询间隔（移动端后台降到 60s 省电）。
    _bgListen = ref.listenManual<bool>(appInBackgroundProvider, (prev, next) {
      if (prev == next || !mounted) return;
      _restartPollTimer(wsConnected: _wsConnected);
    });
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
      final stoppedRequestedNum = _stoppedFetchLimit;
      final futures = <Future<dynamic>>[
        d.client.tellActive(keys: kTaskListTellKeys),
        d.client.tellWaiting(
          offset: 0,
          num: kTaskListTellWaitingMax,
          keys: kTaskListTellKeys,
        ),
        d.client.tellStopped(
          offset: 0,
          num: stoppedRequestedNum,
          keys: kTaskListTellKeys,
        ),
        d.client.getGlobalStat(),
      ];
      if (fetchVersion) {
        futures.add(d.client.getVersion());
      }
      final results = await Future.wait(futures);
      final stopped = results[2] as List<Map<String, dynamic>>;
      await _historyRecorder?.onStoppedList(stopped);
      if (!mounted) return;
      // 返回不足请求量 || 已撞顶 → 视为没有更多数据，隐藏「加载更多」。
      final reachedEnd =
          stopped.length < stoppedRequestedNum ||
          _stoppedFetchLimit >= _kStoppedFetchLimitMax;
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
          reachedEnd == _stoppedReachedEnd &&
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
          _stoppedReachedEnd = reachedEnd;
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
    } catch (e, st) {
      // RPC 层日志已由 Aria2LoggingTransport 打印；这里补一条带 manual /
      // active count 上下文的行，便于在 console 里把"任务列表整体加载失败"
      // 与某一条具体的 tellActive/tellWaiting 错误关联起来。
      debugPrint('[task_list] _runTick(manual=$manual) failed: $e');
      debugPrintStack(stackTrace: st, label: 'task_list _runTick');
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
    } catch (e, st) {
      debugPrint('[task_list] retry addUri (${uris.length} uri) failed: $e');
      debugPrintStack(stackTrace: st, label: 'task_list retry');
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
        // 无成功添加：若有 addUri 错误优先展示真实原因（连接失败/鉴权等），
        // 否则说明全是重复 URI。
        final msg = result.errors.isNotEmpty
            ? formatRpcError(l10n, result.errors.first.error)
            : l10n.snackAllDuplicates;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }
      // 把 errors 计入 skipped 摘要，让用户知道并非全成功。
      final skippedTotal = result.skipped + result.errors.length;
      final msg = skippedTotal > 0
          ? l10n.snackAddedWithSkipped(result.added, skippedTotal)
          : (result.added == 1
                ? l10n.snackAdded
                : l10n.snackAddedCount(result.added));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      _scheduleTick(manual: true);
    } catch (e, st) {
      debugPrint('[task_list] paste-and-queue failed: $e');
      debugPrintStack(stackTrace: st, label: 'task_list paste-and-queue');
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
    } catch (e, st) {
      debugPrint('[task_list] import history failed: $e');
      debugPrintStack(stackTrace: st, label: 'task_list import-history');
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
    } catch (e, st) {
      debugPrint('[task_list] batch action failed: $e');
      debugPrintStack(stackTrace: st, label: 'task_list batch');
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
    await revealPathInUiWithFeedback(context, l10n, resolveRevealPath(task));
  }

  @override
  void dispose() {
    _generationListenable?.removeListener(_onConnectionGenerationBumped);
    _generationListenable = null;
    _daemonListen?.close();
    _bgListen?.close();
    unawaited(_wsSub?.cancel());
    _timer?.cancel();
    _tickDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _tabs.dispose();
    super.dispose();
  }

  /// daemon 内部 client/WS 被重建（LibraryDaemon 重启 / RemoteDaemon
  /// WS 重连）时调用：重新读取最新 `daemon.client` 与 `daemon.wsNotifier`
  /// 并重绑订阅。
  void _onConnectionGenerationBumped() {
    if (!mounted) return;
    final d = _wsBoundDaemon;
    if (d == null) return;
    _bindToDaemon(d);
    // 数据可能因重启滞后，主动拉取一次。
    unawaited(_scheduleTick());
  }

  /// 用给定 daemon 的最新 client/WS 绑定订阅、重建历史记录器。
  ///
  /// 调用方应保证 [daemon] == `_wsBoundDaemon`；否则 daemon 切换时调用方
  /// 需先更新 `_wsBoundDaemon` 与 generation listener 的注册关系。
  void _bindToDaemon(Aria2Daemon daemon) {
    _lastBoundGeneration = daemon.connectionGeneration.value;
    _version = null;
    unawaited(_wsSub?.cancel());
    _wsSub = null;
    _historyRecorder = TaskHistoryRecorder(daemon.client);
    final ws = daemon.wsNotifier;
    _wsConnected = ws != null;
    _restartPollTimer(wsConnected: _wsConnected);
    if (ws != null) {
      _wsSub = ws.notifications.listen((n) {
        if (!mounted) return;
        unawaited(_historyRecorder?.onNotification(n));
        _scheduleTick(debounced: true);
      });
    }
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
                        await d.client.removeTask(
                          gid,
                          status: '${t['status']}',
                        );
                      } catch (e) {
                        debugPrint('[task_list] removeTask($gid) failed: $e');
                      }
                    }
                  });
                case 'clear_stopped_results':
                  await _batchAction(() async {
                    for (final t in List<Map<String, dynamic>>.from(_stopped)) {
                      final gid = '${t['gid']}';
                      if (gid.isEmpty) continue;
                      try {
                        await d.client.removeDownloadResult(gid);
                      } catch (e) {
                        debugPrint(
                          '[task_list] removeDownloadResult($gid) failed: $e',
                        );
                      }
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
              // History tab 是第 5 个（index 4）：拆出 Completed Tab 后该
              // 索引从 3 漂移到 4。这里专属菜单（导出 / 导入历史）只在
              // 历史 Tab 可见，避免在任务列表 Tab 误触发本地历史动作。
              if (_tabs.index == 4) ...[
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
          // 「清空历史」按钮仅在 History Tab（index 4，自从 Completed Tab
          // 插入后从原本 3 漂移而来）显示——避免在其他 Tab 看到一个会
          // 永久清空本地历史的 AppBar 红按钮造成误触。
          if (_tabs.index == 4)
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
            Tab(text: '${l10n.tabCompleted} (${_completedView.length})'),
            Tab(text: '${l10n.tabStopped} (${_stoppedView.length})'),
            Tab(text: l10n.tabHistory),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_global != null)
            _GlobalStatsBar(
              stats: _global!,
              version: _version,
              compact: compact,
              wsOn: wsOn,
              onCopy: () async {
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
            ),
          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Card(
                color: Theme.of(
                  context,
                ).colorScheme.errorContainer.withValues(alpha: 0.4),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          formatRpcError(l10n, Exception(_loadError!)),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _scheduleTick(manual: true),
                        child: Text(l10n.retry),
                      ),
                    ],
                  ),
                ),
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
                    // 已完成 Tab：与「已停止」共享 tellStopped paged 数据，
                    // 因此底部 footer / 加载更多按钮也挂在这里——避免用户在
                    // 「已完成」Tab 看到的列表实际是被分页截断的，但本 Tab
                    // 却没有"加载更多"提示。
                    _buildTaskTab(
                      _filter(_completedView),
                      l10n.emptyCompleted,
                      showRetry: true,
                      stoppedTotalLoaded: _stopped.length,
                      onLoadMoreStopped: _stoppedReachedEnd
                          ? null
                          : _loadMoreStopped,
                      stoppedReachedEnd: _stoppedReachedEnd,
                    ),
                    _buildTaskTab(
                      _filter(_stoppedView),
                      l10n.emptyStopped,
                      showRetry: true,
                      stoppedTotalLoaded: _stopped.length,
                      onLoadMoreStopped: _stoppedReachedEnd
                          ? null
                          : _loadMoreStopped,
                      stoppedReachedEnd: _stoppedReachedEnd,
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
    Future<void> Function()? onLoadMoreStopped,
    bool stoppedReachedEnd = false,
    int stoppedTotalLoaded = 0,
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
        onLoadMore: onLoadMoreStopped,
        loadMoreReachedEnd: stoppedReachedEnd,
        loadMoreLoadedCount: stoppedTotalLoaded,
      ),
    );
  }

  /// 用户点击「加载更多」时把请求上限抬高一级，并立即触发一次 manual tick。
  ///
  /// 调用方负责检查 [_stoppedReachedEnd]——已到末尾时不会调用本方法。
  Future<void> _loadMoreStopped() async {
    if (_stoppedReachedEnd) return;
    final next = (_stoppedFetchLimit + _kStoppedPageStep).clamp(
      _kStoppedFetchInitial,
      _kStoppedFetchLimitMax,
    );
    if (next == _stoppedFetchLimit) return;
    setState(() {
      _stoppedFetchLimit = next;
    });
    await _scheduleTick(manual: true);
  }

  Future<void> _pauseTask(String gid) async {
    final d = ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    try {
      await d.client.pause(gid);
      unawaited(_scheduleTick());
    } catch (e) {
      // 行内按钮点击失败：Aria2LoggingTransport 已记录详细 RPC 错误，
      // 这里补一条带 gid 与操作语义的 console 行便于排查。
      debugPrint('[task_list] pause($gid) failed: $e');
    }
  }

  Future<void> _unpauseTask(String gid) async {
    final d = ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    try {
      await d.client.unpause(gid);
      unawaited(_scheduleTick());
    } catch (e) {
      debugPrint('[task_list] unpause($gid) failed: $e');
    }
  }

  Future<void> _removeTask(String gid, {String? status}) async {
    final d = ref.read(aria2DaemonProvider).value;
    if (d == null) return;
    try {
      await d.client.removeTask(gid, status: status);
      unawaited(_scheduleTick());
    } catch (e) {
      debugPrint('[task_list] removeTask($gid, status=$status) failed: $e');
    }
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
    this.onLoadMore,
    this.loadMoreReachedEnd = false,
    this.loadMoreLoadedCount = 0,
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
  final Future<void> Function(String gid, {String? status}) onRemove;

  /// stopped tab 专属：抬高 fetch limit 并重拉数据。null 时不显示 footer。
  final Future<void> Function()? onLoadMore;

  /// 已加载到末尾时显示「已加载全部」提示而不是按钮。
  final bool loadMoreReachedEnd;

  /// 给「加载更多 (已加载 N 条)」按钮显示用。
  final int loadMoreLoadedCount;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: Center(
              child: _EmptyTasksState(
                label: emptyLabel,
                onAddTask: onAddTask,
                addLabel: l10n.navAdd,
              ),
            ),
          ),
        ],
      );
    }
    final colors = Theme.of(context).colorScheme;
    final showFooter = onLoadMore != null;
    // 末尾追加 footer item 时把 itemCount + 1；不影响 separatorBuilder 的索引
    // 含义，因为 ListView.separated 的 separator 只出现在两个 item 之间。
    final totalCount = showFooter ? items.length + 1 : items.length;
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: totalCount,
      addAutomaticKeepAlives: false,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (showFooter && i == items.length) {
          return _StoppedTabFooter(
            l10n: l10n,
            loaded: loadMoreLoadedCount,
            reachedEnd: loadMoreReachedEnd,
            onLoadMore: onLoadMore,
          );
        }
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

/// stopped tab 末尾的「加载更多」 / 「已加载全部」 footer。
///
/// 用一个独立 StatefulWidget 自管 loading 状态：避免点击后整个 stopped tab
/// 都触发 setState rebuild（_TaskListView 是 StatelessWidget，无法承载局部
/// loading state），按钮反馈更轻量。
class _StoppedTabFooter extends StatefulWidget {
  const _StoppedTabFooter({
    required this.l10n,
    required this.loaded,
    required this.reachedEnd,
    required this.onLoadMore,
  });

  final AppLocalizations l10n;
  final int loaded;
  final bool reachedEnd;
  final Future<void> Function()? onLoadMore;

  @override
  State<_StoppedTabFooter> createState() => _StoppedTabFooterState();
}

class _StoppedTabFooterState extends State<_StoppedTabFooter> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    if (widget.reachedEnd) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            l10n.loadedAllStopped(widget.loaded),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: _loading
              ? null
              : () async {
                  setState(() => _loading = true);
                  try {
                    await widget.onLoadMore?.call();
                  } finally {
                    if (mounted) setState(() => _loading = false);
                  }
                },
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.expand_more),
          label: Text(
            widget.loaded > 0
                ? l10n.loadMoreStoppedWithCount(widget.loaded)
                : l10n.loadMoreStopped,
          ),
        ),
      ),
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
  final Future<void> Function(String gid, {String? status}) onRemove;

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
    final dlSpeed = int.tryParse('${t['downloadSpeed']}') ?? 0;
    final ulSpeed = int.tryParse('${t['uploadSpeed']}') ?? 0;
    final errMsg = t['errorMessage'];
    final errorText = errMsg is String && errMsg.isNotEmpty ? errMsg : null;
    final accents = Aria2downColors.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final palette = _statusPalette(status, accents);
    final percentText = total > 0
        ? '${(progress * 100).clamp(0, 100).toStringAsFixed(progress >= 1 ? 0 : 1)}%'
        : null;
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: status == 'paused' || status == 'removed'
          ? scheme.onSurfaceVariant
          : scheme.onSurface,
    );

    final tile = InkWell(
      onTap: () => context.push('/tasks/detail/$gid'),
      onLongPress: () => showTaskContextSheet(
        context,
        task: t,
        onOpenFolder: canOpen ? () => onOpenFolder(t) : null,
        onAfterAction: onAfterAction,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          compactTiles ? 10 : 12,
          8,
          compactTiles ? 10 : 12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TaskStatusBadge(palette: palette),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      ),
                      if (percentText != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          percentText,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: palette.fg,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(palette.fg),
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _StatusBadge(
                        palette: palette,
                        label: _statusLabel(l10n, status),
                      ),
                      if (dlSpeed > 0)
                        _MetaBadge(
                          icon: Icons.arrow_downward_rounded,
                          color: accents.downloadAccent,
                          text: formatSpeed(dlSpeed),
                        ),
                      if (ulSpeed > 0)
                        _MetaBadge(
                          icon: Icons.arrow_upward_rounded,
                          color: accents.uploadAccent,
                          text: formatSpeed(ulSpeed),
                        ),
                      if (eta != null)
                        _MetaBadge(
                          icon: Icons.schedule,
                          color: scheme.onSurfaceVariant,
                          text: eta,
                        ),
                      if (!compactTiles)
                        _MetaBadge(
                          icon: Icons.tag,
                          color: scheme.onSurfaceVariant,
                          text: gid,
                          monospace: true,
                        ),
                    ],
                  ),
                  if (errorText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 14,
                            color: scheme.error,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              errorText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (enableSwipeActions)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: Icon(Icons.chevron_right, color: scheme.outline),
              )
            else
              Row(
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
                    onPressed: () => onRemove(gid, status: status),
                  ),
                ],
              ),
          ],
        ),
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
      onDismissed: (_) => onRemove(gid, status: status),
      child: tile,
    );
  }
}

/// 空任务列表占位：大图标 + 标题 + 行动按钮。比朴素的 Text + Button 更有"招呼
/// 用户来添加任务"的引导感。
class _EmptyTasksState extends StatelessWidget {
  const _EmptyTasksState({
    required this.label,
    required this.onAddTask,
    required this.addLabel,
  });
  final String label;
  final VoidCallback onAddTask;
  final String addLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.download_for_offline_outlined,
            size: 44,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onAddTask,
          icon: const Icon(Icons.add),
          label: Text(addLabel),
        ),
      ],
    );
  }
}

/// 任务状态对应的色板（前景色 + 表面色）。
class _StatusPalette {
  const _StatusPalette(this.fg, this.surface);
  final Color fg;
  final Color surface;
}

_StatusPalette _statusPalette(String status, Aria2downColors a) {
  switch (status) {
    case 'active':
      return _StatusPalette(a.statusActive, a.statusActiveSurface);
    case 'paused':
      return _StatusPalette(a.statusPaused, a.statusPausedSurface);
    case 'complete':
      return _StatusPalette(a.statusComplete, a.statusCompleteSurface);
    case 'error':
    case 'removed':
      return _StatusPalette(a.statusError, a.statusErrorSurface);
    case 'waiting':
    default:
      return _StatusPalette(a.statusWaiting, a.statusWaitingSurface);
  }
}

String _statusLabel(AppLocalizations l10n, String status) {
  // 复用现有 tab 标签作为状态名；缺失时回退到 RPC 原文。
  switch (status) {
    case 'active':
      return l10n.tabActive;
    case 'waiting':
      return l10n.tabWaiting;
    case 'paused':
      return l10n.statusPaused;
    case 'complete':
      return l10n.statusComplete;
    case 'error':
      return l10n.statusError;
    case 'removed':
      return l10n.statusRemoved;
    default:
      return status.isEmpty ? '—' : status;
  }
}

/// 任务行左侧的彩色圆形徽章：状态色 + 状态图标。
class _TaskStatusBadge extends StatelessWidget {
  const _TaskStatusBadge({required this.palette});
  final _StatusPalette palette;

  IconData _icon() {
    // palette 不直接携带 status——靠 fg 与 a.xxx 比对略繁琐；这里改为始终
    // 用 download icon 作占位。本应用任务都是下载，分类用色已经传达状态。
    return Icons.download_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(_icon(), color: palette.fg, size: 20),
    );
  }
}

/// 状态文字徽章（active / paused / complete...）。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.palette, required this.label});
  final _StatusPalette palette;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: palette.fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 速度 / ETA / GID 等元数据徽章：图标 + 文字，无底色，节省空间。
class _MetaBadge extends StatelessWidget {
  const _MetaBadge({
    required this.icon,
    required this.color,
    required this.text,
    this.monospace = false,
  });
  final IconData icon;
  final Color color;
  final String text;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontFeatures: monospace
                ? const [FontFeature.tabularFigures()]
                : null,
            fontFamily: monospace ? 'monospace' : null,
          ),
        ),
      ],
    );
  }
}

/// 任务列表顶部的全局速率 / 计数横栏。
///
/// 视觉重设计：
/// - 左右两个 `_SpeedTile`（下载 / 上传），分别带方向图标 + 大号数字 + 单位。
/// - 中间一道纵向分隔，让两列对比清晰。
/// - 紧凑模式（窄屏）下隐藏右侧任务计数 chip 与 aria2 版本号，把空间让给速率。
/// - 整条栏目可点击 → 把扩展统计文本复制到剪贴板（继承旧行为）。
/// - 底部一行是 WS / 轮询状态指示，去掉了原来左 16 padding 后的孤立小字。
class _GlobalStatsBar extends StatelessWidget {
  const _GlobalStatsBar({
    required this.stats,
    required this.version,
    required this.compact,
    required this.wsOn,
    required this.onCopy,
  });

  final GlobalStatView stats;
  final Map<String, dynamic>? version;
  final bool compact;
  final bool wsOn;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final accents = Aria2downColors.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Card(
        color: scheme.surfaceContainerHigh,
        child: InkWell(
          onTap: onCopy,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(
                        child: _SpeedTile(
                          icon: Icons.arrow_downward_rounded,
                          accent: accents.downloadAccent,
                          label: l10n.tabActive,
                          value: stats.downFmt,
                          compact: compact,
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                      Expanded(
                        child: _SpeedTile(
                          icon: Icons.arrow_upward_rounded,
                          accent: accents.uploadAccent,
                          label: l10n.tabHistory,
                          value: stats.upFmt,
                          compact: compact,
                          rightAligned: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    // chips 区：可横向滚动，避免在极窄屏被挤出。
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _StatsChip(
                              icon: Icons.play_circle_outline,
                              label: l10n.tabActive,
                              count: stats.numActive,
                              color: accents.statusActive,
                              surface: accents.statusActiveSurface,
                            ),
                            const SizedBox(width: 6),
                            _StatsChip(
                              icon: Icons.hourglass_top_outlined,
                              label: l10n.tabWaiting,
                              count: stats.numWaiting,
                              color: scheme.tertiary,
                              surface: scheme.tertiaryContainer,
                            ),
                            const SizedBox(width: 6),
                            _StatsChip(
                              icon: Icons.check_circle_outline,
                              label: l10n.tabStopped,
                              count: stats.numStopped,
                              color: accents.statusComplete,
                              surface: accents.statusCompleteSurface,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ConnectionPill(wsOn: wsOn),
                    if (!compact && version != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        l10n.aria2Version('${version!['version'] ?? ''}'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 速率 tile：图标 + 数字 + 单位。
class _SpeedTile extends StatelessWidget {
  const _SpeedTile({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    required this.compact,
    this.rightAligned = false,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final bool compact;
  final bool rightAligned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 解析 formatSpeed 输出（例如 "1.5 MB/s"）：把数字部分加大、单位变小。
    final m = RegExp(r'^(.+?)\s*([A-Za-z/]+)$').firstMatch(value);
    final number = m?.group(1) ?? value;
    final unit = m?.group(2) ?? '';
    final children = <Widget>[
      Icon(icon, color: accent, size: compact ? 22 : 24),
      const SizedBox(width: 8),
      Column(
        crossAxisAlignment: rightAligned
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: number,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: accent,
                    height: 1.0,
                  ),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: accent.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ];
    return Padding(
      padding: rightAligned
          ? const EdgeInsets.only(left: 16)
          : const EdgeInsets.only(right: 16),
      child: Row(
        mainAxisAlignment: rightAligned
            ? MainAxisAlignment.start
            : MainAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// 任务计数 chip：图标 + 标签 + 数字。
class _StatsChip extends StatelessWidget {
  const _StatsChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.surface,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// WebSocket 状态指示：绿点 + "已连接" 或 灰点 + "轮询"。
class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.wsOn});

  final bool wsOn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final accents = Aria2downColors.of(context);
    final on = wsOn;
    final color = on ? accents.statusComplete : scheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          on ? l10n.wsConnected : l10n.wsPolling,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
