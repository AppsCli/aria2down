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

    test('mobile/web default is remote when unset', () {
      if (shouldPreferRemoteAria2) {
        expect(
          SettingsRepository.resolveConnectionMode(hasStoredMode: false),
          ConnectionMode.remote,
        );
      } else {
        expect(
          SettingsRepository.resolveConnectionMode(hasStoredMode: false),
          ConnectionMode.local,
        );
      }
    });
  });
}
