import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/widget/widget_snapshot.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';

/// The home-screen widget's snapshot (feature 16): each example in
/// test/contracts/widget_snapshot.json, built from its inputs; today is
/// spends only, on that day; the bands; and without Plus, or with the app
/// lock on, nothing from the journal is in it.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final contract =
      jsonDecode(File('test/contracts/widget_snapshot.json').readAsStringSync()) as Map<String, dynamic>;
  final examples = {
    for (final e in (contract['examples'] as List).cast<Map<String, dynamic>>()) e['id'] as String: e['snapshot'],
  };
  final t = DateTime.utc(2026, 9, 20);
  var ids = 0;

  Entry entry(EntryType type, int minor, String day) => Entry(
    id: 'entry-${++ids}',
    type: type,
    amountMinor: minor,
    currency: 'USD',
    localDate: day,
    createdAt: t,
    updatedAt: t,
    category: type == EntryType.spent ? SpendCategory.food : null,
  );

  Goal goal(String name, int target) =>
      Goal(id: 'goal-1', name: name, targetMinor: target, createdAt: t, updatedAt: t);

  /// W1's journal: 3.50 and 12.00 spent and 100.00 saved today, 9.00 spent
  /// the day before.
  final w1Entries = [
    entry(EntryType.spent, 350, '2026-10-02'),
    entry(EntryType.spent, 1200, '2026-10-02'),
    entry(EntryType.saved, 10000, '2026-10-02'),
    entry(EntryType.spent, 900, '2026-10-01'),
  ];

  Map<String, Object?> build({
    String theme = widgetDefaultTheme,
    bool plusActive = true,
    bool lockOn = false,
    String? currency = 'USD',
    Iterable<Entry>? entries,
    Goal? goal,
    int progress = 0,
  }) => widgetSnapshot(
    l10n: l10n,
    locale: 'en_US',
    theme: theme,
    plusActive: plusActive,
    lockOn: lockOn,
    today: '2026-10-02',
    currency: currency,
    entries: entries ?? w1Entries,
    goal: goal,
    goalProgressMinor: progress,
  );

  group('the contract (test/contracts/widget_snapshot.json)', () {
    test('it has the five examples, W1 to W5', () {
      expect(examples.keys, ['W1', 'W2', 'W3', 'W4', 'W5']);
    });

    test('W1: today is its spends; the goal with its band', () {
      expect(build(goal: goal('Bike', 100000), progress: 32000), examples['W1']);
    });

    test('W2: no entry today, and no goal', () {
      expect(build(theme: 'sea', entries: [entry(EntryType.spent, 900, '2026-10-01')]), examples['W2']);
    });

    test('W3: a save today and no spend is 0; a goal past its target has every band', () {
      expect(
        build(entries: [entry(EntryType.saved, 10000, '2026-10-02')], goal: goal('Trip', 50000), progress: 60000),
        examples['W3'],
      );
    });

    test('W4: the lock on, nothing from the journal', () {
      expect(build(theme: 'sea', lockOn: true, goal: goal('Bike', 100000), progress: 32000), examples['W4']);
    });

    test('W5: no Plus comes first, even with the lock on, in the default theme', () {
      expect(
        build(theme: 'sea', plusActive: false, lockOn: true, goal: goal('Bike', 100000), progress: 32000),
        examples['W5'],
      );
    });
  });

  test('without Plus, or with the lock on, no amount and no name is in it', () {
    for (final snapshot in [
      build(lockOn: true, goal: goal('Bike', 100000), progress: 32000),
      build(plusActive: false, goal: goal('Bike', 100000), progress: 32000),
    ]) {
      final json = jsonEncode(snapshot);
      expect(json, isNot(contains('Bike')));
      expect(json, isNot(contains(r'$')));
      expect(json, isNot(contains('2026')), reason: 'not even the day');
    }
  });

  test('the bands: none at 0, one at exactly 20 %, four at 99 %', () {
    List<Object?> bands(int progress) =>
        (build(goal: goal('Bike', 100000), progress: progress)['goal']! as Map)['bands'] as List;
    expect(bands(0), [false, false, false, false, false]);
    expect(bands(19999), [false, false, false, false, false]);
    expect(bands(20000), [true, false, false, false, false]);
    expect(bands(99999), [true, true, true, true, false]);
  });

  test('no currency yet (before onboarding): no amount, and no goal numbers', () {
    final snapshot = build(currency: null, goal: goal('Bike', 100000), progress: 32000);
    expect(snapshot['state'], 'ready');
    expect(snapshot['spentToday'], isNull);
    expect(snapshot['goal'], isNull);
  });

  // Wiring item 14 (#71 with #61): money taken out of savings is never a
  // spend.
  test('a take-out today is not spending', () {
    final snap = build(
      entries: [
        entry(EntryType.spent, 350, '2026-10-02'),
        Entry(
          id: 'out-1',
          type: EntryType.withdraw,
          amountMinor: 5000,
          currency: 'USD',
          localDate: '2026-10-02',
          createdAt: t,
          updatedAt: t,
          goalId: 'goal-1',
        ),
      ],
    );
    expect(snap['spentToday'], r'$3.50');
  });
}
