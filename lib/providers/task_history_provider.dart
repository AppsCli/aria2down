import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/task_history_entry.dart';
import '../data/task_history_repository.dart';

final taskHistoryProvider = FutureProvider<List<TaskHistoryEntry>>((ref) async {
  return TaskHistoryRepository.loadAll();
});
