import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/pig/pig_mood.dart' show HappyPick;

import 'helpers.dart';

/// The Summary tab (plan §3.7, decisions 29 and 52) on PB Mobile Tester's
/// fixture S1 (testing/pr4-flows-layout-golden-list.md): every value of its
/// table in the four views, the arrows disabled (never hidden) at both
/// bounds, the plan bar in the current week only, the week that spans two
/// months, and the empty journal.
void main() {
  // S1: Wednesday 2 December 2026, noon in Bangkok.
  final now = DateTime.parse('2026-12-02T05:00:00Z');

  Future<void> s1(TestApp app) async {
    await app.journal.setPicks({HappyPick.save, HappyPick.plan});
    await app.journal.setPlanMinor(15000);
    Future<void> spend(
      int minor,
      SpendCategory category,
      Feeling? feeling,
      String day,
      String note,
    ) => app.journal.addEntry(
      type: EntryType.spent,
      amountMinor: minor,
      currency: 'USD',
      localDate: day,
      category: category,
      feeling: feeling,
      note: note,
    );
    Future<void> save(int minor, String day) => app.journal.addEntry(
      type: EntryType.saved,
      amountMinor: minor,
      currency: 'USD',
      localDate: day,
    );
    await spend(10000, SpendCategory.home, null, '2026-11-30', 'Rent share');
    await spend(
      1250,
      SpendCategory.food,
      Feeling.worthIt,
      '2026-12-01',
      'Lunch',
    );
    await spend(
      320,
      SpendCategory.transport,
      Feeling.notSure,
      '2026-12-02',
      'Bus',
    );
    await save(5000, '2026-12-01');
    await spend(
      4500,
      SpendCategory.fun,
      Feeling.notReally,
      '2026-11-24',
      'Cinema',
    );
    await save(2000, '2026-11-25');
  }

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  /// Summary on a tall phone (every card on screen), the journal set up
  /// first.
  Future<TestApp> open(
    WidgetTester tester, {
    Future<void> Function(TestApp)? seed,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    final app = TestApp(
      currency: 'USD',
      clock: Clock(fixed: now),
    );
    await tester.runAsync(app.openJournal);
    if (seed != null) await tester.runAsync(() => seed(app));
    await app.pump(tester);
    await tester.tapId('tab-summary');
    await settle(tester, byId('sum-period-label'));
    return app;
  }

  Finder textIn(String id, String text) =>
      find.descendant(of: byId(id), matching: find.text(text));

  IconButton arrow(WidgetTester tester, String id) => tester.widget<IconButton>(
    find.descendant(of: byId(id), matching: find.byType(IconButton)),
  );

  /// The arrow [id] is there, labelled [label], enabled or not.
  void expectArrow(
    WidgetTester tester,
    String id, {
    required String label,
    required bool enabled,
  }) {
    expect(byId(id), findsOneWidget, reason: '$id is never hidden');
    expect(arrow(tester, id).onPressed != null, enabled, reason: id);
    final node = tester.getSemantics(byId(id));
    expect('${node.label} ${node.tooltip}', contains(label), reason: id);
    expect(
      node.flagsCollection.isEnabled,
      enabled ? Tristate.isTrue : Tristate.isFalse,
      reason: '$id: TalkBack hears whether it works',
    );
  }

  /// One view of the table: the period, the totals, the categories in order
  /// (id, label, "amount · percent"), the worth line, the plan bar.
  void expectView(
    WidgetTester tester, {
    required String label,
    required String spent,
    required String saved,
    required List<(String, String, String)> categories,
    required String worth,
    required int? plan,
  }) {
    expect(textIn('sum-period-label', label), findsOneWidget, reason: label);
    expect(textIn('sum-spent', 'Spent'), findsOneWidget);
    expect(textIn('sum-spent', spent), findsOneWidget, reason: '$label spent');
    expect(textIn('sum-saved', 'Saved'), findsOneWidget);
    expect(textIn('sum-saved', saved), findsOneWidget, reason: '$label saved');
    expect(textIn('sum-by-category', 'By category'), findsOneWidget);
    var above = double.negativeInfinity;
    for (final (id, name, share) in categories) {
      expect(textIn('sum-cat-$id', name), findsOneWidget, reason: id);
      expect(textIn('sum-cat-$id', share), findsOneWidget, reason: id);
      final top = tester.getTopLeft(byId('sum-cat-$id')).dy;
      expect(top, greaterThan(above), reason: '$id in order');
      above = top;
    }
    final shown = {for (final (id, _, _) in categories) id};
    for (final c in SpendCategory.values) {
      if (shown.contains(c.id)) continue;
      expect(
        byId('sum-cat-${c.id}'),
        findsNothing,
        reason: '${c.id}: no spends',
      );
    }
    expect(textIn('sum-worth', 'Worth it?'), findsOneWidget);
    expect(textIn('sum-worth', worth), findsOneWidget, reason: '$label worth');
    if (plan == null) {
      expect(byId('sum-plan-bar'), findsNothing, reason: '$label: no plan bar');
    } else {
      expect(textIn('sum-plan-bar', 'Weekly plan'), findsOneWidget);
      expect(textIn('sum-plan-bar', r'$150.00'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.descendant(
          of: byId('sum-plan-bar'),
          matching: find.byType(LinearProgressIndicator),
        ),
      );
      expect(bar.value, plan / 100, reason: '$label plan bar');
    }
  }

  testWidgets('S1, this week: every value; next disabled; the plan bar', (
    tester,
  ) async {
    await open(tester, seed: s1);
    expect(textIn('summary-screen', 'Summary'), findsWidgets);
    expect(byId('sum-week'), findsOneWidget);
    expect(byId('sum-month'), findsOneWidget);
    expectView(
      tester,
      label: 'Nov 30 – Dec 6',
      spent: r'$115.70',
      saved: r'$50.00',
      categories: [
        ('home', 'Home & bills', r'$100.00 · 86%'),
        ('food', 'Food & drinks', r'$12.50 · 10%'),
        ('transport', 'Transport', r'$3.20 · 2%'),
      ],
      worth: '1 worth it · 1 not sure · 0 not really',
      plan: 77,
    );
    expectArrow(tester, 'sum-prev', label: 'Previous week', enabled: true);
    expectArrow(tester, 'sum-next', label: 'Next week', enabled: false);
  });

  testWidgets(
    'S1, last week: the oldest, so previous is disabled; no plan bar',
    (tester) async {
      await open(tester, seed: s1);
      await tester.tapId('sum-prev');
      expectView(
        tester,
        label: 'Nov 23 – Nov 29',
        spent: r'$45.00',
        saved: r'$20.00',
        categories: [('fun', 'Fun & going out', r'$45.00 · 100%')],
        worth: '0 worth it · 0 not sure · 1 not really',
        plan: null,
      );
      expectArrow(tester, 'sum-prev', label: 'Previous week', enabled: false);
      expectArrow(tester, 'sum-next', label: 'Next week', enabled: true);
      // Back to this week, where the plan bar is again.
      await tester.tapId('sum-next');
      expect(textIn('sum-period-label', 'Nov 30 – Dec 6'), findsOneWidget);
      expect(byId('sum-plan-bar'), findsOneWidget);
    },
  );

  testWidgets(
    'S1, by month: December (the Monday is November\'s), then November',
    (tester) async {
      await open(tester, seed: s1);
      await tester.tapId('sum-month');
      expectView(
        tester,
        label: 'December 2026',
        spent: r'$15.70',
        saved: r'$50.00',
        categories: [
          ('food', 'Food & drinks', r'$12.50 · 79%'),
          ('transport', 'Transport', r'$3.20 · 20%'),
        ],
        worth: '1 worth it · 1 not sure · 0 not really',
        plan: null,
      );
      expectArrow(tester, 'sum-prev', label: 'Previous month', enabled: true);
      expectArrow(tester, 'sum-next', label: 'Next month', enabled: false);
      await tester.tapId('sum-prev');
      expectView(
        tester,
        label: 'November 2026',
        spent: r'$145.00',
        saved: r'$20.00',
        categories: [
          ('home', 'Home & bills', r'$100.00 · 68%'),
          ('fun', 'Fun & going out', r'$45.00 · 31%'),
        ],
        worth: '0 worth it · 0 not sure · 1 not really',
        plan: null,
      );
      expectArrow(tester, 'sum-prev', label: 'Previous month', enabled: false);
      expectArrow(tester, 'sum-next', label: 'Next month', enabled: true);
    },
  );

  testWidgets('Week ↔ Month: current to current; a past week to its month', (
    tester,
  ) async {
    await open(tester, seed: s1);
    await tester.tapId('sum-month');
    expect(textIn('sum-period-label', 'December 2026'), findsOneWidget);
    await tester.tapId('sum-week');
    expect(textIn('sum-period-label', 'Nov 30 – Dec 6'), findsOneWidget);
    await tester.tapId('sum-prev');
    await tester.tapId('sum-month');
    expect(textIn('sum-period-label', 'November 2026'), findsOneWidget);
  });

  testWidgets('no entries: the empty line, no cards, both arrows disabled', (
    tester,
  ) async {
    await open(tester);
    expect(textIn('sum-period-label', 'Nov 30 – Dec 6'), findsOneWidget);
    expect(textIn('sum-empty', 'Nothing noted for this week.'), findsOneWidget);
    for (final id in [
      'sum-spent',
      'sum-saved',
      'sum-plan-bar',
      'sum-by-category',
      'sum-worth',
    ]) {
      expect(byId(id), findsNothing, reason: id);
    }
    expectArrow(tester, 'sum-prev', label: 'Previous week', enabled: false);
    expectArrow(tester, 'sum-next', label: 'Next week', enabled: false);
    await tester.tapId('sum-month');
    expect(
      textIn('sum-empty', 'Nothing noted for this month.'),
      findsOneWidget,
    );
    expect(textIn('sum-period-label', 'December 2026'), findsOneWidget);
  });

  testWidgets('the worth card only when a spend in the period has a feeling', (
    tester,
  ) async {
    await open(
      tester,
      seed: (app) => app.journal.addEntry(
        type: EntryType.spent,
        amountMinor: 1000,
        currency: 'USD',
        localDate: '2026-12-01',
        category: SpendCategory.food,
      ),
    );
    expect(byId('sum-spent'), findsOneWidget);
    expect(byId('sum-worth'), findsNothing);
  });
}
