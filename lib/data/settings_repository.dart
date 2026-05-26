import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

/// SharedPreferences 键名。
///
/// 历史遗留键（ADR-010 之前的 aria2c 子进程相关）：
/// - `settings.local_engine` / `settings.fallback_to_subprocess` /
///   `settings.aria2_binary_path` 在升级后会保留在 SharedPreferences 里，但
///   不再被加载——下次 `save()` 时一并清掉（见 [SettingsRepository.save]）。
abstract final class SettingsKeys {
  static const connectionMode = 'settings.connection_mode';
  static const remoteRpcEndpoint = 'settings.remote_rpc_endpoint';
  static const remoteRpcSecret = 'settings.remote_rpc_secret';
  static const downloadDir = 'settings.download_directory';
  static const askDownloadDir = 'settings.ask_download_dir_each_time';
  static const theme = 'settings.theme';
  static const seedColor = 'settings.theme_seed_color_argb';
  static const locale = 'settings.locale';
  static const closeToTray = 'settings.close_to_tray';
  static const minimizeToTray = 'settings.minimize_to_tray';
  static const launchAtStartup = 'settings.launch_at_startup';
  static const startMinimized = 'settings.start_minimized';
  static const keepAliveInBackground = 'settings.keep_alive_in_background';
  static const maxConcurrent = 'settings.max_concurrent_downloads';
  static const maxConnPerServer = 'settings.max_connection_per_server';
  static const globalDownloadLimit = 'settings.global_download_limit';
  static const globalUploadLimit = 'settings.global_upload_limit';
}

/// 读写 [AppSettings]。
final class SettingsRepository {
  const SettingsRepository._();

