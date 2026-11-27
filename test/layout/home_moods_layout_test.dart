// Goldens: Home in three of the pig's moods at 320 dp ×2 (decision 44), the
// H5 row of PB Mobile Tester's PR 3 list (Calm is H1's first day).
@Tags(['golden'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/pig/pig_view.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/pig/pig_mood.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

/// Home in the pig's moods, in every layout case (plan §0.3): each state is
/// a case of the mood contract (test/contracts/pig_mood_cases.json), played
/// into the journal at its own times, so Home shows exactly the contract's
/// mood. C3 is Happy (a save this week), C6 Sleepy (the last entry 113 hours ago), C4 Delighted (save and
/// plan both met).
void main() {
  setUpAll(loadAppFonts);
  final contract = jsonDecode(
    File('test/contracts/pig_mood_cases.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  Map<String, dynamic> contractCase(String id) => (contract['cases'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((c) => c['id'] == id);

  /// Home with [id]'s journal: its picks and plan, each entry added at its
  /// created_at, then the clock at the case's now.
  Future<void> openCase(WidgetTester tester, LayoutCase c, String id) async {
    final data = contractCase(id);
    final currency = contract['currency'] as String;
    final now = DateTime.parse(data['now'] as String);
    final clock = MovableClock(now);
    setLayout(tester, c);
    final app = TestApp(currency: currency, clock: clock)
      ..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      await app.journal.setPicks({
        for (final p in data['picks'] as List) HappyPick.values.byName('$p'),
      });
      await app.journal.setPlanMinor(data['plan_minor'] as int?);
      for (final e in (data['entries'] as List).cast<Map<String, dynamic>>()) {
        clock.now = DateTime.parse(e['created_at'] as String);
        await app.journal.addEntry(
          type: EntryType.values.byName(e['type'] as String),
          amountMinor: e['amount_minor'] as int,
          currency: currency,
          localDate: e['local_date'] as String,
          category: SpendCategory.fromId(e['category']),
          feeling: Feeling.fromId(e['feeling']),
        );
      }
      clock.now = now;
    });
    expect(data['goals'], isEmpty, reason: '$id: goals are not played in');
    await app.pump(tester);
    for (var i = 0; i < 40 && byId('home-pig-line').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    final expected = (data['expect'] as Map)['mood'] as String;
    expect(
      tester.widget<PigView>(find.byType(PigView)).mood,
      PigMood.values.byName(expected),
      reason: '$id: the contract mood',
    );
  }

  Finder homeList() => find
      .descendant(of: byId('home-screen'), matching: find.byType(Scrollable))
      .first;

  for (final c in layoutCases) {
    for (final (id, mood) in [
      ('C3', 'happy'),
      ('C6', 'sleepy'),
      ('C4', 'delighted'),
    ]) {
      testWidgets('H5 Home with the pig $mood (contract $id) ($c)', (
        tester,
      ) async {
        await openCase(tester, c, id);
        await expectSoundLayout(tester, reason: 'H5 $id');
        if (c.takesGolden) {
          await expectLayoutGoldens(
            tester,
            c,
            homeList(),
            screen: 'home',
            state: mood,
            stateId: 'H5',
          );
        }
      });
    }
  }
}
