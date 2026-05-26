/// aria2 `tell*` 请求的 `keys` 参数，减少列表轮询流量。
///
/// 不含 `bitfield` / `pieceLength` / `numPieces` / `connections`（体积大或仅详情用），
/// 见 [kTaskDetailTellKeys]。
const kTaskListTellKeys = <String>[
  'gid',
  'status',
  'totalLength',
  'completedLength',
  'downloadSpeed',
  'uploadSpeed',
  'eta',
  'dir',
  'files',
  'bittorrent',
  'errorMessage',
  'completedTime',
];

/// 任务列表 `tellWaiting` 单次上限（过大时 RPC/JSON 解析会拖慢 UI）。
const kTaskListTellWaitingMax = 200;

/// 仅任务详情页需要的 `tellStatus` 字段（含 BT 分块进度）。
///
/// 注意 aria2 把 `infoHash` / `numSeeders` / `seeder` 放在 tellStatus
/// 响应的 top-level（而非 `bittorrent` 子结构），详情/Torrent Tab 需要这些
/// 字段才能展示对应行。
const kTaskDetailOnlyTellKeys = <String>[
  'connections',
  'pieceLength',
  'numPieces',
  'bitfield',
  'infoHash',
  'numSeeders',
  'seeder',
];

/// 任务详情轮询 `tellStatus` 所需字段。
const kTaskDetailTellKeys = <String>[
  ...kTaskListTellKeys,
  ...kTaskDetailOnlyTellKeys,
  'uploadLength',
  'followedBy',
  'following',
];

/// 写入任务历史时的最小 `tellStatus` 字段集。`infoHash` 留作 BT 历史去重
/// 与详情跳转使用，aria2 暴露在 top-level。
const kTaskHistoryTellKeys = <String>[
  'gid',
  'status',
  'totalLength',
  'completedLength',
  'dir',
  'files',
  'bittorrent',
  'errorMessage',
  'infoHash',
];
