import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/features/plus/fake_plus_store.dart';
import 'package:piggybow/features/plus/plus_entitlement.dart';
import 'package:piggybow/features/plus/plus_store.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/quick_amounts.dart';
import 'package:piggybow/money/money.dart';

import 'helpers.dart';

/// Feature 3, quick amounts: in the Add sheet, for Spent, once a category is
/// picked, up to 3 chips with the last different amounts spent in that
/// category, newest first. A tap fills the amount and saves nothing. No chips
/// for a category with no history, or for Saved.
void main() {
  final t0 = DateTime.utc(2026, 10, 1, 1);

  Entry entry(
    int minutes,
    int amount, {
    EntryType type = EntryType.spent,
    SpendCategory? category = SpendCategory.food,
    String? custom,
    String currency = 'USD',
  }) {
    final at = t0.add(Duration(minutes: minutes));
    final spend = type == EntryType.spent;
    return Entry(
      id: 'e$minutes',
      type: type,
      amountMinor: amount,
      currency: currency,
      localDate: '2026-10-01',
      createdAt: at,
      updatedAt: at,
      category: spend && custom == null ? category : null,
      customCategory: spend ? custom : null,
    );
  }

  List<int> quick(
    List<Entry> entries, {
    SpendCategory? category,
    String? custom,
  }) => quickAmounts(
    entries,
    categoryId: custom ?? (category ?? SpendCategory.food).id,
    currency: 'USD',
  );

  group('the amounts', () {
    test('newest first, each amount once', () {
      expect(
        quick([
          entry(1, 450),
          entry(2, 1250),
          entry(3, 450),
          entry(4, 800),
        ]),
        [800, 450, 1250],
      );
    });

    test('at most 3', () {
      expect(
        quick([for (var i = 0; i < 8; i++) entry(i, 100 * (i + 1))]),
        [800, 700, 600],
      );
    });

    test('by when each was added, not by the order given', () {
      expect(quick([entry(9, 300), entry(1, 100), entry(5, 200)]), [
        300,
        200,
        100,
      ]);
    });

    test('per category: only its own spends', () {
      final entries = [
        entry(1, 450),
        entry(2, 999, category: SpendCategory.transport),
        entry(3, 1250),
      ];
      expect(quick(entries), [1250, 450]);
      expect(quick(entries, category: SpendCategory.transport), [999]);
      expect(quick(entries, category: SpendCategory.groceries), isEmpty);
    });

    test('spends only, and only in the journal currency', () {
      expect(
        quick([
          entry(1, 450),
          entry(2, 5000, type: EntryType.saved),
          entry(3, 700, currency: 'THB'),
        ]),
        [450],
      );
    });

    test('nothing yet: no chips', () {
      expect(quick(const []), isEmpty);
    });

    test('your own category: its own spends, by its id (#49)', () {
      final entries = [
        entry(1, 350, custom: 'c:bubble'),
        entry(2, 450),
        entry(3, 600, custom: 'c:bubble'),
        entry(4, 999, custom: 'c:other'),
      ];
      expect(quick(entries, custom: 'c:bubble'), [600, 350]);
      expect(quick(entries, custom: 'c:other'), [999]);
      expect(quick(entries), [450], reason: 'Food: its own only');
    });
  });

  group('in the Add sheet', () {
    Future<TestApp> open(
      WidgetTester tester, {
      List<(int, SpendCategory)> spends = const [],
      String currency = 'USD',
      bool add = true,
    }) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      addTearDown(tester.view.reset);
      final clock = MovableClock(t0);
      final app = TestApp(currency: currency, clock: clock);
      await tester.runAsync(app.openJournal);
      await tester.runAsync(() async {
        for (final (i, (amount, category)) in spends.indexed) {
          clock.now = t0.add(Duration(minutes: i));
          await app.journal.addEntry(
            type: EntryType.spent,
            amountMinor: amount,
            currency: currency,
            localDate: '2026-10-01',
            category: category,
          );
        }
      });
      await app.pump(tester);
      if (add) await tester.tapId('home-add');
      return app;
    }

    Finder chipSays(int i, String text) =>
        find.descendant(of: byId('add-quick-$i'), matching: find.text(text));

    testWidgets('your own category (#49, with Plus): its own chips', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      addTearDown(tester.view.reset);
      final store = FakePlusStore()
        ..owns = const [PlusProof(token: 't1', productId: plusPlayProductId)];
      final plus = PlusEntitlement(
        store: store,
        hint: MemoryPlusHint(),
        clock: testClock,
      );
      final clock = MovableClock(t0);
      final app = TestApp(
        currency: 'USD',
        clock: clock,
        config: const AppConfig(flavor: Flavor.staging, plusEnabled: true),
        plus: plus,
      );
      await tester.runAsync(app.openJournal);
      await tester.runAsync(() async {
        await app.journal.putCustomCategory(
          CustomCategory(
            id: 'c:bubble',
            name: 'Bubble tea',
            icon: CategoryIcon.drinks,
            createdAt: t0,
          ),
        );
        for (final (i, amount) in [350, 600].indexed) {
          clock.now = t0.add(Duration(minutes: i));
          await app.journal.addEntry(
            type: EntryType.spent,
            amountMinor: amount,
            currency: 'USD',
            localDate: '2026-10-01',
            customCategory: 'c:bubble',
          );
        }
      });
      await tester.runAsync(plus.refresh);
      await app.pump(tester);
      await tester.tapId('home-add');
      await tester.tapId('add-cat-custom-1');
      expect(chipSays(0, r'$6.00'), findsOneWidget);
      expect(chipSays(1, r'$3.50'), findsOneWidget);
      expect(byId('add-quick-2'), findsNothing);
    });

    testWidgets('a category with history: its last 3 different amounts, '
        'formatted in the journal currency', (tester) async {
      await open(
        tester,
        spends: [
          (450, SpendCategory.food),
          (1250, SpendCategory.food),
          (450, SpendCategory.food),
          (800, SpendCategory.food),
          (999, SpendCategory.transport),
        ],
      );
      expect(byId('add-quick-0'), findsNothing, reason: 'no category yet');
      await tester.tapId('add-cat-food');
      expect(chipSays(0, r'$8.00'), findsOneWidget);
      expect(chipSays(1, r'$4.50'), findsOneWidget);
      expect(chipSays(2, r'$12.50'), findsOneWidget);
      expect(byId('add-quick-3'), findsNothing);
      expect(
        tester.getSemantics(byId('add-quick-0')),
        isSemantics(label: r'Use $8.00', isButton: true),
      );
      // Another category: its own.
      await tester.tapId('add-cat-transport');
      expect(chipSays(0, r'$9.99'), findsOneWidget);
      expect(byId('add-quick-1'), findsNothing);
      // One with no history: none.
      await tester.tapId('add-cat-groceries');
      expect(byId('add-quick-0'), findsNothing);
    });

    testWidgets('the currency format: a 0-digit currency', (tester) async {
      await open(tester, currency: 'JPY', spends: [(1200, SpendCategory.food)]);
      await tester.tapId('add-cat-food');
      expect(
        chipSays(0, formatMoney(1200, 'JPY', 'en_US')),
        findsOneWidget,
      );
    });

    testWidgets('a tap fills the amount and saves nothing', (tester) async {
      final app = await open(
        tester,
        spends: [(1250, SpendCategory.food)],
      );
      final before = (await tester.runAsync(app.journal.entries))!.length;
      await tester.tapId('add-cat-food');
      await tester.tapId('add-quick-0');
      final field = tester.widget<TextField>(
        find.descendant(
          of: byId('add-amount'),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, '12.50');
      expect(byId('add-submit'), findsOneWidget, reason: 'the sheet stays');
      final after = (await tester.runAsync(app.journal.entries))!.length;
      expect(after, before, reason: 'nothing saved on a tap');
    });

    testWidgets('Saved: no chips', (tester) async {
      await open(tester, spends: [(1250, SpendCategory.food)]);
      await tester.tapId('add-seg-saved');
      expect(byId('add-quick-0'), findsNothing);
    });

    testWidgets('editing a spend: no chips', (tester) async {
      await open(
        tester,
        add: false,
        spends: [(450, SpendCategory.food), (1250, SpendCategory.food)],
      );
      await tester.tapId('tab-timeline');
      await tester.tapId('tl-row-entry-2');
      expect(byId('edit-save'), findsOneWidget, reason: 'the edit sheet');
      expect(byId('add-quick-0'), findsNothing);
    });
  });
}
