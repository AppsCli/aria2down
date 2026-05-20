import 'package:aria2down/aria2/config/aria2_config_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Aria2ConfigBuilder 包含 RPC 与 session 关键项', () {
    final s = Aria2ConfigBuilder(
      rpcListenPort: 16888,
      rpcSecret: 'abc',
      downloadDir: '/tmp/dl',
      sessionFilePath: '/tmp/s.session',
      logFilePath: '/tmp/a.log',
    ).build();
    expect(s, contains('enable-rpc=true'));
    expect(s, contains('rpc-listen-port=16888'));
    expect(s, contains('rpc-secret=abc'));
    expect(s, contains('input-file=/tmp/s.session'));
    expect(s, contains('dir=/tmp/dl'));
  });

  test('Aria2ConfigBuilder 默认关闭 async-dns 并写入兜底服务器', () {
    final s = Aria2ConfigBuilder(
      rpcListenPort: 1,
      rpcSecret: 'x',
      downloadDir: '/d',
      sessionFilePath: '/s',
      logFilePath: '/l',
    ).build();
    expect(s, contains('async-dns=false'));
    expect(
      s,
      contains('async-dns-server=1.1.1.1,8.8.8.8,223.5.5.5,119.29.29.29'),
    );
  });

  test('Aria2ConfigBuilder 写入限速与并发', () {
    final s = Aria2ConfigBuilder(
      rpcListenPort: 1,
      rpcSecret: 'x',
      downloadDir: '/d',
      sessionFilePath: '/s',
      logFilePath: '/l',
      maxConcurrentDownloads: 5,
      maxConnectionPerServer: 8,
      globalDownloadLimit: '1M',
      globalUploadLimit: '512K',
    ).build();
    expect(s, contains('max-concurrent-downloads=5'));
    expect(s, contains('max-connection-per-server=8'));
    expect(s, contains('max-overall-download-limit=1M'));
    expect(s, contains('max-overall-upload-limit=512K'));
  });
}
