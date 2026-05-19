import 'package:aria2down/app/daemon_error_screen.dart';
import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('DaemonErrorScreen shows retry', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const DaemonErrorScreen(error: 'test failure'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cannot connect to aria2'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
