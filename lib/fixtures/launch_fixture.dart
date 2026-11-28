import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;

import '../core/clock.dart';
import '../journal/category.dart';
import '../journal/entry.dart';
import '../journal/goal.dart';
import '../journal/journal_store.dart';
import '../pig/pig_mood.dart' show HappyPick;

/// Launch fixtures for the on-device flows (staging builds only). Maestro
/// starts the app with the "route" extra `/fixture/<id>`; the app writes that
/// fixture's journal, freezes its clock at the fixture's now for this
/// process, and opens on Home. The ids: every case of the mood contract, read
/// from the very file the contract tests use, and R0, R32 and R100 for the
/// rainbow.
///
/// [kLaunchFixtures] is a compile-time constant, false outside the staging
/// flavor: main.dart uses the fixtures only inside `if (kLaunchFixtures)`, so
/// a store build compiles them out, and the cases file is a staging-only
/// asset (pubspec.yaml).
const kLaunchFixtures = appFlavor == 'staging';

/// The mood contract's cases: an asset of staging builds only.
const fixtureCasesAsset = 'test/contracts/pig_mood_cases.json';

/// The id in [route] when it is `/fixture/<id>`, else null.
String? fixtureIdOf(String route) =>
    RegExp(r'^/fixture/([A-Za-z0-9]+)$').firstMatch(route)?.group(1);

/// The fixture a launch at [route] asks for, or null when it asks for none.
/// [cases] reads the contract's cases (only when the route names a fixture).
Future<LaunchFixture?> launchFixtureFor(
  String route, {
  required Future<String> Function() cases,
}) async {
  final id = fixtureIdOf(route);
  if (id == null) return null;
  return LaunchFixture.byId(id, await cases());
}

/// A clock that can be set: each entry is written at its own creation time,
/// then the clock stays at the fixture's now.
class FixtureClock extends Clock {
  FixtureClock(this.now) : super(fixed: now);

  DateTime now;

  @override
  DateTime nowUtc() => now.toUtc();
}

/// One fixture: the journal it writes and the instant it freezes.
class LaunchFixture {
  LaunchFixture._(this.id, this.now, this.today, this._write) : error = null;

  /// A fixture that can't load: [error] says why, and it writes nothing.
  LaunchFixture._unknown(this.id, String this.error)
    : now = DateTime.utc(2026),
      today = '',
      _write = null;

  final String id;

  /// The frozen instant (UTC).
  final DateTime now;

  /// The day [now] must fall on in the phone's zone (yyyy-mm-dd).
  final String today;

  /// Why this fixture can't load, or null.
  final String? error;

  final Future<void> Function(JournalStore, FixtureClock)? _write;

  /// The app's clock for this process: frozen at [now] once written.
  late final FixtureClock clock = FixtureClock(now);

  /// The fixture [id] (a contract case from [casesJson], R0, R32, R100, or
  /// the store screenshots' STORE1 and STORE2); an unknown id gives a
  /// fixture whose [error] names it.
  static LaunchFixture byId(String id, String casesJson) {
    final rainbow = const {'R0': 0, 'R32': 32000, 'R100': 100000}[id];
    if (rainbow != null) {
      return LaunchFixture._(
        id,
        DateTime.utc(2026, 12, 2, 5),
        '2026-12-02',
        (store, clock) => _writeRainbow(store, clock, rainbow, '2026-12-02'),
      );
    }
    final storeStart = const {'STORE1': 30000, 'STORE2': 127000}[id];
    if (storeStart != null) {
      return LaunchFixture._(
        id,
        storeNow,
        '2026-11-18',
        (store, clock) => _writeStore(store, clock, startMinor: storeStart),
      );
    }
    final contract = jsonDecode(casesJson) as Map<String, dynamic>;
    final cases = (contract['cases'] as List).cast<Map<String, dynamic>>();
    for (final c in cases) {
      if (c['id'] != id) continue;
      return LaunchFixture._(
        id,
        DateTime.parse(c['now'] as String).toUtc(),
        c['today'] as String,
        (store, clock) =>
            _writeCase(store, clock, c, contract['currency'] as String),
      );
    }
    return LaunchFixture._unknown(id, 'No fixture "$id".');
  }

  /// Why this fixture can't run where today is [deviceToday] (the phone's
  /// zone, LocalDay), or null. The zone is never pinned: a run in the wrong
  /// zone fails here instead of testing the wrong day.
  String? check(String deviceToday) {
    if (error != null) return error;
    if (deviceToday == today) return null;
    return 'Fixture $id needs today = $today at ${now.toIso8601String()}, '
        'but today on this phone is $deviceToday. Set the zone, then launch '
        'again.';
  }

