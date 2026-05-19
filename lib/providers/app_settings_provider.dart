import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_settings.dart';
import '../data/settings_repository.dart';

/// 从磁盘加载 [AppSettings]；保存后请 `invalidate` 以触发 aria2 重启等。
final appSettingsProvider = FutureProvider<AppSettings>((ref) async {
  return SettingsRepository.load();
});
