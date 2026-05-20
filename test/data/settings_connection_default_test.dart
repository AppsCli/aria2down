import 'package:aria2down/data/app_settings.dart';
import 'package:aria2down/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveConnectionMode', () {
    test('no stored key returns web=remote or native=local', () {
      expect(
        SettingsRepository.resolveConnectionMode(hasStoredMode: false),
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
