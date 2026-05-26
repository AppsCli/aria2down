import '../aria2/client/aria2_client.dart';
import 'task_duplicate.dart';
import 'task_list_keys.dart';

/// 单条 URI 的 addUri 失败明细。`uri` 为入参原值（去重后），`error` 为底
/// 层抛出的异常实例（通常是 `Aria2RpcException` / `Aria2TransportException`）。
typedef QueueUrisFailure = ({String uri, Object error});

/// 向 aria2 入队 URI，并返回明细统计。
///
/// `errors` 列出每条 URI 与对应异常（addUri 失败时记录），调用方可决定
/// 是否对部分失败展示提示。返回值是 record 类型，新增字段不会破坏只读
/// `r.added`/`r.skipped` 的旧调用。
typedef QueueUrisResult = ({
  int added,
  int skipped,
  List<QueueUrisFailure> errors,
});

/// 入队每个 URI 为**独立任务**。
///
/// aria2 `addUri` 的语义是「同一资源的多个镜像 URL」：一次调用只创建一个
/// 任务，列表里的 URL 互为镜像。本函数面向「剪贴板 / 分享文本里多个独立
/// 链接」场景，因此对每条 URI 单独发起一次 `addUri`，保证 N 个 URL 对应
/// N 个任务。
///
/// 去重 / 过滤规则：
/// 1. 入参 `uris` 内部按规范化字符串去重（空白裁剪 + 小写），重复条目计入
///    `skipped`。这样可以避免「Add Task 页面手动粘多行相同 URL」或调用方
///    没有走 `extractDownloadUrisFromText` 时产生重复任务。
/// 2. 不符合 http/https/ftp/sftp/magnet 协议的字符串直接 skipped（防止把
///    手敲 "not-a-url" 这种垃圾投给 aria2 浪费一轮 RPC）。
/// 3. 与 aria2 已存在的 active / waiting 任务做差集，同样计入 `skipped`。
///
/// 失败容错：批量调用过程中任意一条 `addUri` 失败**不会**中断后续，错误
/// 收集进 `errors` 字段返回。调用方据此可向用户展示「3 个成功，1 个失败」
/// 这种部分摘要——之前是抛异常打断循环，调用方只能 toast 兜底，无法知道
/// 哪些已经入队。
Future<QueueUrisResult> queueUrisToAria2(
  Aria2Client client,
  List<String> uris, {
  Map<String, dynamic>? options,
}) async {
  if (uris.isEmpty) {
    return (added: 0, skipped: 0, errors: const <QueueUrisFailure>[]);
  }
  // Step 1: 入参内部去重 + 协议白名单过滤。
  final seen = <String>{};
  final unique = <String>[];
  var skipped = 0;
  for (final raw in uris) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      skipped++;
      continue;
    }
    if (!_isAcceptableForAria2(trimmed)) {
      skipped++;
      continue;
    }
    final norm = trimmed.toLowerCase();
    if (!seen.add(norm)) {
      skipped++;
      continue;
    }
    unique.add(trimmed);
  }
  if (unique.isEmpty) {
    return (added: 0, skipped: skipped, errors: const <QueueUrisFailure>[]);
  }

  // Step 2: 与现有 active / waiting 列表比对。waiting 上限与
  // `kTaskListTellWaitingMax` 对齐，避免列表上限不一致：之前 num=500 而
  // 列表页 200，>500 任务时去重可能漏检；统一到列表常量后即便 waiting
  // 队列爆量，至少与 UI 显示口径一致。
  final active = await client.tellActive(keys: kTaskListTellKeys);
  final waiting = await client.tellWaiting(
    offset: 0,
    num: kTaskListTellWaitingMax,
    keys: kTaskListTellKeys,
  );
  final existing = <Map<String, dynamic>>[...active, ...waiting];
  final (newUris, skippedExisting) = filterNewUris(existing, unique);
  skipped += skippedExisting;
  if (newUris.isEmpty) {
    return (added: 0, skipped: skipped, errors: const <QueueUrisFailure>[]);
  }

  final opts = options == null || options.isEmpty ? null : options;
  var added = 0;
  final errors = <QueueUrisFailure>[];
  for (final uri in newUris) {
    try {
      await client.addUri(<String>[uri], options: opts);
      added++;
    } catch (e) {
      errors.add((uri: uri, error: e));
    }
  }
  return (added: added, skipped: skipped, errors: errors);
}

/// 判断一条字符串是否值得发给 aria2。
///
/// 与 [`extractDownloadUrisFromText` 中 `_isValidDownloadUri`] 同步：magnet
/// 必须含 `btih`，其余必须解析出 scheme + host 且 scheme 在白名单。
///
/// 故意保持「比较宽松」：用户偶尔会粘 `http://10.0.0.1`（无 path）或带
/// 特殊字符的查询串，这里只拦明显无效（缺协议、空 host）。
bool _isAcceptableForAria2(String raw) {
  if (raw.toLowerCase().startsWith('magnet:?')) {
    return raw.toLowerCase().contains('btih');
  }
  final u = Uri.tryParse(raw);
  if (u == null || !u.hasScheme || u.host.isEmpty) return false;
  return const {
    'http',
    'https',
    'ftp',
    'sftp',
  }.contains(u.scheme.toLowerCase());
}
