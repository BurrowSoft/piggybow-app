import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/money/money.dart';
import 'package:piggybow/tips/tips.dart';

import 'helpers.dart';

/// Home (plan §3.2): the pig and its line, its reaction to an Add, the
/// reminder offer, the goal card, this week, today's idea, and the one-time
/// celebration of a goal reached.
void main() {
  // Tests run on Friday 2 October 2026, 08:30 in Bangkok (helpers.dart);
  // this week is Monday 28 September to today.
  String money(int minor) => formatMoney(minor, 'THB', 'en_US');
  final t = DateTime.utc(2026, 9, 20);
  Goal bike({int target = 100000}) => Goal(
    id: 'g1',
    name: 'Bike',
    targetMinor: target,
    createdAt: t,
    updatedAt: t,
  );

  /// Pumps until [f] finds something (the journal answers over a few frames).
  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  /// A few frames for the journal to answer and the screen to rebuild.
  Future<void> letJournalAnswer(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<TestApp> openHome(
    WidgetTester tester, {
    Future<void> Function(TestApp)? seed,
  }) async {
    final app = TestApp();
    await tester.runAsync(app.openJournal);
    if (seed != null) await tester.runAsync(() => seed(app));
    await app.pump(tester);
    await settle(tester, byId('home-week'));
    return app;
  }

  Future<void> spend(TestApp app, int minor, String day, {Feeling? feeling}) =>
      app.journal.addEntry(
        type: EntryType.spent,
        amountMinor: minor,
        currency: 'THB',
        localDate: day,
        category: SpendCategory.food,
        feeling: feeling,
      );

  Future<void> save(TestApp app, int minor, String day) => app.journal.addEntry(
    type: EntryType.saved,
    amountMinor: minor,
    currency: 'THB',
    localDate: day,
  );

  testWidgets('the first day: the calm pig says how to start', (tester) async {
    final semantics = tester.ensureSemantics();
    await openHome(tester);
    expect(
      find.text('Hi! Tap Add to note your first spend or save.'),
      findsOneWidget,
    );
    expect(tester.getSemantics(byId('home-pig')), isSemantics(value: 'calm'));
    semantics.dispose();
  });

  testWidgets(
    'after an Add the pig answers it, until the app goes to the background',
    (tester) async {
      final app = await openHome(tester);
      await tester.tapId('home-add');
      await tester.enterId('add-amount', '50');
      await tester.tapId('add-cat-food');
      await tester.tapId('add-feel-worth');
      await tester.tapId('add-submit');
      await settle(tester, find.text('Worth it. Nice!'));
      expect(find.text('Worth it. Nice!'), findsOneWidget);
      app.services.lastAdd.value = null; // what main.dart does on hide
      await tester.pumpAndSettle();
      expect(find.text('Worth it. Nice!'), findsNothing);
    },
  );

  testWidgets(
    'the reminder offer: not before the first entry, then until answered',
    (tester) async {
      final app = await openHome(tester);
      expect(byId('home-reminder-yes'), findsNothing);
      await tester.runAsync(() => spend(app, 5000, '2026-10-02'));
      await settle(tester, byId('home-reminder-yes'));
      expect(find.text('A gentle nudge?'), findsOneWidget);
      expect(find.text('Remind me at 8:00 PM'), findsOneWidget);
      await tester.tapId('home-reminder-no');
      await letJournalAnswer(tester);
      expect(byId('home-reminder-yes'), findsNothing);
      expect(await tester.runAsync(app.journal.reminderOfferAnswered), isTrue);
      expect(app.notifications.requests, 0, reason: 'No thanks asks nothing');
    },
  );

  testWidgets('Yes: the reminder on at 20:00, and the permission asked', (
    tester,
  ) async {
    final app = await openHome(
      tester,
      seed: (app) => spend(app, 5000, '2026-10-02'),
    );
    await settle(tester, byId('home-reminder-yes'));
    await tester.tapId('home-reminder-yes');
    await letJournalAnswer(tester);
    final account = app.session.accountState!;
    expect(account.reminderOn, isTrue);
    expect((account.reminderTime.hour, account.reminderTime.minute), (20, 0));
    expect(app.notifications.requests, 1);
    expect(byId('home-reminder-yes'), findsNothing);
  });

  testWidgets('the goal card: none yet, then a goal with its numbers', (
    tester,
  ) async {
    final app = await openHome(tester);
    expect(find.text('Start a savings goal'), findsOneWidget);
    expect(byId('goal-create'), findsOneWidget);
    await tester.runAsync(() async {
      await app.journal.putGoal(bike());
      await save(app, 32000, '2026-10-01');
    });
    await settle(tester, byId('goal-card'));
    expect(find.text('${money(32000)} of ${money(100000)}'), findsOneWidget);
    expect(find.text('32%'), findsOneWidget);
  });

  testWidgets(
    'this week: spent, saved and the worth count; the plan bar only with a plan',
    (tester) async {
      final app = await openHome(
        tester,
        seed: (app) async {
          await spend(app, 1000, '2026-09-29', feeling: Feeling.worthIt);
          await spend(app, 500, '2026-09-30', feeling: Feeling.notSure);
          await save(app, 300, '2026-10-01');
          await spend(app, 9900, '2026-09-27'); // last week (a Sunday)
        },
      );
      expect(find.text('Spent ${money(1500)}'), findsOneWidget);
      expect(find.text('Saved ${money(300)}'), findsOneWidget);
      expect(find.text('1 spend felt worth it'), findsOneWidget);
      expect(
        find.byType(LinearProgressIndicator),
        findsNothing,
        reason: 'no plan yet',
      );
      await tester.runAsync(() => app.journal.setPlanMinor(2000));
      await settle(tester, find.byType(LinearProgressIndicator));
      expect(find.text('Weekly plan ${money(2000)}'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.75,
      );
    },
  );

  testWidgets("today's idea follows the day, and Another idea steps on", (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await openHome(tester);
    final tip = tipForDay(DateTime(2026, 10, 2));
    expect(find.text(tipText(l10n, tip)), findsOneWidget);
    await tester.tapId('home-idea-another');
    expect(find.text(tipText(l10n, nextTip(tip))), findsOneWidget);
  });

  testWidgets('a goal reached is celebrated once', (tester) async {
    final app = await openHome(
      tester,
      seed: (app) async {
        await app.journal.putGoal(bike(target: 1000));
        await save(app, 1000, '2026-10-01');
      },
    );
    await settle(tester, byId('goal-done-screen'));
    expect(find.text('You did it!'), findsOneWidget);
    await tester.tapId('goal-done-close');
    await settle(tester, find.text('Reached: Bike'));
    expect(
      find.text('Reached: Bike'),
      findsOneWidget,
      reason: 'under the empty goal card',
    );
    expect(await tester.runAsync(() => app.journal.celebrated('g1')), isTrue);
    expect(byId('goal-done-screen'), findsNothing);
  });
}
