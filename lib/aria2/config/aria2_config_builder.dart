import 'package:path/path.dart' as p;

/// 生成写入用户目录的 `aria2.conf` 文本。
final class Aria2ConfigBuilder {
  Aria2ConfigBuilder({
    required this.rpcListenPort,
    required this.rpcSecret,
    required this.downloadDir,
    required this.sessionFilePath,
    required this.logFilePath,
    this.maxConcurrentDownloads,
    this.maxConnectionPerServer,
    this.globalDownloadLimit,
    this.globalUploadLimit,
  });

  final int rpcListenPort;
  final String rpcSecret;
  final String downloadDir;
  final String sessionFilePath;
  final String logFilePath;
  final int? maxConcurrentDownloads;
  final int? maxConnectionPerServer;
  final String? globalDownloadLimit;
  final String? globalUploadLimit;

  /// aria2 配置项使用 Unix 风格路径更稳妥（Windows 亦常可接受）。
  String _posixPath(String path) => p.normalize(path).replaceAll('\\', '/');

  String build() {
    final dir = _posixPath(downloadDir);
    final session = _posixPath(sessionFilePath);
    final log = _posixPath(logFilePath);
    final maxConn = maxConnectionPerServer ?? 16;
    final maxDl = maxConcurrentDownloads;
    final dlLimit = globalDownloadLimit?.trim();
    final ulLimit = globalUploadLimit?.trim();

    final extra = <String>[
      if (maxDl != null && maxDl > 0) 'max-concurrent-downloads=$maxDl',
      if (dlLimit != null && dlLimit.isNotEmpty)
        'max-overall-download-limit=$dlLimit',
      if (ulLimit != null && ulLimit.isNotEmpty)
        'max-overall-upload-limit=$ulLimit',
    ].join('\n');

    return '''
enable-rpc=true
rpc-listen-all=false
rpc-allow-origin-all=false
rpc-listen-port=$rpcListenPort
rpc-secret=$rpcSecret
rpc-secure=false
dir=$dir
input-file=$session
save-session=$session
save-session-interval=30
continue=true
max-connection-per-server=$maxConn
split=$maxConn
min-split-size=1M
disk-cache=64M
file-allocation=prealloc
seed-time=0
log=$log
log-level=warn
console-log-level=warn
$extra
''';
  }
}
