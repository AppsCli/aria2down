import 'package:aria2down/core/platform_hints.dart';
import 'package:aria2down/data/app_settings.dart';
import 'package:aria2down/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingsRepository.resolveConnectionMode', () {
    test('uses stored value when present', () {
      expect(
        SettingsRepository.resolveConnectionMode(
          hasStoredMode: true,
          storedRaw: 'remote',
        ),
        ConnectionMode.remote,
      );
    });

    test('first install defaults: web remote, native local', () {
      final mode = SettingsRepository.resolveConnectionMode(
        hasStoredMode: false,
      );
      if (shouldPreferRemoteAria2) {
        expect(mode, ConnectionMode.remote);
      } else {
        expect(mode, ConnectionMode.local);
      }
    });
  });
}
