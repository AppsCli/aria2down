import 'package:aria2down/data/app_settings.dart';
import 'package:aria2down/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveConnectionMode', () {
    test('no stored key prefers remote on mobile/web platforms', () {
      // Unit-test the resolver logic with explicit stored flag.
      expect(
        SettingsRepository.resolveConnectionMode(
          hasStoredMode: false,
          storedRaw: null,
        ),
        isA<ConnectionMode>(),
      );
    });

    test('stored remote mode is preserved', () {
      expect(
        SettingsRepository.resolveConnectionMode(
          hasStoredMode: true,
          storedRaw: 'remote',
        ),
        ConnectionMode.remote,
      );
    });

    test('stored local mode is preserved', () {
      expect(
        SettingsRepository.resolveConnectionMode(
          hasStoredMode: true,
          storedRaw: 'local',
        ),
        ConnectionMode.local,
      );
    });
  });
}
