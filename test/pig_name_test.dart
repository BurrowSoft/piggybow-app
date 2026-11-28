import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:piggybow/core/local_prefs.dart';
import 'package:piggybow/features/me/me_actions.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/pig/pig_name.dart';

import 'helpers.dart';

/// Feature 1, name your pig: Me → Your pig → Name, optional, up to 20
/// characters, trimmed (empty: no name). Home shows it, small and muted,
/// above the speech box. Delete everything clears it; the export never
/// carries it (it isn't journal data).
void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Piggybow',
      packageName: 'com.burrowsoft.piggybow',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('the name as it is kept', () {
    test('trimmed; nothing left is no name', () {
      expect(normalizePigName('  Mochi  '), 'Mochi');
      expect(normalizePigName('Pink Pig'), 'Pink Pig');
      expect(normalizePigName(''), isNull);
      expect(normalizePigName('   '), isNull);
      expect(normalizePigName(null), isNull);
    });

    test('line breaks and tabs become spaces', () {
      expect(normalizePigName('Mo\nchi'), 'Mo chi');
      expect(normalizePigName('Mo\t\tchi'), 'Mo chi');
    });

    test('at most 20 characters, as a person counts them', () {
      expect(normalizePigName('A' * 25), 'A' * 20);
      // A pig emoji is one character (two UTF-16 units).
      expect(normalizePigName('🐷' * 25), '🐷' * 20);
      // Cut before a space: no space at the end.
      expect(normalizePigName('${'A' * 19} Bcd'), 'A' * 19);
    });
  });

  group('kept on this device, cleared with everything else', () {
    test('Delete everything clears it', () async {
      final prefs = MemoryLocalPrefs()..pigName = 'Mochi';
      await prefs.clear();
      expect(prefs.pigName, isNull);
    });
  });

  group('Me and Home', () {
    Finder rowSays(String text) =>
        find.descendant(of: byId('me-pig-name'), matching: find.text(text));

    Future<TestApp> openMe(WidgetTester tester, {String? name}) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      addTearDown(tester.view.reset);
      final app = TestApp();
      if (name != null) app.prefs.pigName = name;
      await tester.runAsync(app.openJournal);
      await app.pump(tester, location: '/me');
      for (var i = 0; i < 40 && byId('me-pig-name').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('no name: the row asks for one, and Home shows none', (
      tester,
    ) async {
      await openMe(tester);
      expect(rowSays('Give your pig a name'), findsOneWidget);
      await tester.tapId('tab-home');
      expect(byId('home-pig-name'), findsNothing);
    });

    testWidgets('named: trimmed, on the row and above the speech box', (
      tester,
    ) async {
      final app = await openMe(tester);
      await tester.tapId('me-pig-name');
      expect(find.text("Your pig's name"), findsOneWidget);
      await tester.enterId('me-pig-name-field', '  Mochi  ');
      await tester.tapId('me-pig-name-save');
      expect(app.prefs.pigName, 'Mochi');
      expect(rowSays('Mochi'), findsOneWidget);
      await tester.tapId('tab-home');
      expect(
        find.descendant(
          of: byId('home-pig-name'),
          matching: find.text('Mochi'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the field takes 20 characters at most', (tester) async {
      final app = await openMe(tester);
      await tester.tapId('me-pig-name');
      await tester.enterId('me-pig-name-field', 'A' * 30);
      await tester.tapId('me-pig-name-save');
      expect(app.prefs.pigName, 'A' * 20);
    });

    testWidgets('emptied: no name again', (tester) async {
      final app = await openMe(tester, name: 'Mochi');
      expect(rowSays('Mochi'), findsOneWidget);
      await tester.tapId('me-pig-name');
      await tester.enterId('me-pig-name-field', '   ');
      await tester.tapId('me-pig-name-save');
      expect(app.prefs.pigName, isNull);
      expect(rowSays('Give your pig a name'), findsOneWidget);
    });

    testWidgets('Cancel keeps the name', (tester) async {
      final app = await openMe(tester, name: 'Mochi');
      await tester.tapId('me-pig-name');
      await tester.enterId('me-pig-name-field', 'Oink');
      await tester.tapId('me-pig-name-cancel');
      expect(app.prefs.pigName, 'Mochi');
      expect(rowSays('Mochi'), findsOneWidget);
    });

    testWidgets('the export never carries it', (tester) async {
      final app = await openMe(tester, name: 'Mochi');
      await tester.runAsync(
        () => app.journal.addEntry(
          type: EntryType.saved,
          amountMinor: 500,
          currency: 'THB',
          localDate: '2026-10-01',
        ),
      );
      final csv = (await tester.runAsync(() => journalCsv(app.services)))!;
      expect(csv, isNot(contains('Mochi')));
    });
  });
}
