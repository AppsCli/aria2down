import 'package:aria2down/data/app_settings.dart';
import 'package:aria2down/data/settings_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trip export JSON', () {
    const original = AppSettings(
      connectionMode: ConnectionMode.remote,
      remoteRpcEndpoint: '10.0.0.2:6800',
      remoteRpcSecret: 'secret',
      maxConcurrentDownloads: 3,
      globalDownloadLimit: '2M',
      closeToTray: false,
      launchAtStartup: true,
      startMinimized: true,
      keepAliveInBackground: false,
    );
    final json = SettingsExport.toJson(original);
    expect(json['appVersion'], isNotNull);
    expect(json['exportedAt'], isNotNull);
    final restored = SettingsExport.fromJson(json);
    expect(restored.connectionMode, ConnectionMode.remote);
    expect(restored.remoteRpcEndpoint, '10.0.0.2:6800');
    expect(restored.maxConcurrentDownloads, 3);
    expect(restored.globalDownloadLimit, '2M');
    expect(restored.closeToTray, false);
    expect(restored.launchAtStartup, true);
    expect(restored.startMinimized, true);
    expect(restored.keepAliveInBackground, false);
  });

  test('defaults: startMinimized=false / keepAliveInBackground=true', () {
    final restored = SettingsExport.fromJson(<String, dynamic>{
      'version': 1,
      'settings': <String, dynamic>{},
    });
    expect(restored.startMinimized, false);
    expect(restored.keepAliveInBackground, true);
  });
}
