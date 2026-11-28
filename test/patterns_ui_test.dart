import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/features/plus/fake_plus_store.dart';
import 'package:piggybow/features/plus/plus_entitlement.dart';
import 'package:piggybow/features/plus/plus_store.dart';
import 'package:piggybow/features/summary/patterns_view.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/summary/patterns.dart';

import '../tool/no_guilt.dart' show findGuilt;
import 'helpers.dart';

/// Feature 20, Patterns (a Plus perk): with Plus, the first pattern at the
/// end of Summary and up to 3 on its own screen, with the window and what was
/// read; without Plus, a plain teaser once there's enough to go on, with "See
/// Plus" (the paywall) and "Hide" (for good); a build without Plus, nothing.
void main() {
  // Tests run on Friday 2 October 2026 in Bangkok (helpers.dart).
  const withPlus = AppConfig(flavor: Flavor.staging, plusEnabled: true);

  Future<void> spend(
    TestApp app,
    Feeling feeling, {
    SpendCategory category = SpendCategory.food,
    String day = '2026-10-01',
  }) => app.journal.addEntry(
    type: EntryType.spent,
    amountMinor: 500,
    currency: 'USD',
    localDate: day,
    category: category,
    feeling: feeling,
  );

  /// 25 spends with a feeling: Food, Saturdays and Fun stand out.
  Future<void> rich(TestApp app) async {
    for (var i = 0; i < 10; i++) {
      await spend(
        app,
        Feeling.notSure,
        category: SpendCategory.other,
        day: '2026-09-30',
      );
    }
    for (var i = 0; i < 5; i++) {
      await spend(app, Feeling.worthIt);
    }
    for (var i = 0; i < 4; i++) {
      await spend(app, Feeling.worthIt, category: SpendCategory.fun);
    }
    await spend(app, Feeling.notSure, category: SpendCategory.fun);
    for (final day in [
      '2026-09-26',
      '2026-09-19',
      '2026-09-12',
      '2026-09-05',
      '2026-08-29',
    ]) {
      await spend(
        app,
        Feeling.worthIt,
        category: SpendCategory.other,
        day: day,
      );
    }
  }

  /// Not enough yet: 5 spends with a feeling.
  Future<void> few(TestApp app) async {
    for (var i = 0; i < 5; i++) {
      await spend(app, Feeling.worthIt);
    }
  }

  const food = 'Food & drinks: most spends felt worth it';
  const saturday = 'Saturday: most spends felt worth it';
  const fun = 'Fun & going out: most spends felt worth it';

  Future<({TestApp app, FakePlusStore store, PlusEntitlement? plus})> open(
    WidgetTester tester, {
    required Future<void> Function(TestApp) seed,
    bool plusOn = false,
    bool plusBuild = true,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    final store = FakePlusStore();
    if (plusOn) {
      store.owns = const [PlusProof(token: 't1', productId: plusPlayProductId)];
    }
    final plus = plusBuild
        ? PlusEntitlement(store: store, hint: MemoryPlusHint(), clock: testClock)
        : null;
    final app = TestApp(
      currency: 'USD',
      config: plusBuild ? withPlus : const AppConfig(flavor: Flavor.staging),
      plus: plus,
    );
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() => seed(app));
    if (plus != null) await tester.runAsync(plus.refresh);
    await app.pump(tester);
    await tester.tapId('tab-summary');
    for (var i = 0; i < 40 && byId('sum-period-label').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    return (app: app, store: store, plus: plus);
  }

  Finder textIn(String id, String text) =>
      find.descendant(of: byId(id), matching: find.text(text));

  group('with Plus', () {
    testWidgets('your own category stands out, under its own name, on the '
        'card and on Patterns', (tester) async {
      // 6 worth-it spends in your own category and 15 not-sure ones in
      // Other: 21 with a feeling, and only your category stands out.
      await open(
        tester,
        plusOn: true,
        seed: (app) async {
          await app.journal.putCustomCategory(
            CustomCategory(
              id: 'c:bubble',
              name: 'Bubble tea',
              icon: CategoryIcon.drinks,
              createdAt: testClock.nowUtc(),
            ),
          );
          for (var i = 0; i < 6; i++) {
            await app.journal.addEntry(
              type: EntryType.spent,
              amountMinor: 500,
              currency: 'USD',
              localDate: '2026-10-01',
              customCategory: 'c:bubble',
              feeling: Feeling.worthIt,
            );
          }
          for (var i = 0; i < 15; i++) {
            await spend(
              app,
              Feeling.notSure,
              category: SpendCategory.other,
              day: '2026-09-30',
            );
          }
        },
      );
      const bubble = 'Bubble tea: most spends felt worth it';
      expect(textIn('sum-patterns-line', bubble), findsOneWidget);
      await tester.tapId('sum-patterns-see-all');
      tester.expectScreen('patterns-screen');
      expect(textIn('patterns-line-0', bubble), findsOneWidget);
      expect(byId('patterns-line-1'), findsNothing);
      expect(find.textContaining('c:bubble'), findsNothing, reason: 'never an id');
    });

    testWidgets('the first pattern at the end of Summary; all three on '
        'Patterns, with the window and what was read', (tester) async {
      await open(tester, seed: rich, plusOn: true);
      expect(textIn('sum-patterns', 'Patterns'), findsOneWidget);
      expect(textIn('sum-patterns-line', food), findsOneWidget);
      expect(byId('sum-patterns-teaser'), findsNothing);
      await tester.tapId('sum-patterns-see-all');
      tester.expectScreen('patterns-screen');
      expect(textIn('patterns-line-0', food), findsOneWidget);
      expect(textIn('patterns-line-1', saturday), findsOneWidget);
      expect(textIn('patterns-line-2', fun), findsOneWidget);
      expect(byId('patterns-line-3'), findsNothing);
      expect(
        textIn('patterns-window', 'From the last 8 weeks'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: byId('patterns-privacy'),
          matching: find.textContaining('Notes are never read.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('not enough yet: the card says so, with nothing to open', (
      tester,
    ) async {
      await open(tester, seed: few, plusOn: true);
      expect(
        textIn(
          'sum-patterns-line',
          'Patterns show here once a few more spends have a feeling.',
        ),
        findsOneWidget,
      );
      expect(byId('sum-patterns-see-all'), findsNothing);
    });

    testWidgets('Plus ends: the teaser is back, the patterns gone', (
      tester,
    ) async {
      final o = await open(tester, seed: rich, plusOn: true);
      expect(byId('sum-patterns'), findsOneWidget);
      o.store.owns = const [];
      await tester.runAsync(o.plus!.refresh);
      await tester.pumpAndSettle();
      expect(byId('sum-patterns'), findsNothing);
      expect(byId('sum-patterns-teaser'), findsOneWidget);
      expect(find.text(food), findsNothing);
    });
  });

  group('without Plus', () {
    testWidgets('the teaser once there is enough, never the patterns; See '
        'Plus opens the paywall', (tester) async {
      await open(tester, seed: rich);
      expect(byId('sum-patterns'), findsNothing);
      expect(
        textIn('sum-patterns-teaser', 'Patterns in how your spends felt'),
        findsOneWidget,
      );
      for (final line in [food, saturday, fun]) {
        expect(find.text(line), findsNothing, reason: 'never shown, blurred');
      }
      expect(find.byIcon(Icons.lock), findsNothing);
      // Tonal, quieter than the content: not the accent fill of the theme's
      // filled buttons.
      final see = tester.widget<FilledButton>(
        find.descendant(
          of: byId('sum-patterns-see-plus'),
          matching: find.byType(FilledButton),
        ),
      );
      final scheme = Theme.of(
        tester.element(byId('sum-patterns-teaser')),
      ).colorScheme;
      expect(
        see.style!.backgroundColor!.resolve(const {}),
        scheme.secondaryContainer,
      );
      await tester.tapId('sum-patterns-see-plus');
      await tester.pumpAndSettle();
      tester.expectScreen('plus-screen');
    });

    testWidgets('not enough yet: no teaser at all', (tester) async {
      await open(tester, seed: few);
      expect(byId('sum-patterns-teaser'), findsNothing);
      expect(byId('sum-patterns'), findsNothing);
    });

    testWidgets('Hide: gone for good, on this phone', (tester) async {
      final o = await open(tester, seed: rich);
      await tester.tapId('sum-patterns-hide');
      await tester.pumpAndSettle();
      expect(byId('sum-patterns-teaser'), findsNothing);
      expect(o.app.prefs.patternsTeaserHidden, isTrue);
      await tester.tapId('tab-home');
      await tester.tapId('tab-summary');
      await tester.pumpAndSettle();
      expect(byId('sum-patterns-teaser'), findsNothing);
      // Delete everything clears it with the other preferences.
      await tester.runAsync(o.app.prefs.clear);
      expect(o.app.prefs.patternsTeaserHidden, isFalse);
    });
  });

  testWidgets('a build without Plus: no card, no teaser', (tester) async {
    await open(tester, seed: rich, plusBuild: false);
    expect(byId('sum-patterns'), findsNothing);
    expect(byId('sum-patterns-teaser'), findsNothing);
  });

  test('no guilt: every line passes the copy check, with no advice or '
      'judgement; the patterns themselves have no number', () {
    final en = lookupAppLocalizations(const Locale('en'));
    // The window is named ("the last 8 weeks"); a pattern never counts.
    final copy = [
      en.sumPatterns,
      en.sumPatternsSeeAll,
      en.patternsWindow,
      en.patternsNotYet,
      en.patternsNone,
      en.patternsPrivacy,
      en.patternsPlusTitle,
      en.patternsPlusBody,
      en.patternsPlusSee,
      en.patternsPlusHide,
    ];
    final patterns = [
      for (final c in SpendCategory.values)
        for (final pattern in [
          FeelingPattern.categoryWorth(c.id),
          FeelingPattern.categoryMixed(c.id),
        ])
          patternText(en, pattern, dateLocale: 'en_US', customs: const {}),
      for (var day = DateTime.monday; day <= DateTime.sunday; day++)
        patternText(
          en,
          FeelingPattern.weekdayWorth(day),
          dateLocale: 'en_US',
          customs: const {},
        ),
      patternText(
        en,
        const FeelingPattern.overallWorth(),
        dateLocale: 'en_US',
        customs: const {},
      ),
    ];
    expect(patterns, contains(food));
    expect(patterns, contains(saturday));
    for (final text in patterns) {
      expect(RegExp(r'\d').hasMatch(text), isFalse, reason: '"$text": a number');
    }
    final never = [
      '%',
      r'\bshould\b',
      r'\btry\b',
      r'\bconsider\b',
      r'\bcareful\b',
      r'\bimpulsive\b',
      r'\bregret',
      r'\bmistake',
      r'\bbetter\b',
      r'\bworse\b',
      r'\btoo\b',
      r'\bonly\b',
      r'\bkeep it up\b',
      r'\bwatch\b',
      r'\bnot really\b',
    ];
    for (final text in [...copy, ...patterns]) {
      expect(findGuilt({'line': text}), isEmpty, reason: text);
      for (final p in never) {
        expect(
          RegExp(p, caseSensitive: false).hasMatch(text),
          isFalse,
          reason: '"$text" matches $p',
        );
      }
    }
  });
}
