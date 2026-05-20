import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 应用是否处于后台（用于移动端降低轮询频率）。
final appInBackgroundProvider = StateProvider<bool>((ref) => false);
