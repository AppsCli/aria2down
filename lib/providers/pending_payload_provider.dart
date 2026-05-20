import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/incoming_link.dart';

/// 来自外部唤起入口、等待 AddTaskPage 自动处理的种子/Metalink 字节。
class PendingFilePayload {
  const PendingFilePayload({
    required this.bytes,
    required this.kind,
    this.fileName,
  });
  final Uint8List bytes;
  final IncomingFileKind kind;
  final String? fileName;
}

/// AddTaskPage 在首次构建时消费一次（[consume]），之后被清空。
class PendingFileNotifier extends StateNotifier<PendingFilePayload?> {
  PendingFileNotifier() : super(null);

  void offer(PendingFilePayload payload) => state = payload;

  PendingFilePayload? consume() {
    final p = state;
    state = null;
    return p;
  }
}

final pendingIncomingFileProvider =
    StateNotifierProvider<PendingFileNotifier, PendingFilePayload?>(
      (ref) => PendingFileNotifier(),
    );
