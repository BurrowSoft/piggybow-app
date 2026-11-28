import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_lock.dart';
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
/// quiet second, then one per change that changes it (a burst writes once),
/// never the same one twice; the lock, Plus and a new day each reach it;
/// builds without the widget write nothing.
void main() {
  final t = DateTime.utc(2026, 9, 20);

  /// Lets the quiet second pass, then the store's reads.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<(TestApp, FakeBridge)> mount(
    WidgetTester tester, {
    bool enabled = true,
    ValueNotifier<bool>? plusActive,
    AppLock? lock,
    MovableClock? clock,
  }) async {
    final app = TestApp(currency: 'USD', appLock: lock, clock: clock);
    await app.pump(tester);
    final bridge = FakeBridge();
    await tester.pumpWidget(
      WidgetSync(
        enabled: enabled,
        session: app.session,
        services: app.services,
        plusActive: plusActive ?? ValueNotifier(true),
        bridge: bridge,
        child: const SizedBox(),
      ),
    );
    await settle(tester);
    return (app, bridge);
  }

  Future<void> spend(WidgetTester tester, TestApp app, int minor, {String? day}) =>
      tester.runAsync(
        () => app.journal.addEntry(
          type: EntryType.spent,
          amountMinor: minor,
          currency: 'USD',
          localDate: day ?? app.localDay.todayWire,
          category: SpendCategory.food,
        ),
      );

  testWidgets('a first snapshot after a quiet second, then one per change; a '
      'burst writes once, and the same snapshot is never sent twice', (tester) async {
    final (app, bridge) = await mount(tester);
    expect(bridge.writes, hasLength(1));
    expect(bridge.writes.single['state'], 'ready');
    expect(bridge.writes.single['spentToday'], isNull);

    await spend(tester, app, 350);
    await settle(tester);
    expect(bridge.writes, hasLength(2));
    expect(bridge.writes.last['spentToday'], r'$3.50');

    // Two at once: one write.
    await spend(tester, app, 1200);
    await spend(tester, app, 100);
    await settle(tester);
    expect(bridge.writes, hasLength(3));
    expect(bridge.writes.last['spentToday'], r'$16.50');

    // A spend on another day leaves today's snapshot as it was: nothing sent.
    await spend(tester, app, 900, day: '2026-09-30');
    await settle(tester);
    expect(bridge.writes, hasLength(3));
  });

  testWidgets("the goal, with its bands; with Plus gone only \"Part of Plus\" "
      'goes, nothing from the journal', (tester) async {
    final plus = ValueNotifier(true);
    final (app, bridge) = await mount(tester, plusActive: plus);
    await tester.runAsync(() async {
      await app.journal.putGoal(
        Goal(id: 'goal-1', name: 'Bike', targetMinor: 100000, startMinor: 40000, createdAt: t, updatedAt: t),
      );
    });
    await spend(tester, app, 350);
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

  testWidgets('the app lock turned on: "Tap to open" and nothing else', (tester) async {
    final lock = AppLock(
      store: MemorySecretStore(),
      biometrics: FakeBiometrics(),
      firstRun: MemoryFirstRunMarker(),
      iterations: 50,
    );
    final (app, bridge) = await mount(tester, lock: lock);
    await spend(tester, app, 350);
    await settle(tester);
    expect(bridge.writes.last['spentToday'], r'$3.50');

    await tester.runAsync(() => lock.setPin('2468'));
    await settle(tester);
    expect(bridge.writes.last['state'], 'locked');
    expect(jsonEncode(bridge.writes.last), isNot(contains(r'$')));
  });

  testWidgets("a new day: the next snapshot is the new day's, with nothing "
      'spent yet', (tester) async {
    // 08:30 in Bangkok on 2 October.
    final clock = MovableClock(DateTime.utc(2026, 10, 2, 1, 30));
    final (app, bridge) = await mount(tester, clock: clock);
    await spend(tester, app, 350);
    await settle(tester);
    expect((bridge.writes.last['day'], bridge.writes.last['spentToday']), ('2026-10-02', r'$3.50'));

    // 00:30 the next day; any change writes the new day's snapshot.
    clock.now = DateTime.utc(2026, 10, 2, 17, 30);
    await spend(tester, app, 900, day: '2026-10-02');
    await settle(tester);
    expect((bridge.writes.last['day'], bridge.writes.last['spentToday']), ('2026-10-03', null));
  });

  testWidgets('a build without the widget writes nothing', (tester) async {
    final (app, bridge) = await mount(tester, enabled: false);
    await spend(tester, app, 350);
    await settle(tester);
    expect(bridge.writes, isEmpty);
  });
}
