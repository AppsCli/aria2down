import 'dart:convert';
import 'dart:io';

import 'package:aria2down/aria2/daemon/local_daemon.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String?> _findAria2c() async {
  if (kIsWeb) return null;
  final env = Platform.environment['ARIA2C_PATH']?.trim();
  if (env != null && env.isNotEmpty && await File(env).exists()) {
    return env;
  }
  final result = Platform.isWindows
      ? await Process.run('where', ['aria2c'], runInShell: true)
      : await Process.run('which', ['aria2c']);
  if (result.exitCode != 0) return null;
  final line = const LineSplitter()
      .convert(result.stdout.toString().trim())
      .firstWhere((e) => e.isNotEmpty, orElse: () => '');
  if (line.isEmpty) return null;
  if (await File(line).exists()) return line;
  return null;
}

void main() {
  test(
    'LocalDaemon + addUri 从本机临时 HTTP 完成小文件下载（需 aria2c）',
    () async {
      final aria2Path = await _findAria2c();
      if (aria2Path == null) {
        markTestSkipped('未找到 aria2c：安装 aria2 或设置环境变量 ARIA2C_PATH');
        return;
      }

      final workRoot = await Directory.systemTemp.createTemp('aria2down_e2e_');
      HttpServer? server;
      LocalDaemon? daemon;

      Future<void> cleanup() async {
        try {
          await daemon?.stop(force: true);
        } catch (_) {
          /* ignore */
        }
        try {
          await server?.close(force: true);
        } catch (_) {
          /* ignore */
        }
        try {
          await workRoot.delete(recursive: true);
        } catch (_) {
          /* ignore */
        }
      }

      addTearDown(cleanup);

      const payload = 'aria2down-e2e-payload';
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

      final url = 'http://${bound.address.address}:${bound.port}/payload.txt';

      final d = LocalDaemon(
        binaryPath: aria2Path,
        stateRoot: workRoot,
        downloadDirectory: workRoot,
      );
      daemon = d;
      await d.start();

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
