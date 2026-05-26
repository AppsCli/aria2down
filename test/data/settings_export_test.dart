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
    // 「每次询问下载目录」默认关闭——避免老用户升级后突然变成每次都被弹窗
    // 打断。开启需要主动在设置里 opt-in。
    expect(restored.askDownloadDirEachTime, false);
    // 「主题色」默认为 null（跟随应用品牌默认）——保证升级路径里看到的色
    // 调与升级前一致。
    expect(restored.seedColorArgb, isNull);
  });

  test('round-trip askDownloadDirEachTime + downloadDirectoryOverride', () {
    const original = AppSettings(
      downloadDirectoryOverride: '/Users/me/Downloads/aria2',
      askDownloadDirEachTime: true,
    );
    final restored = SettingsExport.fromJson(SettingsExport.toJson(original));
    expect(restored.downloadDirectoryOverride, '/Users/me/Downloads/aria2');
    expect(restored.askDownloadDirEachTime, true);
  });

  test('round-trip seedColorArgb 保持原值', () {
    const original = AppSettings(
      seedColorArgb: 0xFF7E57C2, // 薰衣草紫
    );
    final restored = SettingsExport.fromJson(SettingsExport.toJson(original));
    expect(restored.seedColorArgb, 0xFF7E57C2);
  });

  test('seedColorArgb 接受 int / num / String 三种 JSON 形态', () {
    // 旧 export 可能把 ARGB 当 int 存，手编 JSON 又会写成 string；要全部兼容。
    final restoredInt = SettingsExport.fromJson(<String, dynamic>{
      'version': 1,
      'settings': {'seedColorArgb': 0xFFC62828},
    });
    expect(restoredInt.seedColorArgb, 0xFFC62828);

    final restoredString = SettingsExport.fromJson(<String, dynamic>{
      'version': 1,
      'settings': {'seedColorArgb': '${0xFFC62828}'},
    });
    expect(restoredString.seedColorArgb, 0xFFC62828);

    final restoredNum = SettingsExport.fromJson(<String, dynamic>{
      'version': 1,
      'settings': {'seedColorArgb': 0xFFC62828.toDouble()},
    });
    expect(restoredNum.seedColorArgb, 0xFFC62828);
  });

  test('seedColorArgb 接受无效字符串 → null（不破坏整次导入）', () {
    final restored = SettingsExport.fromJson(<String, dynamic>{
      'version': 1,
      'settings': {'seedColorArgb': 'not-a-color'},
    });
    expect(restored.seedColorArgb, isNull);
  });
}
