/// 任务列表排序（aria2 `tell*` 返回的 Map）。
int taskDownloadSpeed(Map<String, dynamic> task) =>
    int.tryParse('${task['downloadSpeed']}') ?? 0;

int taskCompletedTime(Map<String, dynamic> task) =>
    int.tryParse('${task['completedTime']}') ?? 0;

void sortActiveByDownloadSpeed(List<Map<String, dynamic>> tasks) {
  tasks.sort((a, b) => taskDownloadSpeed(b).compareTo(taskDownloadSpeed(a)));
}

void sortStoppedByCompletedTimeDesc(List<Map<String, dynamic>> tasks) {
  tasks.sort((a, b) => taskCompletedTime(b).compareTo(taskCompletedTime(a)));
}