  static Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return AppSettings(
      connectionMode: resolveConnectionMode(
        hasStoredMode: p.containsKey(SettingsKeys.connectionMode),
        storedRaw: p.getString(SettingsKeys.connectionMode),
      ),
      remoteRpcEndpoint: p.getString(SettingsKeys.remoteRpcEndpoint),
      remoteRpcSecret: p.getString(SettingsKeys.remoteRpcSecret),
      downloadDirectoryOverride: p.getString(SettingsKeys.downloadDir),
      askDownloadDirEachTime: p.getBool(SettingsKeys.askDownloadDir) ?? false,
      theme: readTheme(p.getString(SettingsKeys.theme)),
      seedColorArgb: p.getInt(SettingsKeys.seedColor),
      locale: readLocale(p.getString(SettingsKeys.locale)),
      closeToTray: p.getBool(SettingsKeys.closeToTray) ?? true,
      minimizeToTray: p.getBool(SettingsKeys.minimizeToTray) ?? false,
      launchAtStartup: p.getBool(SettingsKeys.launchAtStartup) ?? false,
      startMinimized: p.getBool(SettingsKeys.startMinimized) ?? false,
      keepAliveInBackground:
          p.getBool(SettingsKeys.keepAliveInBackground) ?? true,
      maxConcurrentDownloads: p.getInt(SettingsKeys.maxConcurrent),
      maxConnectionPerServer: p.getInt(SettingsKeys.maxConnPerServer),
      globalDownloadLimit: p.getString(SettingsKeys.globalDownloadLimit),
      globalUploadLimit: p.getString(SettingsKeys.globalUploadLimit),
    );
  }

  static Future<void> resetToDefaults() async {
    final p = await SharedPreferences.getInstance();
    for (final key in [
      SettingsKeys.connectionMode,
      // 历史遗留键（ADR-010 移除 aria2c 子进程之前）：reset 时一并清掉，
      // 避免在 SharedPreferences 里留下永远不会被加载的废数据。
      'settings.local_engine',
      'settings.fallback_to_subprocess',
      'settings.aria2_binary_path',
      SettingsKeys.remoteRpcEndpoint,
      SettingsKeys.remoteRpcSecret,
      SettingsKeys.downloadDir,
      SettingsKeys.askDownloadDir,
      SettingsKeys.theme,
      SettingsKeys.seedColor,
      SettingsKeys.locale,
      SettingsKeys.closeToTray,
      SettingsKeys.minimizeToTray,
      SettingsKeys.launchAtStartup,
      SettingsKeys.startMinimized,
      SettingsKeys.keepAliveInBackground,
      SettingsKeys.maxConcurrent,
      SettingsKeys.maxConnPerServer,
      SettingsKeys.globalDownloadLimit,
      SettingsKeys.globalUploadLimit,
    ]) {
      await p.remove(key);
    }
  }

  static Future<void> save(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(SettingsKeys.connectionMode, s.connectionMode.name);
    await _setOrRemove(p, SettingsKeys.remoteRpcEndpoint, s.remoteRpcEndpoint);
    await _setOrRemove(p, SettingsKeys.remoteRpcSecret, s.remoteRpcSecret);
    // ADR-010 之前的 aria2c 子进程相关键（settings.local_engine /
    // settings.fallback_to_subprocess / settings.aria2_binary_path）从这里
    // 主动 remove——升级时第一次 save() 就把残留废键擦掉。
    await p.remove('settings.local_engine');
    await p.remove('settings.fallback_to_subprocess');
    await p.remove('settings.aria2_binary_path');
    await _setOrRemove(
      p,
      SettingsKeys.downloadDir,
      s.downloadDirectoryOverride,
    );
    await p.setBool(SettingsKeys.askDownloadDir, s.askDownloadDirEachTime);
    await p.setString(SettingsKeys.theme, s.theme.name);
    await _setIntOrRemove(p, SettingsKeys.seedColor, s.seedColorArgb);
    await p.setString(SettingsKeys.locale, s.locale.name);
    await p.setBool(SettingsKeys.closeToTray, s.closeToTray);
    await p.setBool(SettingsKeys.minimizeToTray, s.minimizeToTray);
    await p.setBool(SettingsKeys.launchAtStartup, s.launchAtStartup);
    await p.setBool(SettingsKeys.startMinimized, s.startMinimized);
    await p.setBool(
      SettingsKeys.keepAliveInBackground,
      s.keepAliveInBackground,
    );
    await _setIntOrRemove(
      p,
      SettingsKeys.maxConcurrent,
      s.maxConcurrentDownloads,
    );
    await _setIntOrRemove(
      p,
      SettingsKeys.maxConnPerServer,
      s.maxConnectionPerServer,
    );
    await _setOrRemove(
      p,
      SettingsKeys.globalDownloadLimit,
      s.globalDownloadLimit,
    );
    await _setOrRemove(p, SettingsKeys.globalUploadLimit, s.globalUploadLimit);
  }

  /// 首次安装：Web 默认远程 RPC；移动设备默认本机内嵌库；桌面默认本机。
  static ConnectionMode resolveConnectionMode({
    required bool hasStoredMode,
    String? storedRaw,
  }) {
    if (!hasStoredMode) {
      if (kIsWeb) return ConnectionMode.remote;
      return ConnectionMode.local;
    }
    return readConnectionMode(storedRaw);
  }

  static ConnectionMode readConnectionMode(String? raw) {
    if (raw == null || raw.isEmpty) return ConnectionMode.local;
    try {
      return ConnectionMode.values.byName(raw);
    } catch (_) {
      return ConnectionMode.local;
    }
  }

  static AppThemePreference readTheme(String? raw) {
    if (raw == null || raw.isEmpty) return AppThemePreference.system;
    try {
      return AppThemePreference.values.byName(raw);
    } catch (_) {
      return AppThemePreference.system;
    }
  }

  static AppLocalePreference readLocale(String? raw) {
    if (raw == null || raw.isEmpty) return AppLocalePreference.system;
    try {
      return AppLocalePreference.values.byName(raw);
    } catch (_) {
      return AppLocalePreference.system;
    }
  }

  static Future<void> _setOrRemove(
    SharedPreferences p,
    String key,
    String? value,
  ) async {
    if (value == null || value.trim().isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, value.trim());
    }
  }

  static Future<void> _setIntOrRemove(
    SharedPreferences p,
    String key,
    int? value,
  ) async {
    if (value == null || value < 1) {
      await p.remove(key);
    } else {
      await p.setInt(key, value);
    }
  }
}