  /// Writes the fixture into [store], then leaves [clock] at [now]; or, when
  /// it can't, writes nothing and says why. A fixture goes only into a blank
  /// journal (no entry, goal, picks or plan): any app can start the launch
  /// activity with a route, so a fixture must never mix with someone's own
  /// notes.
  Future<String?> write(JournalStore store) async {
    final write = _write;
    if (write == null) return error;
    if (!await store.isBlank()) {
      return 'Fixture $id goes only into an empty journal, and this one has '
          "notes. Clear the app's data, then launch again.";
    }
    await write(store, clock);
    // Straight to Home: onboarding doesn't intercept a fixture's launch.
    await store.setOnboarded();
    clock.now = now;
    return null;
  }
}

DateTime? _at(Object? iso) =>
    iso == null ? null : DateTime.parse(iso as String).toUtc();

/// A contract case as the person would have left it: the entries at their
/// own created_at, the goals with their stamps (a reached goal was
/// celebrated when it happened). The mood reads only the entries and the
/// stamps; so that the goal card agrees with them too, an active goal with
/// stamped bands and no amounts of its own comes first, the case's saves go
/// to it, and its target puts them in its highest stamped band (with no
/// saves, what's already saved does).
Future<void> _writeCase(
  JournalStore store,
  FixtureClock clock,
  Map<String, dynamic> c,
  String currency,
) async {
  await store.setCurrency(currency);
  await store.setPicks({
    for (final p in c['picks'] as List) HappyPick.values.byName(p as String),
  });
  await store.setPlanMinor(c['plan_minor'] as int?);
  final goals = (c['goals'] as List).cast<Map<String, dynamic>>();
  final entries = (c['entries'] as List).cast<Map<String, dynamic>>();
  final shown = goals
      .where(
        (g) =>
            (g['status'] ?? 'active') == 'active' &&
            g['reached_at'] == null &&
            g['target_minor'] == null &&
            g['start_minor'] == null &&
            _highestBand(g) > 0,
      )
      .firstOrNull;
  clock.now = _at(c['now'])!;
  if (shown != null) {
    final saved = entries
        .where((e) => e['type'] == 'saved')
        .fold<int>(0, (sum, e) => sum + (e['amount_minor'] as int));
    final band = _highestBand(shown);
    await _putGoal(
      store,
      clock,
      shown,
      targetMinor: saved > 0 ? saved * 5 ~/ band : 100000,
      startMinor: saved > 0 ? 0 : 100000 * band ~/ 5,
    );
  }
  for (final e in entries) {
    clock.now = _at(e['created_at'])!;
    await store.addEntry(
      type: EntryType.fromId(e['type'])!,
      amountMinor: e['amount_minor'] as int,
      currency: currency,
      localDate: e['local_date'] as String,
      category: SpendCategory.fromId(e['category']),
      feeling: Feeling.fromId(e['feeling']),
    );
  }
  clock.now = _at(c['now'])!;
  for (final g in goals) {
    if (identical(g, shown)) continue;
    await _putGoal(
      store,
      clock,
      g,
      targetMinor: g['target_minor'] as int? ?? 100000,
      startMinor: g['start_minor'] as int? ?? 0,
    );
  }
}

/// The highest band a contract goal has stamped (1 to 5), or 0.
int _highestBand(Map<String, dynamic> g) {
  final stamps = g['band_reached_at'] as List;
  for (var i = stamps.length; i > 0; i--) {
    if (stamps[i - 1] != null) return i;
  }
  return 0;
}

/// A contract goal, with its stamps as the case gives them.
Future<void> _putGoal(
  JournalStore store,
  FixtureClock clock,
  Map<String, dynamic> g, {
  required int targetMinor,
  required int startMinor,
}) async {
  final id = store.newId();
  final reachedAt = _at(g['reached_at']);
  await store.putGoal(
    Goal(
      id: id,
      name: g['name'] as String,
      targetMinor: targetMinor,
      startMinor: startMinor,
      status: GoalStatus.fromId(g['status']) ?? GoalStatus.active,
      bandReachedAt: [for (final b in g['band_reached_at'] as List) _at(b)],
      reachedAt: reachedAt,
      createdAt: clock.now,
      updatedAt: clock.now,
    ),
  );
  if (reachedAt != null) await store.markCelebrated(id);
}

/// The rainbow fixtures: "Bike", 1,000.00, with one save of [savedMinor]
/// through the usual path (none for 0); a goal reached that way was
/// celebrated.
Future<void> _writeRainbow(
  JournalStore store,
  FixtureClock clock,
  int savedMinor,
  String today,
) async {
  await store.setCurrency('USD');
  await store.setPicks({HappyPick.save});
  final id = store.newId();
  await store.putGoal(
    Goal(
      id: id,
      name: 'Bike',
      targetMinor: 100000,
      createdAt: clock.now,
      updatedAt: clock.now,
    ),
  );
  if (savedMinor > 0) {
    await store.addEntry(
      type: EntryType.saved,
      amountMinor: savedMinor,
      currency: 'USD',
      localDate: today,
    );
  }
  if ((await store.goal(id))?.reachedAt != null) await store.markCelebrated(id);
}

