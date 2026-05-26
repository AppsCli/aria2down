import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../aria2/daemon/library_daemon.dart';
import 'aria2_daemon_provider.dart';

/// 库引擎已启用的可选 capability 集合（见 [Aria2NativeSession.getCapabilities]）。
///
/// 子进程 / 远程 daemon 走真实 aria2 RPC，所有功能等价完整 —— 返回 [_kFullCapabilitiesSet]
/// 让 UI 不显示降级提示。仅当库模式 + 旧 prebuilt 时返回真实的部分集合。
final libraryCapabilitiesProvider = FutureProvider<Set<String>>((ref) async {
  final daemon = await ref.watch(aria2DaemonProvider.future);
  if (daemon is LibraryDaemon) {
    return daemon.capabilities;
  }
  return _kFullCapabilitiesSet;
});

/// 「所有 capability 都已启用」的全集；非库引擎 daemon 不需要查询，直接返回此集合
/// 即可绕过 UI 的功能降级提示。新增能力时同步加入。
const _kFullCapabilitiesSet = <String>{
  'removeDownloadResult',
  'listReserved',
  'listDownloadResults',
  'downloadHandleExt',
};

/// 已知的可选 capability 标识——UI 用来判断缺失项。集合元素与 C++ 端
/// `aria2_ffi_get_capabilities` 输出对齐。
abstract final class LibraryCapability {
  static const removeDownloadResult = 'removeDownloadResult';
  static const listReserved = 'listReserved';
  static const listDownloadResults = 'listDownloadResults';
  static const downloadHandleExt = 'downloadHandleExt';

  /// 全集，用于「未缺失任何能力」的早退判断。
  static const all = _kFullCapabilitiesSet;
}
