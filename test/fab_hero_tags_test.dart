import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/router.dart';

import 'helpers.dart';

/// Home and Timeline each have an Add button (a FloatingActionButton), and the
/// shell keeps both tabs alive once they've been opened. With the default hero
/// tag, a route pushed over the shell found two heroes with one tag: Flutter's
/// "multiple heroes that share the same tag" assertion, in debug builds.
void main() {
  final t = DateTime.utc(2026, 9, 20);

  testWidgets("Home's and Timeline's Add buttons don't share a hero tag", (tester) async {
    final app = TestApp();
    await tester.runAsync(app.openJournal);
    await tester.runAsync(
      () => app.journal.putGoal(
        Goal(id: 'g1', name: 'Bike', targetMinor: 1000, createdAt: t, updatedAt: t),
      ),
    );
    await app.pump(tester);

    // Both tabs, so both Add buttons are built.
    await tester.tapId('tab-timeline');
    tester.expectScreen('timeline-screen');
    await tester.tapId('tab-home');
    tester.expectScreen('home-screen');

    // A route over the shell: its transition gathers every hero below it.
    unawaited(GoRouter.of(tester.element(byId('home-screen'))).push(GoalRoutes.detail('g1')));
    for (var i = 0; i < 40 && byId('goal-screen').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    tester.expectScreen('goal-screen');
  });
}
