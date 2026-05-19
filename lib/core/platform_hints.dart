import 'package:flutter/foundation.dart';

/// 当前平台是否应默认引导「远程 RPC」而非本机 aria2。
bool get shouldPreferRemoteAria2 {
  if (kIsWeb) return true;
  return defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
}
