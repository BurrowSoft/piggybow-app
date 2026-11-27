import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/pig/pig_view.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/pig/pig_mood.dart';

/// The pig's look and words (plan §4.1, §4.3, §4.4): the four moods' files
/// parse, every line the mood contract can show has its own text, and the
/// Delighted hop stays still under reduce-motion.
void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('TalkBack names the pig by its mood (R2)', () {
    expect(
      [for (final m in PigMood.values) pigA11yLabel(l10n, m)],
      [
        'Your pig looks sleepy.',
        'Your pig looks calm.',
        'Your pig looks happy.',
        'Your pig looks delighted.',
      ],
    );
  });

  test(
    'every line the contract expects, and every reaction, has its own text',
    () {
      final contract = jsonDecode(
        File('test/contracts/pig_mood_cases.json').readAsStringSync(),
      );
      final expected = <(String, Map<String, Object>)>[
        for (final c in contract['cases'] as List)
          (
            (c['expect'] as Map)['line'] as String,
            Map<String, Object>.from(
              ((c['expect'] as Map)['args'] as Map?) ?? const {},
            ),
          ),
      ];
      expect(expected, isNotEmpty);
      final reactions = [
        for (final r in PigReaction.values)
          pigBubbleKey(const PigState(PigMood.calm, 'pigCalm1'), r),
      ];
      expect(reactions.toSet(), hasLength(5));
      for (final (key, args) in [
        ...expected,
        for (final r in reactions) (r, const <String, Object>{}),
      ]) {
        final text = pigLineText(l10n, key, args);
        if (key != 'pigCalm1') {
          expect(text, isNot(l10n.pigCalm1), reason: '$key fell back');
        }
        for (final v in args.values) {
          expect(text, contains('$v'), reason: '$key shows $v');
        }
      }
    },
  );

  test('the lines as written', () {
    expect(
      pigLineText(l10n, 'pigDelightedBand', {'band': 2}),
      'Band 2 of 5 colored in!',
    );
    expect(
      pigLineText(l10n, 'pigDelightedGoal', {'goalName': 'Bike'}),
      'You reached Bike!',
    );
    expect(pigLineText(l10n, 'pigAfterSave'), 'Into the rainbow it goes!');
    expect(
      pigLineText(l10n, 'pigFirstDay'),
      'Hi! Tap Add to note your first spend or save.',
    );
  });

  test("each mood's file parses", () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final mood in PigMood.values) {
      final info = await vg.loadPicture(SvgAssetLoader(pigAsset(mood)), null);
      expect(info.size, const Size(200, 200), reason: mood.name);
      info.picture.dispose();
    }
  });

  Future<void> show(WidgetTester tester, PigMood mood) => tester.pumpWidget(
    MaterialApp(
      home: Center(child: PigView(mood: mood)),
    ),
  );

  double lift(WidgetTester tester) => -tester
      .widget<Transform>(
        find.descendant(
          of: find.byType(PigView),
          matching: find.byType(Transform),
        ),
      )
      .transform
      .getTranslation()
      .y;

  testWidgets('Delighted hops once; the other moods stay put', (tester) async {
    await show(tester, PigMood.calm);
    await tester.pump(const Duration(milliseconds: 260));
    expect(lift(tester), 0);
    await show(tester, PigMood.delighted);
    await tester.pump(const Duration(milliseconds: 260));
    expect(lift(tester), greaterThan(0));
    await tester.pumpAndSettle();
    expect(lift(tester), closeTo(0, 1e-9), reason: 'back down');
    expect(
      (tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader
              as SvgAssetLoader)
          .assetName,
      'assets/pig/pig-delighted.svg',
    );
  });

  testWidgets('reduce-motion: Delighted without the hop', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await show(tester, PigMood.delighted);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(lift(tester), 0);
  });

  testWidgets('the pig is decorative: nothing to read out', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester, PigMood.happy);
    expect(
      tester.getSemantics(find.byType(PigView)),
      isNot(isSemantics(label: 'pig')),
    );
    semantics.dispose();
  });

  testWidgets('a file that fails to decode never stops the app from starting', (
    tester,
  ) async {
    await tester.runAsync(
      () => precacheSvgs(['assets/pig/no-such-pig.svg', pigAsset(PigMood.calm)]),
    );
  });

  testWidgets('the four pigs are decoded before the first frame', (
    tester,
  ) async {
    await tester.runAsync(() async {
      svg.cache.clear();
      await precachePigs();
    });
    expect(svg.cache.count, PigMood.values.length);
    final main = File('lib/main.dart').readAsStringSync();
    final start = main.indexOf('final pigsLoad = precachePigs();');
    final awaited = main.indexOf('await pigsLoad;');
    expect(start, isNonNegative);
    expect(awaited, greaterThan(start));
    expect(
      awaited,
      lessThan(main.indexOf('runApp(app(')),
      reason: 'before the app runs',
    );
  });
}
