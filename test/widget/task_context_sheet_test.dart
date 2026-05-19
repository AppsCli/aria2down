import 'package:aria2down/features/tasks/task_context_sheet.dart';
import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Task context sheet shows view details and copy actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showTaskContextSheet(
                    ctx,
                    task: {
                      'gid': 'abc123',
                      'status': 'active',
                      'files': [
                        {
                          'uris': [
                            {'uri': 'https://example.com/file.zip'},
                          ],
                        },
                      ],
                    },
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('View details'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Copy all URIs'), findsOneWidget);
  });
}
