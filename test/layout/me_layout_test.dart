import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/pig/pig_mood.dart' show HappyPick;

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

/// Me in every layout case (plan §0.3, decision 43): its fullest state (all
/// three picks, the largest plan, the reminder on with notifications off,
/// help and the version), the plan dialog with its error, Your privacy with
/// every line and the full policy's link, and the picker.
void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Piggybow',
      packageName: 'com.burrowsoft.piggybow',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  /// The checks on the whole of [screenId]'s list, scrolled top to bottom.
  Future<void> checkScrolled(
    WidgetTester tester,
    String screenId,
    String state,
  ) async {
    final list = find
        .descendant(of: byId(screenId), matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(list).position;
    position.jumpTo(0);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await expectSoundLayout(
        tester,
        reason: '$state at ${position.pixels.round()}',
      );
      if (position.pixels >= position.maxScrollExtent) break;
      position.jumpTo(
        (position.pixels + position.viewportDimension * 0.7).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
      await tester.pump();
    }
    position.jumpTo(0);
    await tester.pumpAndSettle();
  }

  Future<TestApp> open(WidgetTester tester, LayoutCase c) async {
    setLayout(tester, c);
    final app =
        TestApp(
            currency: 'USD',
            config: const AppConfig(
              flavor: Flavor.staging,
              sentryDsn: 'https://key@example.invalid/1',
              supportUrl: 'https://example.invalid/support',
              privacyUrl: 'https://example.invalid/privacy',
            ),
          )
          ..prefs.appearance = c.appearance
          ..notifications.grant = false;
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      await app.journal.setPicks(HappyPick.values.toSet());
      await app.journal.setPlanMinor(999999999999);
    });
    await app.pump(tester, location: '/me');
    await settle(tester, byId('me-happy'));
    return app;
  }

  for (final c in layoutCases) {
    testWidgets('M1 Me, fullest ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('me-reminder');
      await settle(tester, byId('me-open-settings'));
      await checkScrolled(tester, 'me-screen', 'M1');
    });

    testWidgets('M2 the plan dialog with its error ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('me-plan');
      await tester.enterId('me-plan-amount', '1234567890123');
      await tester.tapId('me-plan-save');
      expect(find.text('That amount is too large.'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'M2');
    });

    testWidgets("M3 Your privacy, every line and the policy's link ($c)", (
      tester,
    ) async {
      await open(tester, c);
      await tester.tapId('me-privacy');
      await settle(tester, byId('me-privacy-screen'));
      await checkScrolled(tester, 'me-privacy-screen', 'M3');
      // The link ends the list: at the largest text it's below the fold.
      final list = find
          .descendant(
            of: byId('me-privacy-screen'),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(byId('privacy-policy'), 200, scrollable: list);
      expect(byId('privacy-policy'), findsOneWidget);
    });

    testWidgets('M4 the picker in Me ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('me-happy');
      await settle(tester, byId('me-happy-done'));
      await checkScrolled(tester, 'me-happy', 'M4');
    });
  }
}
