import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 本机 aria2 状态目录路径（无需启动子进程）。
abstract final class LocalDaemonPaths {
  static Future<String> stateRoot() async {
    final base = await getApplicationSupportDirectory();
    return p.join(base.path, 'aria2down');
  }

  static Future<String> logFilePath() async {
    return p.join(await stateRoot(), 'state', 'aria2.log');
  }
}
