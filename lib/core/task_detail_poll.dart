/// 任务详情页轮询间隔：进行中更频繁，已结束更省流量。
Duration taskDetailPollInterval(String? status) {
  switch (status) {
    case 'active':
    case 'waiting':
      return const Duration(seconds: 2);
    case 'paused':
      return const Duration(seconds: 5);
    case 'complete':
    case 'error':
    case 'removed':
      return const Duration(seconds: 10);
    default:
      return const Duration(seconds: 3);
  }
}
