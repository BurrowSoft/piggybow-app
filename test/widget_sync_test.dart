import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_lock.dart';
import 'package:piggybow/features/plus/fake_plus_store.dart';
import 'package:piggybow/features/plus/plus_entitlement.dart';
import 'package:piggybow/features/plus/plus_store.dart';
import 'package:piggybow/features/widget/widget_sync.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';

import 'app_lock_test.dart' show FakeBiometrics;
import 'helpers.dart';

/// Every snapshot the app hands over, decoded.
class FakeBridge implements WidgetBridge {
  final writes = <Map<String, dynamic>>[];

  @override
  Future<void> update(String snapshotJson) async =>
      writes.add(jsonDecode(snapshotJson) as Map<String, dynamic>);
}

/// The home-screen widget kept in step (feature 16): a first snapshot after a
/// quiet spell, then one per change that changes it (a burst writes once),
/// never the same one twice; the lock, Plus and a new day each reach it; the
/// lock on, Plus ending and Delete everything are written at once, with no
/// quiet spell; builds without the widget write nothing.
///
/// The store is changed in runAsync (it works on real time), so a change
/// schedules its write on real time; the first write is on the test's clock.
void main() {
  final t = DateTime.utc(2026, 9, 20);
  const quiet = Duration(milliseconds: 40);

  /// Lets a quiet spell pass on both clocks, then the store's reads.
  Future<void> settle(WidgetTester tester, [Duration spell = quiet]) async {
    await tester.pump(spell * 2);
    await tester.runAsync(() => Future<void>.delayed(spell + const Duration(milliseconds: 200)));
    await tester.pump();
  }

  /// Real time for the store's reads, far shorter than a 1 s quiet spell.
  Future<void> brief(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  Future<(TestApp, FakeBridge)> mount(
    WidgetTester tester, {
    bool enabled = true,
    ValueNotifier<bool>? plusActive,
    AppLock? lock,
    MovableClock? clock,
    Duration spell = quiet,
    String? palette,
  }) async {
    final app = TestApp(currency: 'USD', appLock: lock, clock: clock);
    // Me → Theme's choice, by name (palettes.dart).
    if (palette != null) app.prefs.palette = palette;
    await app.pump(tester);
    final bridge = FakeBridge();
    await tester.pumpWidget(
      WidgetSync(
        enabled: enabled,
        session: app.session,
        services: app.services,
        plusActive: plusActive ?? ValueNotifier(true),
        bridge: bridge,
        quiet: spell,
        child: const SizedBox(),
      ),
    );
    await settle(tester, spell);
    return (app, bridge);
  }

  Future<Entry> spend(TestApp app, int minor, {String? day}) => app.journal.addEntry(
    type: EntryType.spent,
    amountMinor: minor,
    currency: 'USD',
    localDate: day ?? app.localDay.todayWire,
    category: SpendCategory.food,
  );

  testWidgets('a first snapshot after a quiet spell, then one per change; a '
      'burst writes once, and the same snapshot is never sent twice', (tester) async {
    final (app, bridge) = await mount(tester);
    expect(bridge.writes, hasLength(1));
    expect(bridge.writes.single['state'], 'ready');
    expect(bridge.writes.single['spentToday'], isNull);

    await tester.runAsync(() => spend(app, 350));
    await settle(tester);
    expect(bridge.writes, hasLength(2));
    expect(bridge.writes.last['spentToday'], r'$3.50');

    // Two at once: one write.
    await tester.runAsync(() async {
      await spend(app, 1200);
      await spend(app, 100);
    });
    await settle(tester);
    expect(bridge.writes, hasLength(3));
    expect(bridge.writes.last['spentToday'], r'$16.50');

    // A spend on another day leaves today's snapshot as it was: nothing sent.
    await tester.runAsync(() => spend(app, 900, day: '2026-09-30'));
    await settle(tester);
    expect(bridge.writes, hasLength(3));
  });

  testWidgets('the goal, with its bands; with Plus gone only "Part of Plus" '
      'goes, nothing from the journal', (tester) async {
    final plus = ValueNotifier(true);
    final (app, bridge) = await mount(tester, plusActive: plus);
    await tester.runAsync(() async {
      await app.journal.putGoal(
        Goal(id: 'goal-1', name: 'Bike', targetMinor: 100000, startMinor: 40000, createdAt: t, updatedAt: t),
      );
      await spend(app, 350);
    });
    await settle(tester);
    final goal = bridge.writes.last['goal'] as Map<String, dynamic>;
    expect(goal['name'], 'Bike');
    expect(goal['progress'], r'$400.00 of $1,000.00');
    expect(goal['bands'], [true, true, false, false, false]);

    plus.value = false;
    await settle(tester);
    expect(bridge.writes.last, {
      'version': 1,
      'state': 'plus',
      'theme': 'default',
      'text': {'plus': 'Part of Plus'},
    });
  });

  testWidgets('showing less is written at once, with no quiet spell: Plus '
      'ending, the lock turned on, Delete everything', (tester) async {
    final lock = AppLock(
      store: MemorySecretStore(),
      biometrics: FakeBiometrics(),
      firstRun: MemoryFirstRunMarker(),
      iterations: 50,
    );
    final plus = ValueNotifier(true);
    const second = Duration(seconds: 1);
    final (app, bridge) = await mount(tester, plusActive: plus, lock: lock, spell: second);
    await tester.runAsync(() async {
      await app.journal.putGoal(
        Goal(id: 'goal-1', name: 'Bike', targetMinor: 100000, createdAt: t, updatedAt: t),
      );
      await spend(app, 350);
    });
    await settle(tester, second);
    expect(bridge.writes.last['spentToday'], r'$3.50');

    // Plus ends: written on the spot, the test's clock standing still (no
    // journal read is needed for "Part of Plus").
    plus.value = false;
    await tester.pump();
    expect(bridge.writes.last['state'], 'plus');
    // Back: the journal is read again, a few frames, still far within a second.
    plus.value = true;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(bridge.writes.last['state'], 'ready');

    // The lock turned on: written within a brief moment, long before a second.
    await tester.runAsync(() => lock.setPin('2468'));
    await brief(tester);
    expect(bridge.writes.last['state'], 'locked');
    expect(jsonEncode(bridge.writes.last), isNot(contains(r'$')));
    await tester.runAsync(lock.clear);
    await brief(tester);
    expect(bridge.writes.last['state'], 'ready');

    // Delete everything: a blank journal, at once too.
    await tester.runAsync(app.journal.wipe);
    await brief(tester);
    expect(bridge.writes.last['goal'], isNull);
    expect(bridge.writes.last['spentToday'], isNull);
  });

  testWidgets("a journal that can't be read never holds back the lock: "
      '"Tap to open" still reaches the widget', (tester) async {
    final lock = AppLock(
      store: MemorySecretStore(),
      biometrics: FakeBiometrics(),
      firstRun: MemoryFirstRunMarker(),
      iterations: 50,
    );
    final (app, bridge) = await mount(tester, lock: lock);
    await tester.runAsync(() => spend(app, 350));
    await settle(tester);
    expect(bridge.writes.last['spentToday'], r'$3.50');

    // Closed, every read of the journal throws.
    await tester.runAsync(app.journal.close);
    await tester.runAsync(() => lock.setPin('2468'));
    await brief(tester);
    expect(bridge.writes.last['state'], 'locked');
  });

  testWidgets("a new day: the next snapshot is the new day's, with nothing "
      'spent yet', (tester) async {
    // 08:30 in Bangkok on 2 October.
    final clock = MovableClock(DateTime.utc(2026, 10, 2, 1, 30));
    final (app, bridge) = await mount(tester, clock: clock);
    await tester.runAsync(() => spend(app, 350));
    await settle(tester);
    expect((bridge.writes.last['day'], bridge.writes.last['spentToday']), ('2026-10-02', r'$3.50'));

    // 00:30 the next day; any change writes the new day's snapshot.
    clock.now = DateTime.utc(2026, 10, 2, 17, 30);
    await tester.runAsync(() => spend(app, 900, day: '2026-10-02'));
    await settle(tester);
    expect((bridge.writes.last['day'], bridge.writes.last['spentToday']), ('2026-10-03', null));
  });

  testWidgets('a build without the widget writes nothing', (tester) async {
    final (app, bridge) = await mount(tester, enabled: false);
    await tester.runAsync(() => spend(app, 350));
    await settle(tester);
    expect(bridge.writes, isEmpty);
  });

  // Wiring item 14 (#71 with #45, #47 and #51).
  test('PlusActive follows the entitlement, and tells when it changes', () async {
    final plus = PlusEntitlement(
      store: FakePlusStore()..owns = const [PlusProof(token: 't1', productId: plusPlayProductId)],
      hint: MemoryPlusHint(),
      clock: testClock,
    );
    final active = PlusActive(plus);
    var told = 0;
    void listener() => told++;
    active.addListener(listener);
    expect(active.value, isFalse);
    await plus.start();
    expect(active.value, isTrue);
    expect(told, greaterThan(0));
    active.removeListener(listener);
    expect(const PlusActive(null).value, isFalse, reason: 'a build without Plus');
  });

  testWidgets("the goal is Home's first card: the oldest active one, not the "
      'one a new save goes to', (tester) async {
    final (app, bridge) = await mount(tester);
    await tester.runAsync(() async {
      await app.journal.putGoal(
        Goal(id: 'goal-1', name: 'Bike', targetMinor: 100000, createdAt: t, updatedAt: t),
      );
      final later = t.add(const Duration(days: 1));
      await app.journal.putGoal(
        Goal(id: 'goal-2', name: 'Laptop', targetMinor: 100000, createdAt: later, updatedAt: later),
        allowAnother: true,
      );
      await app.journal.addEntry(
        type: EntryType.saved,
        amountMinor: 500,
        currency: 'USD',
        localDate: app.localDay.todayWire,
        goalId: 'goal-2',
      );
    });
    await settle(tester);
    expect((await tester.runAsync(app.journal.activeGoal))!.id, 'goal-2');
    expect((bridge.writes.last['goal'] as Map<String, dynamic>)['name'], 'Bike');
  });

  testWidgets("the theme is Me → Theme's while Plus is active, the default "
      'without it', (tester) async {
    final plus = ValueNotifier(true);
    final (_, bridge) = await mount(tester, plusActive: plus, palette: 'plum');
    expect(bridge.writes.last['theme'], 'plum');
    plus.value = false;
    await settle(tester);
    expect(bridge.writes.last['theme'], 'default');
  });
}
