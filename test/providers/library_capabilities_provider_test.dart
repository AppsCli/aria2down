// 验证 libraryCapabilitiesProvider 在三种 daemon 下的返回行为：
//
// 1. LibraryDaemon → 暴露真实 capability 集合（可能为空集合 = 旧 prebuilt）。
// 2. RemoteDaemon / LocalDaemon → 返回完整集合，UI 不展示降级提示。
//
// 这里不实例化真实 daemon（会拉起 native worker / Process）；用 fake daemon
// 覆盖 aria2DaemonProvider，断言 provider 路径。

import 'dart:io';

import 'package:aria2down/aria2/client/aria2_client.dart';
import 'package:aria2down/aria2/client/ws_listener.dart';
import 'package:aria2down/aria2/daemon/aria2_daemon.dart';
import 'package:aria2down/aria2/daemon/library_daemon.dart';
import 'package:aria2down/providers/aria2_daemon_provider.dart';
import 'package:aria2down/providers/library_capabilities_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LibraryDaemon 暴露真实 capability 集合（空集合 = 旧 prebuilt）', () async {
    final daemon = _FakeLibraryDaemon(const <String>{});
    final container = ProviderContainer(
      overrides: [aria2DaemonProvider.overrideWith((ref) async => daemon)],
    );
    addTearDown(container.dispose);
    final caps = await container.read(libraryCapabilitiesProvider.future);
    expect(caps, isEmpty);
  });

  test('LibraryDaemon 部分缺失 capability 时返回交集，UI 用差集判断', () async {
    final daemon = _FakeLibraryDaemon({
      LibraryCapability.removeDownloadResult,
      LibraryCapability.listReserved,
    });
    final container = ProviderContainer(
      overrides: [aria2DaemonProvider.overrideWith((ref) async => daemon)],
    );
    addTearDown(container.dispose);
    final caps = await container.read(libraryCapabilitiesProvider.future);
    expect(caps, contains(LibraryCapability.removeDownloadResult));
    expect(caps, contains(LibraryCapability.listReserved));
    expect(caps, isNot(contains(LibraryCapability.downloadHandleExt)));
    expect(caps, isNot(contains(LibraryCapability.listDownloadResults)));
    // UI 据此判断「需要降级提示」。
    final missing = LibraryCapability.all.difference(caps);
    expect(missing, {
      LibraryCapability.listDownloadResults,
      LibraryCapability.downloadHandleExt,
    });
  });

  test('非库引擎 daemon 永远返回完整 capability，不触发降级提示', () async {
    final daemon = _FakeNonLibraryDaemon();
    final container = ProviderContainer(
      overrides: [aria2DaemonProvider.overrideWith((ref) async => daemon)],
    );
    addTearDown(container.dispose);
    final caps = await container.read(libraryCapabilitiesProvider.future);
    expect(caps, equals(LibraryCapability.all));
    // 差集为空 → UI 不显示降级提示。
    expect(LibraryCapability.all.difference(caps), isEmpty);
  });
}

/// 假 LibraryDaemon：仅覆盖 capabilities getter 供 provider 路径读取。
///
/// 不启动 native worker——`extends LibraryDaemon` 调用父构造器只赋字段，无副作用。
/// 测试只需检测 `daemon is LibraryDaemon` 类型分支与 `.capabilities` 内容。
final class _FakeLibraryDaemon extends LibraryDaemon {
  _FakeLibraryDaemon(this._caps) : super(stateRoot: Directory.systemTemp);
  final Set<String> _caps;

  @override
  Set<String> get capabilities => _caps;
}

/// 假 non-LibraryDaemon：远程 / 子进程引擎在测试中等价。
class _FakeNonLibraryDaemon implements Aria2Daemon {
  @override
  int get rpcPort => 6800;
  @override
  String get rpcSecret => '';
  @override
  Uri get rpcHttpUri => Uri.parse('http://127.0.0.1:6800/jsonrpc');
  @override
  Uri get rpcWebSocketUri => Uri.parse('ws://127.0.0.1:6800/jsonrpc');
  @override
  Aria2Client get client => throw UnimplementedError();
  @override
  Aria2NotificationSource? get wsNotifier => null;
  @override
  ValueListenable<int> get connectionGeneration => ValueNotifier<int>(0);
  @override
  String? get logFilePath => null;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop({bool force = false}) async {}
}
