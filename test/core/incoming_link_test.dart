import 'package:aria2down/core/incoming_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseIncomingLink', () {
    test('aria2down://add?uri=… 单链接', () {
      const raw =
          'aria2down://add?uri=https%3A%2F%2Fexample.com%2Ffile.zip';
      final p = parseIncomingLink(Uri.parse(raw));
      expect(p, isA<IncomingUris>());
      expect((p as IncomingUris).uris, ['https://example.com/file.zip']);
    });

    test('aria2down://add?uris=… 多链接（换行编码）', () {
      final raw =
          'aria2down://add?uris=${Uri.encodeComponent('https://a/1.zip\nhttps://b/2.zip')}';
      final p = parseIncomingLink(Uri.parse(raw));
      expect(p, isA<IncomingUris>());
      expect((p as IncomingUris).uris, [
        'https://a/1.zip',
        'https://b/2.zip',
      ]);
    });

    test('aria2down://magnet?xt=… 重组磁力', () {
      const raw = 'aria2down://magnet?xt=urn:btih:abcdef0123456789';
      final p = parseIncomingLink(Uri.parse(raw));
      expect(p, isA<IncomingUris>());
      expect((p as IncomingUris).uris.single,
          'magnet:?xt=urn:btih:abcdef0123456789');
    });

    test('直接 magnet 链', () {
      const raw = 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567';
      final p = parseIncomingLink(Uri.parse(raw));
      expect(p, isA<IncomingUris>());
      expect((p as IncomingUris).uris.single, raw);
    });

    test('直接 https 链（系统 VIEW 转交）', () {
      const raw = 'https://example.com/setup.exe';
      final p = parseIncomingLink(Uri.parse(raw));
      expect(p, isA<IncomingUris>());
      expect((p as IncomingUris).uris, [raw]);
    });

    test('file:// .torrent 识别为 IncomingFile', () {
      const raw = 'file:///tmp/sample.torrent';
      final p = parseIncomingLink(Uri.parse(raw));
      expect(p, isA<IncomingFile>());
      expect((p as IncomingFile).kind, IncomingFileKind.torrent);
      expect(p.fileName, 'sample.torrent');
    });

    test('file:// .metalink 识别为 IncomingFile', () {
      const raw = 'file:///tmp/example.metalink';
      final p = parseIncomingLink(Uri.parse(raw));
      expect(p, isA<IncomingFile>());
      expect((p as IncomingFile).kind, IncomingFileKind.metalink);
    });

    test('content:// 无扩展名按 torrent 兜底', () {
      const raw = 'content://media/external/file/123';
      final p = parseIncomingLink(Uri.parse(raw));
      expect(p, isA<IncomingFile>());
      expect((p as IncomingFile).kind, IncomingFileKind.torrent);
    });

    test('分享文本提取多链接', () {
      const text =
          'check these:\nhttps://example.com/a.zip and magnet:?xt=urn:btih:abc123';
      final p = parseIncomingLink(null, text: text);
      expect(p, isA<IncomingUris>());
      final uris = (p as IncomingUris).uris;
      expect(uris.any((u) => u.startsWith('https://example.com/a.zip')), isTrue);
      expect(uris.any((u) => u.startsWith('magnet:?')), isTrue);
    });

    test('未识别返回 IncomingUnknown', () {
      final p = parseIncomingLink(Uri.parse('aria2down://'));
      expect(p, isA<IncomingUnknown>());
    });

    test('无效 scheme 不接受', () {
      final p = parseIncomingLink(Uri.parse('javascript:alert(1)'));
      expect(p, isA<IncomingUnknown>());
    });

    test('aria2down://?url= 备选键', () {
      const raw =
          'aria2down://add?url=https%3A%2F%2Fcdn.example%2Fb.iso';
      final p = parseIncomingLink(Uri.parse(raw));
      expect(p, isA<IncomingUris>());
      expect((p as IncomingUris).uris, ['https://cdn.example/b.iso']);
    });
  });

  group('buildAddPathFromIncoming', () {
    test('单链接 -> /add?uri=…', () {
      final path = buildAddPathFromIncoming(const IncomingUris([
        'https://example.com/a.zip',
      ]));
      expect(path, '/add?uri=https%3A%2F%2Fexample.com%2Fa.zip');
    });

    test('多链接 -> /add?uris=…', () {
      final path = buildAddPathFromIncoming(const IncomingUris([
        'https://a/1',
        'https://b/2',
      ]));
      expect(path, startsWith('/add?uris='));
      final decoded = Uri.decodeComponent(path.split('=').last);
      expect(decoded.split('\n'), ['https://a/1', 'https://b/2']);
    });

    test('空数组 -> /add', () {
      expect(buildAddPathFromIncoming(const IncomingUris([])), '/add');
    });
  });
}
