import 'package:shared_preferences/shared_preferences.dart';

import '../core/platform_hints.dart';
import 'app_settings.dart';

/// SharedPreferences 键名。
abstract final class SettingsKeys {
  static const connectionMode = 'settings.connection_mode';
  static const localEngine = 'settings.local_engine';
  static const fallbackToSubprocess = 'settings.fallback_to_subprocess';
  static const remoteRpcEndpoint = 'settings.remote_rpc_endpoint';
  static const remoteRpcSecret = 'settings.remote_rpc_secret';
  static const aria2BinaryPath = 'settings.aria2_binary_path';
  static const downloadDir = 'settings.download_directory';
  static const theme = 'settings.theme';
  static const locale = 'settings.locale';
  static const closeToTray = 'settings.close_to_tray';
  static const minimizeToTray = 'settings.minimize_to_tray';
  static const launchAtStartup = 'settings.launch_at_startup';
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
      localEngine: readLocalEngine(p.getString(SettingsKeys.localEngine)),
      fallbackToSubprocess:
          p.getBool(SettingsKeys.fallbackToSubprocess) ?? true,
      remoteRpcEndpoint: p.getString(SettingsKeys.remoteRpcEndpoint),
      remoteRpcSecret: p.getString(SettingsKeys.remoteRpcSecret),
      aria2BinaryPath: p.getString(SettingsKeys.aria2BinaryPath),
      downloadDirectoryOverride: p.getString(SettingsKeys.downloadDir),
      theme: readTheme(p.getString(SettingsKeys.theme)),
      locale: readLocale(p.getString(SettingsKeys.locale)),
      closeToTray: p.getBool(SettingsKeys.closeToTray) ?? true,
      minimizeToTray: p.getBool(SettingsKeys.minimizeToTray) ?? false,
      launchAtStartup: p.getBool(SettingsKeys.launchAtStartup) ?? false,
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
      SettingsKeys.localEngine,
      SettingsKeys.fallbackToSubprocess,
      SettingsKeys.remoteRpcEndpoint,
      SettingsKeys.remoteRpcSecret,
      SettingsKeys.aria2BinaryPath,
      SettingsKeys.downloadDir,
      SettingsKeys.theme,
      SettingsKeys.locale,
      SettingsKeys.closeToTray,
      SettingsKeys.minimizeToTray,
      SettingsKeys.launchAtStartup,
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
    await p.setString(SettingsKeys.localEngine, s.localEngine.name);
    await p.setBool(SettingsKeys.fallbackToSubprocess, s.fallbackToSubprocess);
    await _setOrRemove(p, SettingsKeys.remoteRpcEndpoint, s.remoteRpcEndpoint);
    await _setOrRemove(p, SettingsKeys.remoteRpcSecret, s.remoteRpcSecret);
    await _setOrRemove(p, SettingsKeys.aria2BinaryPath, s.aria2BinaryPath);
    await _setOrRemove(
      p,
      SettingsKeys.downloadDir,
      s.downloadDirectoryOverride,
    );
    await p.setString(SettingsKeys.theme, s.theme.name);
    await p.setString(SettingsKeys.locale, s.locale.name);
    await p.setBool(SettingsKeys.closeToTray, s.closeToTray);
    await p.setBool(SettingsKeys.minimizeToTray, s.minimizeToTray);
    await p.setBool(SettingsKeys.launchAtStartup, s.launchAtStartup);
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

  /// 首次安装：移动/Web 默认远程 RPC，桌面默认本机子进程。
  static ConnectionMode resolveConnectionMode({
    required bool hasStoredMode,
    String? storedRaw,
  }) {
    if (!hasStoredMode) {
      return shouldPreferRemoteAria2
          ? ConnectionMode.remote
          : ConnectionMode.local;
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

  /// 默认 [LocalEngine.library]，与 ADR-007（默认内嵌 libaria2）一致。
  static LocalEngine readLocalEngine(String? raw) {
    if (raw == null || raw.isEmpty) return LocalEngine.library;
    try {
      return LocalEngine.values.byName(raw);
    } catch (_) {
      return LocalEngine.library;
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
