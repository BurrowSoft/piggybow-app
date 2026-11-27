import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/pig/pig_view.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/pig/pig_mood.dart';

import 'helpers.dart';

/// Every case of the mood contract (test/contracts/pig_mood_cases.json),
/// played into the journal and read off Home: the pig's mood (its TalkBack
/// label) and its line are what the pure function gives. This pins Home to
/// the contract, ended goals included (decision 53). Each case's now is the
/// app's clock; its today is that instant's day in Bangkok (helpers.dart).
void main() {
  final contract = jsonDecode(
    File('test/contracts/pig_mood_cases.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final currency = contract['currency'] as String;
  final cases = (contract['cases'] as List).cast<Map<String, dynamic>>();

  DateTime? at(Object? iso) =>
      iso == null ? null : DateTime.parse(iso as String);

  /// The case as the person would have left it: the entries at their own
  /// created_at, then the goals with their stamps (a reached goal was
  /// celebrated when it happened), and the clock back at the case's now.
  Future<void> play(
    TestApp app,
    MovableClock clock,
    Map<String, dynamic> c,
  ) async {
    final store = app.journal;
    await store.setPicks({
      for (final p in c['picks'] as List) HappyPick.values.byName(p as String),
    });
    await store.setPlanMinor(c['plan_minor'] as int?);
    for (final e in (c['entries'] as List).cast<Map<String, dynamic>>()) {
      clock.now = at(e['created_at'])!;
      await store.addEntry(
        type: EntryType.fromId(e['type'])!,
        amountMinor: e['amount_minor'] as int,
        currency: currency,
        localDate: e['local_date'] as String,
        category: SpendCategory.fromId(e['category']),
        feeling: Feeling.fromId(e['feeling']),
      );
    }
    clock.now = at(c['now'])!;
    var n = 0;
    for (final g in (c['goals'] as List).cast<Map<String, dynamic>>()) {
      final id = 'g${++n}';
      final reachedAt = at(g['reached_at']);
      await store.putGoal(
        Goal(
          id: id,
          name: g['name'] as String,
          targetMinor: g['target_minor'] as int? ?? 100000,
          startMinor: g['start_minor'] as int? ?? 0,
          status: GoalStatus.fromId(g['status']) ?? GoalStatus.active,
          bandReachedAt: [for (final b in g['band_reached_at'] as List) at(b)],
          reachedAt: reachedAt,
          createdAt: clock.now,
          updatedAt: clock.now,
        ),
      );
      if (reachedAt != null) await store.markCelebrated(id);
    }
  }

  for (final c in cases) {
    final expected = c['expect'] as Map<String, dynamic>;
    testWidgets('${c['id']} on Home: ${c['why']}', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      addTearDown(tester.view.reset);
      final clock = MovableClock(at(c['now'])!);
      final app = TestApp(currency: currency, clock: clock);
      await tester.runAsync(app.openJournal);
      await tester.runAsync(() => play(app, clock, c));
      await app.pump(tester);
      for (var i = 0; i < 40 && byId('home-pig-line').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(
        app.services.localDay.todayWire,
        c['today'],
        reason: "the case's today is the app's",
      );
      expect(byId('goal-done-screen'), findsNothing);

      final l10n = AppLocalizations.of(tester.element(byId('home-screen')));
      final mood = PigMood.values.byName(expected['mood'] as String);
      expect(
        tester.getSemantics(byId('home-pig')),
        isSemantics(label: pigA11yLabel(l10n, mood)),
      );
      final line = pigLineText(
        l10n,
        expected['line'] as String,
        Map<String, Object>.from(expected['args'] as Map? ?? const {}),
      );
      expect(
        find.descendant(of: byId('home-pig-line'), matching: find.text(line)),
        findsOneWidget,
        reason: expected['line'] as String,
      );
    });
  }
}