/// The store screenshots' frozen instant (decision 34): Wednesday 18
/// November 2026, 12:00 in the flows' zone (UTC+7). A Wednesday, as the
/// plan's week has Monday to Wednesday, and day 322 of the year, so Home's
/// idea of the day is tip02.
final storeNow = DateTime.utc(2026, 11, 18, 5);

/// One adult's everyday week in US dollars, brand-free (no shop, app or
/// people's names), as testing/play-screenshots-plan.md §3 has it, moved to
/// the week of Monday 16 November: (created, day, type, amount, category,
/// feeling, note). The saves go to the active goal.
final _storeEntries =
    <(DateTime, String, EntryType, int, SpendCategory?, Feeling?, String)>[
      // Last week (Friday).
      (
        DateTime.utc(2026, 11, 13, 11),
        '2026-11-13',
        EntryType.saved,
        12000,
        null,
        null,
        'Birthday money',
      ),
      // Monday.
      (
        DateTime.utc(2026, 11, 16, 2, 10),
        '2026-11-16',
        EntryType.spent,
        4500,
        SpendCategory.home,
        Feeling.notSure,
        'Internet bill',
      ),
      (
        DateTime.utc(2026, 11, 16, 12, 40),
        '2026-11-16',
        EntryType.spent,
        3200,
        SpendCategory.fun,
        Feeling.worthIt,
        'Concert tickets',
      ),
      // Tuesday.
      (
        DateTime.utc(2026, 11, 17, 1, 30),
        '2026-11-17',
        EntryType.spent,
        625,
        SpendCategory.food,
        Feeling.notReally,
        'Coffee and a pastry',
      ),
      (
        DateTime.utc(2026, 11, 17, 10, 15),
        '2026-11-17',
        EntryType.spent,
        6240,
        SpendCategory.groceries,
        Feeling.worthIt,
        'Groceries for the week',
      ),
      (
        DateTime.utc(2026, 11, 17, 12, 50),
        '2026-11-17',
        EntryType.saved,
        6000,
        null,
        null,
        'Sold an old jacket',
      ),
      // Wednesday, today.
      (
        DateTime.utc(2026, 11, 18, 1, 20),
        '2026-11-18',
        EntryType.spent,
        275,
        SpendCategory.transport,
        null,
        'Bus to work',
      ),
      (
        DateTime.utc(2026, 11, 18, 4, 45),
        '2026-11-18',
        EntryType.spent,
        1450,
        SpendCategory.food,
        Feeling.worthIt,
        'Lunch with a friend',
      ),
    ];

/// STORE1 and STORE2: the plan's journal. Picks {save} (the pig Happy for
/// this week's save), a $250.00 weekly plan (it shows without the plan pick,
/// decision 34), and "Trip to Japan", $1,500.00, created on 1 November with
/// [startMinor] already saved: $300.00 for STORE1 (with the saves, $480.00,
/// 32 %), $1,270.00 for STORE2 ($1,450.00, one $50.00 save from reached).
/// Its first bands are stamped on 1 November, so the pig isn't Delighted.
Future<void> _writeStore(
  JournalStore store,
  FixtureClock clock, {
  required int startMinor,
}) async {
  clock.now = DateTime.utc(2026, 11, 1, 3);
  await store.setCurrency('USD');
  await store.setPicks({HappyPick.save});
  await store.setPlanMinor(25000);
  // The reminder offer was answered long ago: Home opens on the pig, the
  // goal, the week and the idea, with no one-time prompt in the shots.
  await store.answerReminderOffer();
  await store.putGoal(
    Goal(
      id: store.newId(),
      name: 'Trip to Japan',
      targetMinor: 150000,
      startMinor: startMinor,
      createdAt: clock.now,
      updatedAt: clock.now,
    ),
  );
  for (final (at, day, type, minor, category, feeling, note)
      in _storeEntries) {
    clock.now = at;
    await store.addEntry(
      type: type,
      amountMinor: minor,
      currency: 'USD',
      localDate: day,
      category: category,
      feeling: feeling,
      note: note,
    );
  }
}

/// Shown instead of the app when a fixture can't load: the tester's flows
/// look for `fixture-error` and read why. Test builds only, so English.
class FixtureErrorApp extends StatelessWidget {
  const FixtureErrorApp(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: Semantics(
          container: true,
          identifier: 'fixture-error',
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message),
          ),
        ),
      ),
    ),
  );
}
