import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/lock/lock_screen.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/theme/theme.dart';

import 'helpers.dart';

/// OK with fewer than 4 digits says why (a live region
/// under the dots, like "The PINs don't match"), and nothing is submitted.
void main() {
  testWidgets('OK with 3 digits: "Use at least 4 digits."; the next key '
      'clears it', (tester) async {
    final done = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PinPad(
            title: 'Choose a PIN',
            onDone: (pin) async => done.add(pin),
          ),
        ),
      ),
    );
    for (final d in ['1', '2', '3']) {
      await tester.tapId('pin-key-$d');
    }
    await tester.tapId('pin-key-ok');
    expect(find.text('Use at least 4 digits.'), findsOneWidget);
    expect(done, isEmpty);
    final live = tester.getSemantics(byId('pin-error'));
    expect(live, isNotNull);

    await tester.tapId('pin-key-4');
    expect(find.text('Use at least 4 digits.'), findsNothing);
    await tester.tapId('pin-key-ok');
    expect(done, ['1234']);
  });
}
