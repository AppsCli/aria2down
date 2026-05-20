import 'uri_utils.dart';

/// 来自操作系统的「外部唤起」事件解析结果。
///
/// 支持来源（[parseIncomingLink]）：
/// - 自定义 scheme：`aria2down://add?uri=…`、`aria2down://add?uris=…`、
///   `aria2down://magnet?xt=…`、`aria2down:<encoded-url>`。
/// - Web/磁力：`http(s)://…`、`ftp://…`、`magnet:?xt=…`（由系统 VIEW Intent 或 macOS Apple Event 投递）。
/// - 分享文本：通过 `text` 形参（Android `ACTION_SEND`）传入任意文本，从中提取链接。
/// - 文件：`file:///…/abc.torrent`、`content://…`（由 [IncomingLinkKind.torrentFile]
///   / [IncomingLinkKind.metalinkFile] 表示，调用方需要进一步读取字节）。
sealed class IncomingLinkPayload {
  const IncomingLinkPayload();
}

/// 一条或多条可直接交给 aria2 的下载链接。
class IncomingUris extends IncomingLinkPayload {
  const IncomingUris(this.uris);
  final List<String> uris;
}

/// 需要读取字节后再调用 `addTorrent` / `addMetalink` 的本地/内容文件。
enum IncomingFileKind { torrent, metalink }

class IncomingFile extends IncomingLinkPayload {
  const IncomingFile({required this.uri, required this.kind, this.fileName});

  /// 原始 URI（`file://…` 或 Android `content://…`）。
  final String uri;
  final IncomingFileKind kind;
  final String? fileName;
}

/// 无法识别的入参；调用方可弹窗或忽略。
class IncomingUnknown extends IncomingLinkPayload {
  const IncomingUnknown(this.raw);
  final String raw;
}

const String kAriaScheme = 'aria2down';

/// 应用内统一入口：把外部 URI / 分享文本 翻译为 [IncomingLinkPayload]。
///
/// `text` 参数用于 `ACTION_SEND`（Android）或 macOS Services 等仅给文本的入口。
IncomingLinkPayload parseIncomingLink(Uri? uri, {String? text}) {
  if (uri == null && (text == null || text.trim().isEmpty)) {
    return const IncomingUnknown('');
  }

  if (uri == null) {
    final uris = extractDownloadUrisFromText(text!);
    return uris.isEmpty ? IncomingUnknown(text) : IncomingUris(uris);
  }

  // 自定义 scheme：aria2down://...
  if (uri.scheme.toLowerCase() == kAriaScheme) {
    return _parseAriaScheme(uri);
  }

  // 磁力链：magnet:?xt=urn:btih:...
  if (uri.scheme.toLowerCase() == 'magnet') {
    final raw = uri.toString();
    return IncomingUris([raw]);
  }

  // 直接 Web 链接（系统 VIEW 转发到我们）：仅采纳协议白名单。
  final lower = uri.scheme.toLowerCase();
  if (lower == 'http' ||
      lower == 'https' ||
      lower == 'ftp' ||
      lower == 'sftp') {
    return IncomingUris([uri.toString()]);
  }

  // 本地/内容文件
  if (lower == 'file' || lower == 'content') {
    final name = _basenameFromUri(uri);
    final lowerName = name.toLowerCase();
    if (lowerName.endsWith('.torrent')) {
      return IncomingFile(
        uri: uri.toString(),
        kind: IncomingFileKind.torrent,
        fileName: name,
      );
    }
    if (lowerName.endsWith('.metalink') ||
        lowerName.endsWith('.meta4') ||
        lowerName.endsWith('.metalink4')) {
      return IncomingFile(
        uri: uri.toString(),
        kind: IncomingFileKind.metalink,
        fileName: name,
      );
    }
    // Android content:// 经常没有扩展名，留给调用方再处理。
    return IncomingFile(
      uri: uri.toString(),
      kind: IncomingFileKind.torrent,
      fileName: name.isEmpty ? null : name,
    );
  }

  // 其它 scheme 兜底：当作文本提取一次。
  final extracted = extractDownloadUrisFromText(uri.toString());
  if (extracted.isNotEmpty) return IncomingUris(extracted);
  return IncomingUnknown(uri.toString());
}

IncomingLinkPayload _parseAriaScheme(Uri uri) {
  // aria2down://add?uri=...&uris=...
  //   host  ─┘    └── 通常 'add'，也支持 'magnet'/'open'/为空
  final host = uri.host.toLowerCase();
  final out = <String>[];

  // uri / uris 查询参数（与 in-app 深链一致）。
  final single = uri.queryParameters['uri'];
  if (single != null && single.trim().isNotEmpty) {
    final decoded = _safeDecode(single.trim());
    if (decoded.isNotEmpty) out.add(decoded);
  }
  final multi = uri.queryParameters['uris'];
  if (multi != null && multi.trim().isNotEmpty) {
    for (final line in multi.split(RegExp(r'[\r\n]+'))) {
      final decoded = _safeDecode(line.trim());
      if (decoded.isNotEmpty) out.add(decoded);
    }
  }
  // 备选键：url（部分浏览器扩展习惯写法）。
  final url = uri.queryParameters['url'];
  if (url != null && url.trim().isNotEmpty) {
    final decoded = _safeDecode(url.trim());
    if (decoded.isNotEmpty) out.add(decoded);
  }

  // host == 'magnet'：把 query 重组为标准磁力链。
  if (host == 'magnet' && uri.query.isNotEmpty) {
    out.add('magnet:?${uri.query}');
  }

  // 任意位置裸链兜底：例如 aria2down://https%3A%2F%2Fexample.com%2Fa.zip
  if (out.isEmpty) {
    final raw = uri.toString();
    final body = raw
        .substring(kAriaScheme.length + 1)
        .replaceAll(RegExp(r'^/+'), '');
    if (body.isNotEmpty) {
      final decoded = _safeDecode(body);
      out.addAll(extractDownloadUrisFromText(decoded));
    }
  }

  // 仍为空（例如 aria2down://），返回 Unknown 让 UI 仅打开新建页。
  if (out.isEmpty) {
    return const IncomingUnknown('');
  }
  // 二次过滤：仅保留可被 aria2 接受的链接。
  final filtered = extractDownloadUrisFromText(out.join('\n'));
  return filtered.isEmpty
      ? IncomingUnknown(uri.toString())
      : IncomingUris(filtered);
}

String _safeDecode(String raw) {
  try {
    return Uri.decodeComponent(raw);
  } catch (_) {
    return raw;
  }
}

String _basenameFromUri(Uri uri) {
  if (uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.last;
  }
  return uri.toString().split('/').last;
}

/// 把 [IncomingUris] 渲染为 GoRouter 跳转用的 `/add?...` 路径。
String buildAddPathFromIncoming(IncomingUris payload) {
  if (payload.uris.isEmpty) return '/add';
  if (payload.uris.length == 1) {
    return '/add?uri=${Uri.encodeComponent(payload.uris.single)}';
  }
  return '/add?uris=${Uri.encodeComponent(payload.uris.join('\n'))}';
}
