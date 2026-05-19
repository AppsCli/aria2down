import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 进行中任务数量（任务列表轮询时更新，用于导航角标）。
final taskActiveCountProvider = StateProvider<int>((ref) => 0);
