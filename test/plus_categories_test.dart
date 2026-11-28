import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/features/me/me_actions.dart';
import 'package:piggybow/features/plus/fake_plus_store.dart';
import 'package:piggybow/features/plus/plus_entitlement.dart';
import 'package:piggybow/features/plus/plus_store.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/repeat/repeat.dart';

import 'helpers.dart';

/// Categories (decision 79): hiding a built-in is free, in every build;
/// your own are Plus's: Add category opens the paywall without it and the
/// editor with it, and a new one comes back picked in the sheet. After Plus
/// ends they leave the sheet but stay on their spends (Timeline, Summary,
/// the CSV, an edit). One category always stays showing.
void main() {
  const owned = PlusProof(token: 't1', productId: plusPlayProductId);

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Piggybow',
      packageName: 'com.burrowsoft.piggybow',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  CustomCategory own(
    String id,
    String name, {
    CategoryIcon icon = CategoryIcon.coffee,
    int day = 1,
    bool hidden = false,
  }) => CustomCategory(
    id: '${CustomCategory.idPrefix}$id',
    name: name,
    icon: icon,
    createdAt: DateTime.utc(2026, 9, day),
    hidden: hidden,
  );

  /// A spend of 4.50 yesterday in [custom] (one of your own) or [category].
  Future<void> spendIn(TestApp app, {String? custom, SpendCategory? category}) =>
      app.journal.addEntry(
        type: EntryType.spent,
        amountMinor: 450,
        currency: 'THB',
        localDate: '2026-10-01',
        category: category,
        customCategory: custom,
      );

  /// The app; [plusBuild] false is a build without Plus.
  Future<({TestApp app, FakePlusStore store})> open(
    WidgetTester tester, {
    bool plusBuild = true,
    bool plusOn = false,
    List<CustomCategory> customs = const [],
    Set<SpendCategory> hidden = const {},
    Future<void> Function(TestApp app)? seed,
    String location = '/home',
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    final store = FakePlusStore()..owns = plusOn ? const [owned] : const [];
    final app = TestApp(
      config: AppConfig(flavor: Flavor.staging, plusEnabled: plusBuild),
      plus: plusBuild
          ? PlusEntitlement(store: store, hint: MemoryPlusHint(), clock: testClock)
          : null,
    );
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      for (final c in customs) {
        await app.journal.putCustomCategory(c);
      }
      for (final c in hidden) {
        await app.journal.setBuiltInHidden(c, true);
      }
      if (seed != null) await seed(app);
    });
    await app.pump(tester, location: location);
    await settle(
      tester,
      byId(switch (location) {
        '/home' => 'home-screen',
        '/me/categories' => 'categories-food',
        _ => 'me-happy',
      }),
    );
    return (app: app, store: store);
  }

  Future<List<Entry>> spends(WidgetTester tester, TestApp app) async => [
    for (final e in (await tester.runAsync(app.journal.entries))!)
      if (e.type == EntryType.spent) e,
  ];

  /// What a screen reader hears: the merged node's data (the TestId's own
  /// flags are merged into it).
  bool picked(WidgetTester tester, String id) =>
      tester.getSemantics(byId(id)).getSemanticsData().flagsCollection.isSelected ==
      Tristate.isTrue;

  Finder textIn(String id, String text) =>
      find.descendant(of: byId(id), matching: find.text(text));

  // The release gate (the Reviewer's): the built-in categories, and hiding
  // them, stay without Plus.
  testWidgets('a build without Plus: the built-ins, no Add category; Me → '
      'Categories hides one (free), and the sheet leaves it out', (tester) async {
    final o = await open(tester, plusBuild: false, location: '/me');
    await tester.tapId('me-categories');
    tester.expectScreen('categories-screen');
    expect(byId('categories-add'), findsNothing);
    expect(find.text('Yours'), findsNothing);
    await tester.tapId('categories-fun-toggle');
    expect(textIn('categories-fun', 'Hidden'), findsOneWidget);
    expect(textIn('categories-fun-toggle', 'Show'), findsOneWidget);
    expect((await tester.runAsync(o.app.journal.hiddenBuiltIns))!, {SpendCategory.fun});

    await tester.tapId('tab-home');
    await tester.tapId('home-add');
    expect(byId('add-cat-fun'), findsNothing);
    expect(byId('add-cat-add'), findsNothing);
    for (final c in SpendCategory.values.where((c) => c != SpendCategory.fun)) {
      expect(byId('add-cat-${c.id}'), findsOneWidget, reason: c.id);
    }
    await tester.enterId('add-amount', '45');
    await tester.tapId('add-cat-food');
    await tester.tapId('add-submit');
    expect((await spends(tester, o.app)).single.category, SpendCategory.food);
  });

  testWidgets('one category always stays showing', (tester) async {
    final o = await open(
      tester,
      location: '/me/categories',
      hidden: {...SpendCategory.values.where((c) => c != SpendCategory.other)},
    );
    await tester.tapId('categories-other-toggle');
    expect(find.text('Keep at least one category showing'), findsOneWidget);
    expect(textIn('categories-other', 'Hidden'), findsNothing);
    expect(
      (await tester.runAsync(o.app.journal.hiddenBuiltIns))!,
      isNot(contains(SpendCategory.other)),
    );
    // Showing one again is always fine; then the other can go.
    await tester.tapId('categories-food-toggle');
    await tester.tapId('categories-other-toggle');
    expect(textIn('categories-other', 'Hidden'), findsOneWidget);
  });

  testWidgets('with Plus, a category of your own counts as the one showing', (tester) async {
    final o = await open(
      tester,
      plusOn: true,
      location: '/me/categories',
      customs: [own('a', 'Coffee')],
      hidden: {...SpendCategory.values.where((c) => c != SpendCategory.other)},
    );
    await tester.tapId('categories-other-toggle');
    expect(find.text('Keep at least one category showing'), findsNothing);
    expect(textIn('categories-other', 'Hidden'), findsOneWidget);
    await tester.tapId('categories-custom-1-toggle');
    expect(find.text('Keep at least one category showing'), findsOneWidget);
    expect((await tester.runAsync(o.app.journal.customCategories))!.single.hidden, isFalse);
  });

  testWidgets('without Plus on: Add category opens the paywall, in the sheet '
      'and in Categories', (tester) async {
    final o = await open(tester);
    await tester.tapId('home-add');
    await tester.enterId('add-amount', '45');
    await tester.tapId('add-cat-add');
    await settle(tester, byId('plus-restore'));
    tester.expectScreen('plus-screen');
    await tester.pageBack();
    await tester.pumpAndSettle();
    // Back on the sheet, as it was: no editor opened.
    expect(byId('category-edit-screen'), findsNothing);
    final amount = tester.widget<TextField>(
      find.descendant(of: byId('add-amount'), matching: find.byType(TextField)),
    );
    expect(amount.controller!.text, '45');
    await tester.tapId('add-back');

    await tester.tapId('tab-me');
    await tester.tapId('me-categories');
    await tester.tapId('categories-add');
    await settle(tester, byId('plus-restore'));
    tester.expectScreen('plus-screen');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(byId('category-edit-screen'), findsNothing);
    expect((await tester.runAsync(o.app.journal.customCategories))!, isEmpty);
  });

  testWidgets('with Plus: Add category in the sheet makes one, and it comes '
      'back picked; the spend goes to it', (tester) async {
    final o = await open(tester, plusOn: true);
    await tester.tapId('home-add');
    await tester.enterId('add-amount', '45');
    await tester.tapId('add-cat-add');
    tester.expectScreen('category-edit-screen');
    expect(find.text('New category'), findsOneWidget);
    // A new category starts on the star.
    expect(picked(tester, 'category-icon-star'), isTrue);
    await tester.enterId('category-name', '  Coffee runs ');
    await tester.tapId('category-icon-coffee');
    expect(picked(tester, 'category-icon-coffee'), isTrue);
    expect(picked(tester, 'category-icon-star'), isFalse);
    await tester.tapId('category-save');
    await settle(tester, byId('add-cat-custom-1'));
    expect(byId('category-edit-screen'), findsNothing);
    expect(picked(tester, 'add-cat-custom-1'), isTrue);
    expect(textIn('add-cat-custom-1', 'Coffee runs'), findsOneWidget);
    await tester.tapId('add-submit');

    final mine = (await tester.runAsync(o.app.journal.customCategories))!.single;
    expect(mine.name, 'Coffee runs');
    expect(mine.icon, CategoryIcon.coffee);
    final spend = (await spends(tester, o.app)).single;
    expect(spend.customCategory, mine.id);
    expect(spend.category, isNull);

    await tester.tapId('tab-timeline');
    expect(textIn('tl-row-${spend.id}', 'Coffee runs'), findsWidgets);
  });

  // Repeats in your own categories: the Repeat row works as with a
  // built-in, and the repeat keeps the category.
  testWidgets('with your own category picked, the spend repeats in it', (tester) async {
    ListTile row() => tester.widget<ListTile>(
      find.descendant(of: byId('add-repeat'), matching: find.byType(ListTile)),
    );
    Future<void> reveal(String id) async {
      await tester.ensureVisible(byId(id));
      await tester.pumpAndSettle();
    }

    final o = await open(tester, plusOn: true, customs: [own('a', 'Coffee')]);
    await tester.tapId('home-add');
    await tester.enterId('add-amount', '45');
    await reveal('add-cat-custom-1');
    await tester.tapId('add-cat-custom-1');
    await reveal('add-repeat');
    expect(row().onTap, isNotNull);
    await tester.tap(byId('add-repeat'));
    await tester.pumpAndSettle();
    await tester.tap(byId('repeat-choice-monthly'));
    await tester.pumpAndSettle();
    expect(textIn('add-repeat', 'Every month on day 2'), findsOneWidget);
    await tester.tapId('add-submit');

    final spend = (await spends(tester, o.app)).single;
    final repeat = (await tester.runAsync(o.app.journal.repeats))!.single;
    expect((spend.customCategory, spend.repeatId), ('${CustomCategory.idPrefix}a', repeat.id));
    expect((repeat.category, repeat.customCategory), (null, '${CustomCategory.idPrefix}a'));
  });

  /// A spend of 4.50 in your own [custom] on [day], every month on the 1st.
  Future<void> repeatIn(TestApp app, String custom, {String day = '2026-10-01'}) =>
      app.journal.addEntry(
        type: EntryType.spent,
        amountMinor: 450,
        currency: 'THB',
        localDate: day,
        customCategory: custom,
        repeat: const RepeatSchedule.monthly(1),
        today: day,
      );

  /// Frames, with real time between them, until [f] shows (the journal's
  /// reads and what repeats add at start).
  Future<void> waitFor(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 60 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  // A repeat's page: your own categories with Plus, and its own one always,
  // even after Plus ends. With no note, it's named by its category.
  testWidgets("a repeat's page offers your own categories with Plus, and keeps its own after Plus ends", (tester) async {
    final o = await open(
      tester,
      plusOn: true,
      customs: [own('a', 'Coffee'), own('b', 'Pets', day: 2)],
      seed: (app) => repeatIn(app, 'c:a'),
    );
    await tester.tapId('tab-me');
    await tester.tapId('me-repeats');
    await waitFor(tester, textIn('repeat-row-entry-1', 'Coffee'));
    expect(textIn('repeat-row-entry-1', 'Coffee'), findsOneWidget);

    await tester.tapId('repeat-row-entry-1');
    await waitFor(tester, byId('repeat-cat-custom-1'));
    expect(picked(tester, 'repeat-cat-custom-1'), isTrue);
    expect(byId('repeat-cat-custom-2'), findsOneWidget);
    await tester.tapId('repeat-cat-custom-2');
    expect(picked(tester, 'repeat-cat-custom-2'), isTrue);
    await tester.tapId('repeat-save');
    await waitFor(tester, textIn('repeat-row-entry-1', 'Pets'));
    expect(textIn('repeat-row-entry-1', 'Pets'), findsOneWidget);
    final r = (await tester.runAsync(o.app.journal.repeats))!.single;
    expect((r.category, r.customCategory), (null, 'c:b'));

    // Plus ends: the page keeps the repeat's own, and offers no other.
    o.store.owns = const [];
    await tester.runAsync(o.app.plus!.refresh);
    await tester.pumpAndSettle();
    await tester.tapId('repeat-row-entry-1');
    await waitFor(tester, byId('repeat-cat-custom-2'));
    expect(picked(tester, 'repeat-cat-custom-2'), isTrue);
    expect(byId('repeat-cat-custom-1'), findsNothing);
    expect(byId('repeat-cat-food'), findsOneWidget);
    await tester.tapId('repeat-stop');
    expect(find.text('Stop repeating Pets?'), findsOneWidget);
  });

  // Plus ending doesn't stop a repeat: it adds in your own category, as any
  // entry keeps its category, and Home's card names it so.
  testWidgets('without Plus, a repeat in your own category still adds there, and Home names it', (tester) async {
    final o = await open(
      tester,
      customs: [own('a', 'Coffee')],
      seed: (app) => repeatIn(app, 'c:a', day: '2026-09-01'),
    );
    await waitFor(tester, byId('home-repeats'));
    expect(textIn('home-repeats-repeat-entry-1-2026-10-01', 'Coffee'), findsOneWidget);
    expect(
      [for (final e in await spends(tester, o.app)) if (e.auto) (e.localDate, e.customCategory)],
      [('2026-10-01', 'c:a')],
    );
  });

  testWidgets('the editor: a name is needed, and not one you have: your own '
      "or a built-in's, in any case", (tester) async {
    final o = await open(
      tester,
      plusOn: true,
      location: '/me/categories',
      customs: [own('a', 'Coffee')],
    );
    await tester.tapId('categories-add');
    tester.expectScreen('category-edit-screen');
    await tester.tapId('category-save');
    expect(find.text('Give it a name'), findsOneWidget);
    await tester.enterId('category-name', 'GROCERIES');
    expect(find.text('You already have a category with this name'), findsOneWidget);
    await tester.enterId('category-name', 'coffee');
    expect(find.text('You already have a category with this name'), findsOneWidget);
    await tester.tapId('category-save');
    tester.expectScreen('category-edit-screen');
    await tester.enterId('category-name', 'Pets');
    expect(find.text('You already have a category with this name'), findsNothing);
    await tester.tapId('category-save');
    await settle(tester, byId('categories-custom-2'));
    expect(textIn('categories-custom-2', 'Pets'), findsOneWidget);
    final all = (await tester.runAsync(o.app.journal.customCategories))!;
    expect(all.map((c) => (c.name, c.icon)), [
      ('Coffee', CategoryIcon.coffee),
      ('Pets', CategoryIcon.star),
    ]);
  });

  testWidgets('with Plus: Categories edits your own; its spends show the new '
      'name', (tester) async {
    final o = await open(
      tester,
      plusOn: true,
      location: '/me/categories',
      customs: [own('a', 'Coffee')],
      seed: (app) => spendIn(app, custom: 'c:a'),
    );
    await tester.tapId('categories-custom-1');
    tester.expectScreen('category-edit-screen');
    expect(find.text('Edit category'), findsOneWidget);
    expect(picked(tester, 'category-icon-coffee'), isTrue);
    // Its own name is never "taken".
    expect(find.text('You already have a category with this name'), findsNothing);
    await tester.enterId('category-name', 'Coffee runs');
    await tester.tapId('category-icon-bakery');
    await tester.tapId('category-save');
    await settle(tester, byId('categories-screen'));
    expect(textIn('categories-custom-1', 'Coffee runs'), findsOneWidget);
    final mine = (await tester.runAsync(o.app.journal.customCategories))!.single;
    expect((mine.id, mine.name, mine.icon), ('c:a', 'Coffee runs', CategoryIcon.bakery));

    await tester.tapId('tab-timeline');
    expect(find.text('Coffee runs'), findsWidgets);
  });

  testWidgets('hidden, your own leaves the sheet; shown again, it is back', (tester) async {
    await open(
      tester,
      plusOn: true,
      location: '/me/categories',
      customs: [own('a', 'Coffee'), own('b', 'Pets', day: 2)],
    );
    await tester.tapId('categories-custom-1-toggle');
    expect(textIn('categories-custom-1', 'Hidden'), findsOneWidget);
    await tester.tapId('tab-home');
    await tester.tapId('home-add');
    expect(byId('add-cat-custom-1'), findsNothing);
    expect(textIn('add-cat-custom-2', 'Pets'), findsOneWidget);
    await tester.tapId('add-back');
    // The Me tab comes back on its Categories page.
    await tester.tapId('tab-me');
    await settle(tester, byId('categories-screen'));
    await tester.tapId('categories-custom-1-toggle');
    await tester.tapId('tab-home');
    await tester.tapId('home-add');
    expect(textIn('add-cat-custom-1', 'Coffee'), findsOneWidget);
  });

  testWidgets('after Plus ends: your own leave the sheet, and stay on their '
      'spends: Timeline, Summary, the CSV, and an edit', (tester) async {
    final o = await open(
      tester,
      customs: [own('a', 'Coffee')],
      seed: (app) => spendIn(app, custom: 'c:a'),
    );
    await tester.tapId('home-add');
    expect(byId('add-cat-custom-1'), findsNothing);
    expect(byId('add-cat-food'), findsOneWidget);
    await tester.tapId('add-back');

    await tester.tapId('tab-timeline');
    expect(textIn('tl-row-entry-1', 'Coffee'), findsWidgets);
    // Its edit keeps it, picked, even with Plus off.
    await tester.tapId('tl-row-entry-1');
    expect(picked(tester, 'add-cat-custom-1'), isTrue);
    await tester.enterId('add-amount', '5');
    await tester.tapId('edit-save');
    final edited = (await spends(tester, o.app)).single;
    expect((edited.amountMinor, edited.customCategory), (500, 'c:a'));

    await tester.tapId('tab-summary');
    expect(textIn('sum-cat-c:a', 'Coffee'), findsOneWidget);

    final csv = (await tester.runAsync(
      () => journalCsv(o.app.services, l10n: lookupAppLocalizations(const Locale('en'))),
    ))!;
    expect(csv, contains('2026-10-01,spent,5.00,THB,c:a,Coffee,'));

    await tester.tapId('tab-me');
    await tester.tapId('me-categories');
    expect(byId('categories-plus-ended'), findsOneWidget);
    // Editing your own asks for Plus again.
    await tester.tapId('categories-custom-1');
    await settle(tester, byId('plus-restore'));
    tester.expectScreen('plus-screen');
  });

  testWidgets('Plus ending while the sheet is open takes your own out (the one '
      'picked stays)', (tester) async {
    final o = await open(
      tester,
      plusOn: true,
      customs: [own('a', 'Coffee'), own('b', 'Pets', day: 2)],
    );
    await tester.tapId('home-add');
    await tester.tapId('add-cat-custom-2');
    expect(byId('add-cat-custom-1'), findsOneWidget);
    o.store.owns = const [];
    await tester.runAsync(o.app.plus!.refresh);
    await tester.pumpAndSettle();
    expect(byId('add-cat-custom-1'), findsNothing);
    expect(picked(tester, 'add-cat-custom-2'), isTrue);
  });

  testWidgets('a hidden built-in stays on its spends: their edit shows it, '
      'picked; a new spend has it no more', (tester) async {
    await open(
      tester,
      plusBuild: false,
      hidden: {SpendCategory.food},
      seed: (app) => spendIn(app, category: SpendCategory.food),
    );
    await tester.tapId('home-add');
    expect(byId('add-cat-food'), findsNothing);
    await tester.tapId('add-back');
    await tester.tapId('tab-timeline');
    await tester.tapId('tl-row-entry-1');
    expect(picked(tester, 'add-cat-food'), isTrue);
  });

  testWidgets('never none: every built-in hidden and Plus ended, the sheet '
      'offers every built-in', (tester) async {
    await open(
      tester,
      customs: [own('a', 'Coffee')],
      hidden: SpendCategory.values.toSet(),
    );
    await tester.tapId('home-add');
    for (final c in SpendCategory.values) {
      expect(byId('add-cat-${c.id}'), findsOneWidget, reason: c.id);
    }
    expect(byId('add-cat-custom-1'), findsNothing);
  });

  testWidgets("Me's Categories row, for everyone, in Money", (tester) async {
    await open(tester, plusBuild: false, location: '/me');
    await tester.revealId('me-categories');
    expect(textIn('me-categories', 'Categories'), findsOneWidget);
    expect(textIn('me-categories', 'Choose what shows when you add a spend'), findsOneWidget);
  });
}
