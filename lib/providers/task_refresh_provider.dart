import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 桌面快捷键等触发的任务列表刷新信号（递增值）。
final taskRefreshSignalProvider = StateProvider<int>((ref) => 0);
