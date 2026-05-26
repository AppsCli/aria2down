import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 宽屏侧栏 / 底栏切换断点（与 [MainShell] 一致）。
const double kWideLayoutBreakpoint = 840;

/// 紧凑布局（单列、隐藏次要信息）断点。
const double kCompactLayoutBreakpoint = 600;

/// 当前是否为 iOS / Android 真机平台（非 Web）。
bool get isMobilePlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
}

/// 是否应展示移动端专属引导（横幅、欢迎对话等）。
bool get shouldShowMobileOnboarding => isMobilePlatform || kIsWeb;

/// 首次安装时的默认连接方式：移动/Web 曾默认远程；现移动设备支持内嵌 libaria2，默认本机。
bool get preferLocalConnectionOnFirstRun {
  if (kIsWeb) return false;
  return isMobilePlatform;
}

/// @deprecated 使用 [preferLocalConnectionOnFirstRun]。
bool get shouldPreferRemoteAria2 => !preferLocalConnectionOnFirstRun && kIsWeb;

bool isCompactLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).width < kCompactLayoutBreakpoint;
}

bool isWideLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;
}
