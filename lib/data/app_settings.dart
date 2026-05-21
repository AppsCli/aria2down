import 'package:flutter/material.dart';

/// 主题偏好（持久化枚举）。
enum AppThemePreference { system, light, dark }

/// 语言偏好。
enum AppLocalePreference { system, en, zh }

/// 与 aria2 的连接方式。
enum ConnectionMode { local, remote }

/// [ConnectionMode.local] 下进一步选择执行引擎：
/// - [library]：通过 Dart FFI 内嵌 libaria2（默认）。
/// - [subprocess]：启动外置 `aria2c` 二进制（兜底 / 调试用）。
enum LocalEngine { library, subprocess }

/// 用户可配置项（与 [SettingsRepository] 对应）。
@immutable
class AppSettings {
  const AppSettings({
    this.connectionMode = ConnectionMode.local,
    this.localEngine = LocalEngine.library,
    this.fallbackToSubprocess = true,
    this.remoteRpcEndpoint,
    this.remoteRpcSecret,
    this.aria2BinaryPath,
    this.downloadDirectoryOverride,
    this.theme = AppThemePreference.system,
    this.locale = AppLocalePreference.system,
    this.closeToTray = true,
    this.minimizeToTray = false,
    this.launchAtStartup = false,
    this.startMinimized = false,
    this.keepAliveInBackground = true,
    this.maxConcurrentDownloads,
    this.maxConnectionPerServer,
    this.globalDownloadLimit,
    this.globalUploadLimit,
  });

  static const AppSettings defaults = AppSettings();

  final ConnectionMode connectionMode;
  final LocalEngine localEngine;
  final bool fallbackToSubprocess;
  final String? remoteRpcEndpoint;
  final String? remoteRpcSecret;
  final String? aria2BinaryPath;
  final String? downloadDirectoryOverride;
  final AppThemePreference theme;
  final AppLocalePreference locale;
  final bool closeToTray;
  final bool minimizeToTray;
  final bool launchAtStartup;

  /// 桌面：登录后自动启动应用时，是否直接隐藏到托盘而不显示主窗口。
  /// 仅当 [launchAtStartup] 同时启用时生效；用户手动启动也会沿用此设置。
  final bool startMinimized;

  /// 移动端：在系统后台运行时是否保持前台服务（Android）/ 长时后台任务（iOS）。
  /// 关闭后下载随应用进入后台被系统挂起。
  final bool keepAliveInBackground;

  final int? maxConcurrentDownloads;
  final int? maxConnectionPerServer;
  final String? globalDownloadLimit;
  final String? globalUploadLimit;

  bool get isRemote => connectionMode == ConnectionMode.remote;

  ThemeMode get themeMode => switch (theme) {
    AppThemePreference.system => ThemeMode.system,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };

  /// `null` 表示跟随系统语言。
  Locale? get localeOrNull => switch (locale) {
    AppLocalePreference.system => null,
    AppLocalePreference.en => const Locale('en'),
    AppLocalePreference.zh => const Locale('zh'),
  };

  AppSettings copyWith({
    ConnectionMode? connectionMode,
    LocalEngine? localEngine,
    bool? fallbackToSubprocess,
    String? remoteRpcEndpoint,
    bool clearRemoteRpcEndpoint = false,
    String? remoteRpcSecret,
    bool clearRemoteRpcSecret = false,
    String? aria2BinaryPath,
    bool clearAria2BinaryPath = false,
    String? downloadDirectoryOverride,
    bool clearDownloadDirectoryOverride = false,
    AppThemePreference? theme,
    AppLocalePreference? locale,
    bool? closeToTray,
    bool? minimizeToTray,
    bool? launchAtStartup,
    bool? startMinimized,
    bool? keepAliveInBackground,
    int? maxConcurrentDownloads,
    bool clearMaxConcurrentDownloads = false,
    int? maxConnectionPerServer,
    bool clearMaxConnectionPerServer = false,
    String? globalDownloadLimit,
    bool clearGlobalDownloadLimit = false,
    String? globalUploadLimit,
    bool clearGlobalUploadLimit = false,
  }) {
    return AppSettings(
      connectionMode: connectionMode ?? this.connectionMode,
      localEngine: localEngine ?? this.localEngine,
      fallbackToSubprocess: fallbackToSubprocess ?? this.fallbackToSubprocess,
      remoteRpcEndpoint: clearRemoteRpcEndpoint
          ? null
          : (remoteRpcEndpoint ?? this.remoteRpcEndpoint),
      remoteRpcSecret: clearRemoteRpcSecret
          ? null
          : (remoteRpcSecret ?? this.remoteRpcSecret),
      aria2BinaryPath: clearAria2BinaryPath
          ? null
          : (aria2BinaryPath ?? this.aria2BinaryPath),
      downloadDirectoryOverride: clearDownloadDirectoryOverride
          ? null
          : (downloadDirectoryOverride ?? this.downloadDirectoryOverride),
      theme: theme ?? this.theme,
      locale: locale ?? this.locale,
      closeToTray: closeToTray ?? this.closeToTray,
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      startMinimized: startMinimized ?? this.startMinimized,
      keepAliveInBackground:
          keepAliveInBackground ?? this.keepAliveInBackground,
      maxConcurrentDownloads: clearMaxConcurrentDownloads
          ? null
          : (maxConcurrentDownloads ?? this.maxConcurrentDownloads),
      maxConnectionPerServer: clearMaxConnectionPerServer
          ? null
          : (maxConnectionPerServer ?? this.maxConnectionPerServer),
      globalDownloadLimit: clearGlobalDownloadLimit
          ? null
          : (globalDownloadLimit ?? this.globalDownloadLimit),
      globalUploadLimit: clearGlobalUploadLimit
          ? null
          : (globalUploadLimit ?? this.globalUploadLimit),
    );
  }
}
