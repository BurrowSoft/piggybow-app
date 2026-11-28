import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_lock.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/router.dart';

import '../app_lock_test.dart' show FakeBiometrics;
import '../helpers.dart';

/// Edge to edge (#36): the app draws behind the navigation bar on every
/// Android version, so no page may leave content under it. Each page runs
/// on a phone with a 48 dp navigation bar (three-button navigation; a
/// gesture handle is smaller), at its top and scrolled to its end, at text
/// ×1 and ×2: nothing that reads (text, an icon, a field) may be under the
/// bar. A background behind it (the page's, the tab bar's) is the point.
void main() {
  const navBar = 48.0;
  const statusBar = 24.0;

  void phoneWithNavBar(WidgetTester tester, double textScale) {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.padding = const FakeViewPadding(
      top: statusBar * 3,
      bottom: navBar * 3,
    );
    tester.view.viewPadding = const FakeViewPadding(
      top: statusBar * 3,
      bottom: navBar * 3,
    );
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// What reads under the navigation bar: every text, icon or field a tap in
  /// the bar's band would land on (hit testing skips what a scroll view
  /// clips), probed every 6 dp.
  List<String> underTheNavBar(WidgetTester tester) {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final found = <String>{};
    for (var y = size.height - navBar + 1; y < size.height; y += 6) {
      for (var x = 1.0; x < size.width; x += 6) {
        for (final entry in tester.hitTestOnBinding(Offset(x, y)).path) {
          final target = entry.target;
          if (target is RenderParagraph) {
            found.add('"${target.text.toPlainText()}"');
          } else if (target is RenderEditable) {
            found.add('a text field');
          }
        }
      }
    }
    return found.toList()..sort();
  }

  /// Every vertical list on the page, scrolled to its end.
  Future<void> scrollToTheEnd(WidgetTester tester) async {
    for (final state in tester.stateList<ScrollableState>(
      find.byType(Scrollable),
    )) {
      final position = state.position;
      if (axisDirectionToAxis(position.axisDirection) != Axis.vertical) {
        continue;
      }
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
  }

  Future<void> expectNothingUnderTheNavBar(
    WidgetTester tester,
    String page,
  ) async {
    expect(tester.takeException(), isNull, reason: page);
    expect(underTheNavBar(tester), isEmpty, reason: '$page, at its top');
    await scrollToTheEnd(tester);
    expect(underTheNavBar(tester), isEmpty, reason: '$page, at its end');
  }

  Future<void> waitFor(WidgetTester tester, String id) async {
    for (var i = 0; i < 40 && byId(id).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    tester.expectScreen(id);
  }

  /// A goal on Home: [reached] shows the celebration on the next start.
  Future<TestApp> withGoal(WidgetTester tester, {bool reached = false}) async {
    final app = TestApp();
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      final t = DateTime.utc(2026, 9, 20);
      await app.journal.putGoal(
        Goal(
          id: 'g1',
          name: 'Bike',
          targetMinor: 1000,
          createdAt: t,
          updatedAt: t,
        ),
      );
      await app.journal.addEntry(
        type: EntryType.saved,
        amountMinor: reached ? 1000 : 400,
        currency: 'THB',
        localDate: '2026-10-01',
      );
    });
    return app;
  }

  /// Each page: how to open it, and its screen id.
  final pages = <String, (Future<void> Function(WidgetTester), String)>{
    'O1 Welcome': (
      (tester) => TestApp(onboarded: false).pump(tester),
      'onb-welcome',
    ),
    'O2 What would make you happy': (
      (tester) => TestApp(
        onboarded: false,
      ).pump(tester, location: OnboardingRoutes.happy),
      'onb-happy',
    ),
    'O3 A goal': (
      (tester) => TestApp(
        onboarded: false,
      ).pump(tester, location: OnboardingRoutes.goal),
      'onb-goal',
    ),
    'the currency list, from O1': (
      (tester) async {
        await TestApp(onboarded: false).pump(tester);
        await tester.tapId('onb-currency-change');
      },
      'currency-screen',
    ),
    'Home': ((tester) => TestApp().pump(tester), 'home-screen'),
    'the Add sheet': (
      (tester) async {
        await TestApp().pump(tester);
        await tester.tapId('home-add');
      },
      'add-amount',
    ),
    'Timeline': (
      (tester) => TestApp().pump(tester, location: AppTab.timeline.path),
      'timeline-screen',
    ),
    'Summary': (
      (tester) => TestApp().pump(tester, location: AppTab.summary.path),
      'summary-screen',
    ),
    'Me': (
      (tester) => TestApp().pump(tester, location: AppTab.me.path),
      'me-screen',
    ),
    'Me, What would make you happy': (
      (tester) => TestApp().pump(tester, location: MeRoutes.happy),
      'me-happy',
    ),
    'Me, Privacy': (
      (tester) => TestApp().pump(tester, location: MeRoutes.privacy),
      'me-privacy-screen',
    ),
    'a new goal': (
      (tester) => TestApp().pump(tester, location: GoalRoutes.create),
      'goal-edit-screen',
    ),
    'a goal': (
      (tester) async => (await withGoal(
        tester,
      )).pump(tester, location: GoalRoutes.detail('g1')),
      'goal-screen',
    ),
    'a goal, edited': (
      (tester) async => (await withGoal(
        tester,
      )).pump(tester, location: GoalRoutes.edit('g1')),
      'goal-edit-screen',
    ),
    'the celebration': (
      (tester) async => (await withGoal(tester, reached: true)).pump(tester),
      'goal-done-screen',
    ),
    'the lock screen': (
      (tester) async {
        final lock = AppLock(
          store: MemorySecretStore(),
          biometrics: FakeBiometrics()..has = false,
          firstRun: MemoryFirstRunMarker(),
          iterations: 50,
        );
        await tester.runAsync(() => lock.setPin('2468'));
        lock.lockNow();
        await TestApp(appLock: lock).pump(tester);
      },
      'lock-screen',
    ),
  };

  for (final textScale in [1.0, 2.0]) {
    for (final MapEntry(key: page, value: (open, id)) in pages.entries) {
      testWidgets('$page, text ×${textScale.toInt()}: nothing under the '
          'navigation bar', (tester) async {
        phoneWithNavBar(tester, textScale);
        await open(tester);
        await waitFor(tester, id);
        await expectNothingUnderTheNavBar(tester, page);
      });
    }
  }

  /// The check itself must catch a page that ignores the bar: a list with
  /// its own padding (so no automatic system inset) runs under it, and the
  /// same list in a SafeArea doesn't.
  for (final safe in [false, true]) {
    testWidgets(
      'control: a list ${safe ? 'in' : 'without'} a SafeArea '
      '${safe ? 'stays clear of' : 'runs under'} the bar',
      (tester) async {
        phoneWithNavBar(tester, 1);
        final list = ListView(
          padding: const EdgeInsets.all(16),
          children: [for (var i = 0; i < 40; i++) Text('Row $i')],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: safe ? SafeArea(child: list) : list),
          ),
        );
        final under = underTheNavBar(tester);
        if (safe) {
          expect(under, isEmpty);
        } else {
          expect(under, isNotEmpty, reason: 'the check must see the rows');
        }
      },
    );
  }
}
