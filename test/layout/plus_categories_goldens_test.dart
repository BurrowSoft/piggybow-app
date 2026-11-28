// Goldens: categories (decision 44), at 320 dp ×2, light and dark, for PB
// UX & PM's look: Categories with Plus and after Plus ended, a new category
// in the editor, and the Add sheet's grid with your own and Add category
// (and with one long word).
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/features/plus/fake_plus_store.dart';
import 'package:piggybow/features/plus/plus_entitlement.dart';
import 'package:piggybow/features/plus/plus_store.dart';
import 'package:piggybow/journal/category.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Piggybow',
      packageName: 'com.burrowsoft.piggybow',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  const owned = PlusProof(token: 't1', productId: plusPlayProductId);

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Finder listIn(String screenId) => find
      .descendant(of: byId(screenId), matching: find.byType(Scrollable))
      .first;

  /// Fun hidden; your own Coffee runs, and Pets (hidden on Categories, so
  /// both states show; shown in the sheet); or [firstName] for Coffee runs.
  Future<void> open(
    WidgetTester tester,
    LayoutCase c, {
    required String location,
    bool plusOn = true,
    String firstName = 'Coffee runs',
  }) async {
    setLayout(tester, c);
    final app = TestApp(
      currency: 'USD',
      config: const AppConfig(flavor: Flavor.staging, plusEnabled: true),
      plus: PlusEntitlement(
        store: FakePlusStore()..owns = plusOn ? const [owned] : const [],
        hint: MemoryPlusHint(),
        clock: testClock,
      ),
    )..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      for (final (id, name, icon, day) in [
        ('a', firstName, CategoryIcon.coffee, 1),
        ('b', 'Pets', CategoryIcon.pets, 2),
      ]) {
        await app.journal.putCustomCategory(
          CustomCategory(
            id: '${CustomCategory.idPrefix}$id',
            name: name,
            icon: icon,
            createdAt: DateTime.utc(2026, 9, day),
            hidden: id == 'b' && location != '/home',
          ),
        );
      }
      await app.journal.setBuiltInHidden(SpendCategory.fun, true);
    });
    await app.pump(tester, location: location);
    await settle(
      tester,
      byId(location == '/home' ? 'home-screen' : 'categories-food'),
    );
  }

  for (final c in layoutCases.where((c) => c.takesGolden)) {
    testWidgets('PC1 Categories with Plus ($c)', (tester) async {
      await open(tester, c, location: '/me/categories');
      await expectLayoutGoldens(
        tester,
        c,
        listIn('categories-screen'),
        screen: 'categories',
        state: 'plus',
        stateId: 'PC1',
      );
    });

    testWidgets('PC2 Categories after Plus ended ($c)', (tester) async {
      await open(tester, c, location: '/me/categories', plusOn: false);
      await expectLayoutGoldens(
        tester,
        c,
        listIn('categories-screen'),
        screen: 'categories',
        state: 'plus-ended',
        stateId: 'PC2',
      );
    });

    testWidgets('PC3 a new category in the editor ($c)', (tester) async {
      await open(tester, c, location: '/me/categories');
      await tester.tapId('categories-add');
      await settle(tester, byId('category-icon-star'));
      await expectLayoutGoldens(
        tester,
        c,
        listIn('category-edit-screen'),
        screen: 'category-edit',
        state: 'new',
        stateId: 'PC3',
      );
    });

    testWidgets("PC4 the Add sheet's grid: your own and Add category ($c)", (tester) async {
      await open(tester, c, location: '/home');
      await tester.tapId('home-add');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      // The whole grid in view: its first row at the top of the sheet's list.
      await Scrollable.ensureVisible(tester.element(byId('add-cat-food')));
      await tester.pumpAndSettle();
      expect(byId('add-cat-custom-1'), findsOneWidget);
      expect(byId('add-cat-add'), findsOneWidget);
      await expectLayoutGolden(
        tester,
        c,
        screen: 'add',
        state: 'own-categories',
        stateId: 'PC4',
      );
    });

    // For UX's look: one size for every label, so a long word in a name of
    // your own makes them all smaller, down to normal size; past that the
    // word may break (UX's rule for names).
    testWidgets("PC5 the Add sheet's grid: one long word of your own ($c)", (tester) async {
      await open(tester, c, location: '/home', firstName: 'Subscriptions');
      await tester.tapId('home-add');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(tester.element(byId('add-cat-food')));
      await tester.pumpAndSettle();
      expect(byId('add-cat-custom-1'), findsOneWidget);
      await expectLayoutGolden(
        tester,
        c,
        screen: 'add',
        state: 'own-long-word',
        stateId: 'PC5',
      );
    });
  }
}
