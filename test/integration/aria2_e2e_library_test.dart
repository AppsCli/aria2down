// 库模式（内嵌 libaria2）端到端：仅在 packages/aria2_native 已链接到真实
// libaria2.a 时执行；stub-only 构建会被跳过，保持 `flutter test` 始终绿。
import 'dart:io';

import 'package:aria2_native/aria2_native.dart';
import 'package:aria2down/aria2/daemon/library_daemon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'LibraryDaemon + addUri 通过 libaria2 完成本机小文件下载（需 prebuilt libaria2.a）',
    () async {
      Aria2NativeBindings bindings;
      try {
        bindings = await Aria2NativeLoader.load();
        // 在 host Dart VM 上没有 Flutter 注册的原生符号，is_available 的
        // lookupFunction 会抛 ArgumentError（symbol not found），统一视为
        // 不可用并跳过本测试。
        if (!Aria2NativeSession.isAvailable(bindings)) {
          markTestSkipped('aria2_native 是 stub 构建（缺少 libaria2.a）');
          return;
        }
      } catch (e) {
        markTestSkipped('aria2_native 动态库不可用：$e');
        return;
      }

      final workRoot = await Directory.systemTemp.createTemp('aria2down_lib_');
      HttpServer? server;
      LibraryDaemon? daemon;

      addTearDown(() async {
        try {
          await daemon?.stop(force: true);
        } catch (_) {}
        try {
          await server?.close(force: true);
        } catch (_) {}
        try {
          await workRoot.delete(recursive: true);
        } catch (_) {}
      });

      const payload = 'aria2down-library-payload';
      final bound = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server = bound;
      bound.listen((HttpRequest request) async {
        if (request.uri.path == '/payload.txt') {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.text;
          request.response.write(payload);
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });

      final d = LibraryDaemon(stateRoot: workRoot, downloadDirectory: workRoot);
      daemon = d;
      await d.start();

      final url = 'http://${bound.address.address}:${bound.port}/payload.txt';
      final gid = await d.client.addUri([url]);

      String? statusStr;
      Map<String, dynamic>? last;
      for (var i = 0; i < 400; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        last = await d.client.tellStatus(gid);
        statusStr = last['status'] as String?;
        if (statusStr == 'complete') break;
        if (statusStr == 'error') {
          fail('aria2 任务失败: ${last['errorMessage'] ?? last}');
        }
      }
      expect(statusStr, 'complete', reason: '最后状态: $last');

      final files = last!['files'];
      expect(files, isA<List>());
      final first = Map<String, dynamic>.from((files as List).first as Map);
      final path = first['path'] as String?;
      expect(path, isNotNull);
      expect(await File(path!).exists(), isTrue);
      expect(await File(path).readAsString(), payload);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
