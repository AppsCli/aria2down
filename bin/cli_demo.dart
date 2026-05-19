import 'package:flutter/widgets.dart';

import 'package:aria2down/aria2/daemon/local_daemon.dart';
import 'package:aria2down/data/app_settings.dart';

/// 命令行验证：启动 aria2、`addUri` 小文件并轮询进度后退出。
///
/// 运行：`dart run bin/cli_demo.dart`
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final uri = args.isNotEmpty
      ? args.first
      : 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf';

  final daemon = await LocalDaemon.create(settings: AppSettings.defaults);
  await daemon.start();
  try {
    final gid = await daemon.client.addUri([uri]);
    // ignore: avoid_print
    print('aria2.addUri => gid=$gid');
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final st = await daemon.client.tellStatus(gid);
      final status = st['status'];
      final done = st['completedLength'];
      final total = st['totalLength'];
      // ignore: avoid_print
      print('[$i] status=$status completed=$done total=$total');
      if (status == 'complete' || status == 'error') break;
    }
  } finally {
    await daemon.stop();
  }
}
