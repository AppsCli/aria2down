import 'package:flutter/material.dart';

/// 主题偏好（持久化枚举）。
enum AppThemePreference { system, light, dark }

/// 语言偏好。
///
/// 历史：v0.4 之前只有 en / zh 两种；本次新增 10 种主流国际化语言。Flutter
/// `gen-l10n` 在 .arb 缺 key 时自动 fallback 到 template（英文），所以新增
/// 的语言**只翻译了高频核心 key**（导航 / Tab / 状态 / 对话框按钮 / 设置
/// 主标题约 30~40 项），未翻译的会显示英文。后续贡献者补全单语种 arb 即
/// 可，无需修改本枚举或路由层。
enum AppLocalePreference {
  system,
  en,
  zh,
  zhTw, // 繁体中文（台湾 / 香港）
  ja, // 日本語
  ko, // 한국어
  es, // Español
  fr, // Français
  de, // Deutsch
  ru, // Русский
  pt, // Português (do Brasil)
  ar, // العربية（RTL）
  vi, // Tiếng Việt
}

/// 与 aria2 的连接方式。
///
/// 本机模式（[local]）现在固定走 [LibraryDaemon]（FFI 内嵌 libaria2）——历史
/// 上的 aria2c 子进程兜底已经在 ADR-010 中移除：FFI 引擎在所有发布目标上都
/// 是预编译可用的；子进程额外维护一份 binary 资源、staging 脚本、CI 流程，
/// 收益已经远低于成本。
enum ConnectionMode { local, remote }

/// 用户可配置项（与 [SettingsRepository] 对应）。
@immutable
class AppSettings {
  const AppSettings({
    this.connectionMode = ConnectionMode.local,
    this.remoteRpcEndpoint,
    this.remoteRpcSecret,
    this.downloadDirectoryOverride,
    this.askDownloadDirEachTime = false,
    this.theme = AppThemePreference.system,
    this.seedColorArgb,
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
  final String? remoteRpcEndpoint;
  final String? remoteRpcSecret;
  final String? downloadDirectoryOverride;

  /// 添加新任务时是否弹出原生目录选择对话框让用户挑下载位置。
  ///
  /// - 桌面端调 `file_selector.getDirectoryPath()`，macOS sandbox 通过
  ///   `com.apple.security.files.user-selected.read-write` entitlement 自动授
  ///   权用户选中的目录读写。
  /// - 移动端因为 aria2 引擎只能写本地文件系统路径（SAF `content://` URI 无法
  ///   被 libaria2 直接消费），无法弹原生 SAF。取而代之地展示一个"沙箱内可写
  ///   目录"BottomSheet 让用户选子目录或手动输入路径。
  final bool askDownloadDirEachTime;

  final AppThemePreference theme;

  /// 用户选择的主题种子色（Material 3 `ColorScheme.fromSeed` 的种子）。
  ///
  /// - `null` → 跟随应用品牌默认（`#1565C0` 偏冷的「下载箭头蓝」）。
  /// - 非 null → 32 位 ARGB 整数。Material 3 会以该色为种子推导出整套
  ///   light / dark `ColorScheme`，所以不需要分别存浅深色板。
  ///
  /// 持久化为 `int` 而非 hex 字符串是为了避免 SharedPreferences / JSON 中
  /// 出现大小写差异和 `#` 前缀解析模糊。UI 层有十六进制输入框作为高级用户
  /// 入口。
  final int? seedColorArgb;

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
  ///
  /// 注意：繁体中文走 `Locale('zh', 'TW')` 而不是 `Locale('zh_TW')`——Flutter
  /// 的 LocalizationsDelegate 按 languageCode + countryCode 双段匹配，
  /// `zh_TW` 整体当语言码会找不到。
  Locale? get localeOrNull => switch (locale) {
    AppLocalePreference.system => null,
    AppLocalePreference.en => const Locale('en'),
    AppLocalePreference.zh => const Locale('zh'),
    AppLocalePreference.zhTw => const Locale('zh', 'TW'),
    AppLocalePreference.ja => const Locale('ja'),
    AppLocalePreference.ko => const Locale('ko'),
    AppLocalePreference.es => const Locale('es'),
    AppLocalePreference.fr => const Locale('fr'),
    AppLocalePreference.de => const Locale('de'),
    AppLocalePreference.ru => const Locale('ru'),
    AppLocalePreference.pt => const Locale('pt'),
    AppLocalePreference.ar => const Locale('ar'),
    AppLocalePreference.vi => const Locale('vi'),
  };

  AppSettings copyWith({
    ConnectionMode? connectionMode,
    String? remoteRpcEndpoint,
    bool clearRemoteRpcEndpoint = false,
    String? remoteRpcSecret,
    bool clearRemoteRpcSecret = false,
    String? downloadDirectoryOverride,
    bool clearDownloadDirectoryOverride = false,
    bool? askDownloadDirEachTime,
    AppThemePreference? theme,
    int? seedColorArgb,
    bool clearSeedColor = false,
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
      remoteRpcEndpoint: clearRemoteRpcEndpoint
          ? null
          : (remoteRpcEndpoint ?? this.remoteRpcEndpoint),
      remoteRpcSecret: clearRemoteRpcSecret
          ? null
          : (remoteRpcSecret ?? this.remoteRpcSecret),
      downloadDirectoryOverride: clearDownloadDirectoryOverride
          ? null
          : (downloadDirectoryOverride ?? this.downloadDirectoryOverride),
      askDownloadDirEachTime:
          askDownloadDirEachTime ?? this.askDownloadDirEachTime,
      theme: theme ?? this.theme,
      seedColorArgb: clearSeedColor
          ? null
          : (seedColorArgb ?? this.seedColorArgb),
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
