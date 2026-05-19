/// aria2 `tell*` 请求的 `keys` 参数，减少列表轮询流量。
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
  'connections',
  'pieceLength',
  'numPieces',
  'bitfield',
];

/// 任务详情轮询 `tellStatus` 所需字段。
const kTaskDetailTellKeys = <String>[
  ...kTaskListTellKeys,
  'uploadLength',
  'followedBy',
  'following',
];

/// 写入任务历史时的最小 `tellStatus` 字段集。
const kTaskHistoryTellKeys = <String>[
  'gid',
  'status',
  'totalLength',
  'completedLength',
  'dir',
  'files',
  'bittorrent',
  'errorMessage',
];
