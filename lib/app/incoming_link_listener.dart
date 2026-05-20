import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/incoming_file_loader.dart';
import '../core/incoming_link.dart';
import '../providers/pending_payload_provider.dart';

/// 监听 [AppLinks]（自定义 scheme / 系统 VIEW / 文件双击）并把链接 / 文件
/// 投递到 GoRouter `/add` 流程。
///
/// - URL/Magnet：直接构造 `/add?uri=…` 跳转，复用现有预填逻辑。
/// - .torrent / .metalink 文件：读取字节后通过 [pendingIncomingFileProvider]
///   交给 AddTaskPage 自动调用 `addTorrent` / `addMetalink`。
class IncomingLinkListener extends ConsumerStatefulWidget {
  const IncomingLinkListener({
    super.key,
    required this.router,
    required this.child,
  });

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<IncomingLinkListener> createState() =>
      _IncomingLinkListenerState();
}

class _IncomingLinkListenerState extends ConsumerState<IncomingLinkListener> {
  StreamSubscription<Uri>? _sub;
  AppLinks? _links;
  bool _initialConsumed = false;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  Future<void> _bind() async {
    try {
      _links = AppLinks();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('app_links init failed: $e');
      }
      return;
    }
    _sub = _links!.uriLinkStream.listen(
      _handleUri,
      onError: (Object e) {
        if (kDebugMode) debugPrint('app_links stream error: $e');
      },
    );
    try {
      final initial = await _links!.getInitialLink();
      if (!_initialConsumed && initial != null) {
        _initialConsumed = true;
        _handleUri(initial);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('app_links initial fetch failed: $e');
    }
  }

  Future<void> _handleUri(Uri uri) async {
    final payload = parseIncomingLink(uri);
    if (kDebugMode) {
      debugPrint('aria2down received link: $uri → ${payload.runtimeType}');
    }
    switch (payload) {
      case IncomingUris(uris: final uris):
        widget.router.go(buildAddPathFromIncoming(IncomingUris(uris)));
        break;
      case IncomingFile():
        await _handleFile(payload);
        break;
      case IncomingUnknown():
        widget.router.go('/add');
        break;
    }
  }

  Future<void> _handleFile(IncomingFile file) async {
    final bytes = await IncomingFileLoader.readBytes(file.uri);
    if (bytes == null) {
      widget.router.go('/add');
      return;
    }
    ref
        .read(pendingIncomingFileProvider.notifier)
        .offer(
          PendingFilePayload(
            bytes: bytes,
            kind: file.kind,
            fileName: file.fileName,
          ),
        );
    widget.router.go('/add');
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
