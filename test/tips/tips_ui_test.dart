import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/policy.dart';
import 'package:piggybow/features/tips/tips_ui.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/router.dart';
import 'package:piggybow/tips/pig_tips.dart';
import 'package:piggybow/tips/tips.dart';

import '../helpers.dart';

/// Pig tips on screen (A3, decision 90): Me's switch asks first (the consent
/// sheet) and turns off at once; Your privacy says what tips send; Home
/// shows the day's written tip with "Written by AI" and Report, and the
/// built-in tips with neither. All only where tips are offered.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  // Tests run on Friday 2 October 2026 in Bangkok.
  const today = '2026-10-02';
  const written = WrittenTip(
    day: today,
    text: 'Try a slow Saturday: one small treat, planned ahead.',
    model: 'claude-sonnet-5-5',
    sig: 'sig-1',
  );
  final builtIn = tipText(l10n, tipForDay(DateTime(2026, 10, 2)));

  Future<void> waitFor(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 60 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<TestApp> open(
    WidgetTester tester, {
    PigTips? tips,
    String? location,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    final app = TestApp(pigTips: tips);
    await app.pump(tester, location: location);
    await tester.pumpAndSettle();
    return app;
  }

  bool switchOn(WidgetTester tester) => tester
      .widget<SwitchListTile>(
        find.descendant(
          of: byId('me-pig-tips'),
          matching: find.byType(SwitchListTile),
        ),
      )
      .value;

  group('Me → Pig tips', () {
    testWidgets('not built in, or not offered here: no row, and no privacy '
        'line', (tester) async {
      await open(tester, location: '/me');
      expect(byId('me-pig-tips'), findsNothing);
      await open(tester, tips: FakePigTips(offered: false), location: '/me');
      expect(byId('me-pig-tips'), findsNothing);
      await open(
        tester,
        tips: FakePigTips(offered: false),
        location: MeRoutes.privacy,
      );
      expect(find.text(l10n.privacyTips), findsNothing);
    });

    testWidgets('on asks first: "Not now" changes nothing', (tester) async {
      final tips = FakePigTips();
      await open(tester, tips: tips, location: '/me');
      await tester.revealId('me-pig-tips');
      expect(switchOn(tester), isFalse);
      expect(
        find.descendant(
          of: byId('me-pig-tips'),
          matching: find.text("Off: your pig's built-in tips"),
        ),
        findsOneWidget,
      );
      await tester.tapId('me-pig-tips');
      expect(byId('tips-sheet'), findsOneWidget);
      expect(find.text('Want your pig to write you tips?'), findsOneWidget);
      await tester.tapId('tips-sheet-not-now');
      expect(byId('tips-sheet'), findsNothing);
      expect(tips.on.value, isFalse);
      expect(tips.consents, isEmpty);
      expect(switchOn(tester), isFalse);
    });

    testWidgets('"Yes, turn on tips" turns them on, with the versions of the '
        'texts agreed to', (tester) async {
      final tips = FakePigTips();
      await open(tester, tips: tips, location: '/me');
      await tester.tapId('me-pig-tips');
      await tester.tapId('tips-sheet-yes');
      expect(byId('tips-sheet'), findsNothing);
      expect(tips.on.value, isTrue);
      expect(tips.consents, [
        'ai ${PolicyVersions.ai}',
        'age18 ${PolicyVersions.age18}',
      ]);
      expect(switchOn(tester), isTrue);
      expect(
        find.descendant(
          of: byId('me-pig-tips'),
          matching: find.text("On: one idea a day from your pig's AI"),
        ),
        findsOneWidget,
      );
    });

    testWidgets("when tips can't turn on, the sheet says so and they stay "
        'off', (tester) async {
      final tips = FakePigTips(unavailable: true);
      await open(tester, tips: tips, location: '/me');
      await tester.tapId('me-pig-tips');
      expect(byId('tips-sheet-failed'), findsNothing);
      await tester.tapId('tips-sheet-yes');
      expect(byId('tips-sheet'), findsOneWidget, reason: 'the sheet stays');
      expect(
        find.text("Pig tips aren't available right now. Try again later."),
        findsOneWidget,
      );
      expect(tips.on.value, isFalse);
      await tester.tapId('tips-sheet-not-now');
      expect(switchOn(tester), isFalse);
    });

    testWidgets('off is at once, and said', (tester) async {
      final tips = FakePigTips(on: true);
      await open(tester, tips: tips, location: '/me');
      await tester.tapId('me-pig-tips');
      expect(byId('tips-sheet'), findsNothing, reason: 'off asks nothing');
      expect(tips.on.value, isFalse);
      expect(switchOn(tester), isFalse);
      expect(
        find.text('Pig tips are off. Your pig will share its built-in tips.'),
        findsOneWidget,
      );
    });

    testWidgets('Your privacy says what tips send, where they are offered', (
      tester,
    ) async {
      await open(tester, tips: FakePigTips(), location: MeRoutes.privacy);
      expect(
        find.text(
          'Pig tips, if you turn them on, send a short summary in numbers '
          '(never your notes or amounts) to our server and Anthropic to '
          'write the tip.',
        ),
        findsOneWidget,
      );
    });
  });

  group("Home's Today's idea", () {
    Future<void> showIdea(WidgetTester tester) async {
      await waitFor(tester, byId('home-idea'));
      await tester.revealId('home-idea-another');
      await tester.pumpAndSettle();
    }

    Finder inIdea(Finder f) => find.descendant(of: byId('home-idea'), matching: f);

    testWidgets('a written tip: its text, "Written by AI" and Report', (
      tester,
    ) async {
      await open(tester, tips: FakePigTips(on: true, tip: written));
      await showIdea(tester);
      expect(inIdea(find.text(written.text)), findsOneWidget);
      expect(inIdea(find.text('Written by AI')), findsOneWidget);
      expect(byId('home-idea-report'), findsOneWidget);
    });

    testWidgets('a built-in tip, or tips off: no label, no Report', (
      tester,
    ) async {
      await open(tester, tips: FakePigTips(on: true));
      await showIdea(tester);
      expect(inIdea(find.text(builtIn)), findsOneWidget);
      expect(byId('home-idea-ai'), findsNothing);
      expect(byId('home-idea-report'), findsNothing);

      await open(tester, tips: FakePigTips(tip: written));
      await showIdea(tester);
      expect(inIdea(find.text(builtIn)), findsOneWidget, reason: 'tips off');
      expect(byId('home-idea-ai'), findsNothing);
    });

    testWidgets('"Another idea" steps into the built-in tips, the day\'s '
        'first', (tester) async {
      await open(tester, tips: FakePigTips(on: true, tip: written));
      await showIdea(tester);
      await tester.tapId('home-idea-another');
      expect(inIdea(find.text(builtIn)), findsOneWidget);
      expect(byId('home-idea-ai'), findsNothing);
      expect(byId('home-idea-report'), findsNothing);
    });

    testWidgets('Report: the reason is sent, thanks are said, and the '
        "day's built-in tip takes its place", (tester) async {
      final tips = FakePigTips(on: true, tip: written);
      await open(tester, tips: tips);
      await showIdea(tester);
      await tester.tapId('home-idea-report');
      expect(byId('tip-report-sheet'), findsOneWidget);
      expect(find.text("What's wrong with this tip?"), findsOneWidget);
      for (final reason in TipReportReason.values) {
        expect(
          find.descendant(
            of: byId('tip-report-${reason.name}'),
            matching: find.text(tipReportReasonText(l10n, reason)),
          ),
          findsOneWidget,
          reason: reason.name,
        );
      }
      await tester.tapId('tip-report-advice');
      expect(byId('tip-report-sheet'), findsNothing);
      expect(tips.reports, [(written, TipReportReason.advice)]);
      expect(
        find.text("Thanks. We'll use this to make tips better."),
        findsOneWidget,
      );
      expect(byId('home-idea-ai'), findsNothing);
      await tester.revealId('home-idea-another');
      expect(inIdea(find.text(builtIn)), findsOneWidget);
    });

    testWidgets("Report's Cancel sends nothing, and the tip stays", (
      tester,
    ) async {
      final tips = FakePigTips(on: true, tip: written);
      await open(tester, tips: tips);
      await showIdea(tester);
      await tester.tapId('home-idea-report');
      await tester.tapId('tip-report-cancel');
      expect(byId('tip-report-sheet'), findsNothing);
      expect(tips.reports, isEmpty);
      expect(inIdea(find.text(written.text)), findsOneWidget);
      expect(byId('home-idea-ai'), findsOneWidget);
    });
  });
}
