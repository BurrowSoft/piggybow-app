import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/fixtures/launch_fixture.dart';
import 'package:piggybow/goal/goal_progress.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/journal/journal_store.dart';
import 'package:piggybow/money/rate.dart';
import 'package:piggybow/pig/pig_mood.dart' show HappyPick;

import 'helpers.dart';

/// The launch fixtures (staging builds only): the route that names one, the
/// store build that ignores it, the zone check, and what each kind writes.
/// That every contract case shows on Home as the contract says is
/// home_contract_test, through the same writer.
void main() {
  final casesJson = File(fixtureCasesAsset).readAsStringSync();
  final caseIds = [
    for (final c in (jsonDecode(casesJson)['cases'] as List))
      (c as Map<String, dynamic>)['id'] as String,
  ];

  Future<JournalStore> written(LaunchFixture f) async {
    var ids = 0;
    final store = await JournalStore.inMemory(
      clock: f.clock,
      newId: () => 'id${++ids}',
    );
    addTearDown(store.close);
    await f.write(store);
    return store;
  }

  group('the route', () {
    test('only /fixture/<id> names a fixture', () {
      expect(fixtureIdOf('/fixture/C6'), 'C6');
      expect(fixtureIdOf('/fixture/R100'), 'R100');
      for (final r in [
        '/',
        '/home',
        '/fixture',
        '/fixture/',
        '/fixture/C6/x',
        'fixture/C6',
        '/fixture/C 6',
      ]) {
        expect(fixtureIdOf(r), isNull, reason: r);
      }
    });

    test('a launch with no fixture route reads nothing', () async {
      var reads = 0;
      final f = await launchFixtureFor(
        '/',
        cases: () async {
          reads++;
          return casesJson;
        },
      );
      expect(f, isNull);
      expect(reads, 0);
    });
  });

  group('a store build', () {
    test('has no fixtures: the constant is off outside the staging flavor', () {
      expect(kLaunchFixtures, isFalse);
    });

    test('main uses them only inside if (kLaunchFixtures); the cases are '
        'a staging-only asset', () {
      final main = File('lib/main.dart').readAsStringSync();
      final gate = main.indexOf('if (kLaunchFixtures) {');
      final call = main.indexOf('launchFixtureFor(');
      expect(gate, isNonNegative);
      expect(call, greaterThan(gate));
      expect(main.substring(gate, call), isNot(contains('}')));
      expect(main.indexOf('launchFixtureFor(', call + 1), -1);
      for (final f in Directory('lib').listSync(recursive: true)) {
        final path = f.path.replaceAll(r'\', '/');
        if (f is! File || !path.endsWith('.dart')) continue;
        if (path.endsWith('lib/main.dart') || path.contains('/fixtures/')) {
          continue;
        }
        expect(
          f.readAsStringSync(),
          isNot(contains('launch_fixture.dart')),
          reason: path,
        );
      }
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains(
          '    - path: $fixtureCasesAsset\n'
          '      flavors:\n'
          '        - staging\n',
        ),
      );
    });

    testWidgets('"/fixture/C6" opens the usual Home, with nothing written', (
      tester,
    ) async {
      final app = TestApp();
      await tester.runAsync(app.openJournal);
      await app.pump(tester, location: '/fixture/C6');
      await tester.pumpAndSettle();
      tester.expectScreen('home-screen');
      expect(await tester.runAsync(app.journal.entries), isEmpty);
      expect(await tester.runAsync(app.journal.goals), isEmpty);
    });
  });

  group('the fixtures', () {
    test(
      'every contract case and R0, R32, R100 load; an unknown id says so',
      () {
        for (final id in [...caseIds, 'R0', 'R32', 'R100']) {
          final f = LaunchFixture.byId(id, casesJson);
          expect(f.error, isNull, reason: id);
          expect(f.check(f.today), isNull, reason: id);
        }
        expect(caseIds, hasLength(36));
        final unknown = LaunchFixture.byId('C99', casesJson);
        expect(unknown.error, contains('C99'));
        expect(unknown.check('2026-12-02'), contains('C99'));
      },
    );

    test(
      'a journal with notes takes no fixture: nothing written, and why',
      () async {
        Future<void> spend(JournalStore s) => s.addEntry(
          type: EntryType.spent,
          amountMinor: 450,
          currency: 'USD',
          localDate: '2026-12-01',
          category: SpendCategory.food,
        );
        Future<void> picks(JournalStore s) => s.setPicks({HappyPick.plan});
        Future<void> plan(JournalStore s) => s.setPlanMinor(5000);
        Future<void> goal(JournalStore s) => s.putGoal(
          Goal(
            id: 'g1',
            name: 'Bike',
            targetMinor: 1000,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );
        for (final (what, notes) in [
          ('an entry', spend),
          ('picks', picks),
          ('a plan', plan),
          ('a goal', goal),
        ]) {
          final f = LaunchFixture.byId('C6', casesJson);
          var ids = 0;
          final store = await JournalStore.inMemory(
            clock: f.clock,
            newId: () => 'id${++ids}',
          );
          addTearDown(store.close);
          await notes(store);
          final entries = (await store.entries()).length;
          final goals = (await store.goals()).length;
          final problem = await f.write(store);
          expect(problem, contains('C6'), reason: what);
          expect(problem, contains('empty journal'), reason: what);
          expect((await store.entries()).length, entries, reason: what);
          expect((await store.goals()).length, goals, reason: what);
        }
      },
    );

    testWidgets('on a journal with notes the app shows fixture-error and why', (
      tester,
    ) async {
      final f = LaunchFixture.byId('C6', casesJson);
      final problem = await tester.runAsync(() async {
        final store = await JournalStore.inMemory(clock: f.clock);
        await store.setPlanMinor(5000);
        final problem = await f.write(store);
        expect(await store.goals(), isEmpty);
        await store.close();
        return problem;
      });
      expect(problem, isNotNull);
      await tester.pumpWidget(FixtureErrorApp(problem!));
      expect(find.bySemanticsIdentifier('fixture-error'), findsOneWidget);
      expect(find.text(problem), findsOneWidget);
    });

    test('a blank journal takes one (its currency may be set)', () async {
      final f = LaunchFixture.byId('C6', casesJson);
      final store = await JournalStore.inMemory(clock: f.clock);
      addTearDown(store.close);
      await store.setCurrency('THB');
      expect(await store.isBlank(), isTrue);
      expect(await f.write(store), isNull);
      expect(await store.isBlank(), isFalse);
    });

    test('an unknown id writes nothing', () async {
      final store = await written(LaunchFixture.byId('C99', casesJson));
      expect(await store.entries(), isEmpty);
      expect(await store.goals(), isEmpty);
    });

    test("the zone is checked, never pinned: the fixture's today or an error "
        'naming the case and both days', () {
      final c14 = LaunchFixture.byId('C14', casesJson);
      expect(c14.today, '2026-11-30');
      expect(c14.check('2026-11-30'), isNull);
      final problem = c14.check('2026-11-29');
      expect(problem, contains('C14'));
      expect(problem, contains('2026-11-30'));
      expect(problem, contains('2026-11-29'));
    });

    test('a case: its entries at their own times, its goal with its stamps, '
        'the clock at its now', () async {
      final f = LaunchFixture.byId('C9', casesJson);
      final store = await written(f);
      expect(await store.currency(), 'USD');
      expect(await store.picks(), {HappyPick.save});
      final e = (await store.entries()).single;
      expect(e.type, EntryType.saved);
      expect(e.amountMinor, 20000);
      expect(e.localDate, '2026-12-02');
      expect(e.createdAt, DateTime.utc(2026, 12, 2, 2));
      final g = (await store.goals()).single;
      expect(g.name, 'Bike');
      expect(e.goalId, g.id, reason: 'its goal came first, so the save went to it');
      expect(g.targetMinor, 50000, reason: '200.00 of 500.00: 40 %, band 2');
      expect(g.bandReachedAt, [
        DateTime.utc(2026, 11, 20, 3),
        DateTime.utc(2026, 12, 2, 2),
        null,
        null,
        null,
      ]);
      expect(f.clock.nowUtc(), DateTime.utc(2026, 12, 2, 5));
      expect(
        await store.onboarded(),
        isTrue,
        reason: 'straight to Home, past onboarding',
      );
    });

    test('every entry in another currency: written with its rate, and the '
        "store's conversion is the case's home_minor", () async {
      var checked = 0;
      final contract = jsonDecode(casesJson) as Map<String, dynamic>;
      for (final c in (contract['cases'] as List).cast<Map<String, dynamic>>()) {
        final abroad = [
          for (final e in (c['entries'] as List).cast<Map<String, dynamic>>())
            if (e['currency'] != null) e,
        ];
        if (abroad.isEmpty) continue;
        final store = await written(LaunchFixture.byId(c['id'] as String, casesJson));
        final kept = [
          for (final e in await store.entries())
            if (e.currency != contract['currency']) e,
        ];
        expect(kept, hasLength(abroad.length), reason: '${c['id']}');
        for (final (i, e) in abroad.indexed) {
          final k = kept.reversed.elementAt(i);
          checked++;
          expect(
            (k.currency, k.amountMinor, k.rate, k.homeMinor),
            (e['currency'], e['amount_minor'], Rate.fromMap(e['rate']), e['home_minor']),
            reason: '${c['id']}',
          );
        }
      }
      expect(checked, greaterThan(0), reason: 'C37');
    });

    test("every case: an active goal's card shows the bands it stamped", () async {
      var checked = 0;
      for (final id in caseIds) {
        final store = await written(LaunchFixture.byId(id, casesJson));
        final goal = await store.activeGoal();
        if (goal == null) continue;
        checked++;
        final percent = goalPercent(
          progressMinor: await store.goalProgress(goal),
          targetMinor: goal.targetMinor,
        );
        expect(
          percent ~/ 20,
          goal.bandReachedAt.where((t) => t != null).length,
          reason: '$id at $percent %',
        );
      }
      expect(checked, greaterThan(0));
    });

    test(
      'a case with a reached goal: celebrated, so the app opens on Home',
      () async {
        final store = await written(LaunchFixture.byId('C31', casesJson));
        final g = (await store.goals()).single;
        expect(g.status, GoalStatus.ended);
        expect(g.reachedAt, DateTime.utc(2026, 12, 2, 3));
        expect(await store.celebrated(g.id), isTrue);
      },
    );

    test(
      'R0, R32, R100: "Bike" 1,000.00 and one save through the usual path',
      () async {
        for (final (id, saved, bands, status) in [
          ('R0', 0, 0, GoalStatus.active),
          ('R32', 32000, 1, GoalStatus.active),
          ('R100', 100000, 5, GoalStatus.reached),
        ]) {
          final store = await written(LaunchFixture.byId(id, casesJson));
          final g = (await store.goals()).single;
          expect((g.name, g.targetMinor, g.status), ('Bike', 100000, status));
          expect(await store.goalProgress(g), saved, reason: id);
          expect(
            g.bandReachedAt.where((t) => t != null),
            hasLength(bands),
            reason: id,
          );
          expect(await store.celebrated(g.id), status == GoalStatus.reached);
          expect((await store.entries()).length, saved > 0 ? 1 : 0);
        }
      },
    );
  });
}
