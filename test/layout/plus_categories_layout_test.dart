import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/features/add/entry_sheet.dart';
import 'package:piggybow/features/plus/fake_plus_store.dart';
import 'package:piggybow/features/plus/plus_entitlement.dart';
import 'package:piggybow/features/plus/plus_store.dart';
import 'package:piggybow/journal/category.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

/// Categories in every layout case (plan §0.3, decision 43): the screen with
/// Plus (hidden rows, your own of the longest names, Add category) and after
/// Plus ended (its line), the editor with its error, and the Add sheet's
/// grid with your own and Add category.
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

  /// 30 characters, the most a name can have, in words people use.
  const name30 = 'Weekend coffee with my friends';
  const other = 'Birthday gifts for the family';

  CustomCategory own(
    String id,
    String name,
    CategoryIcon icon, {
    int day = 1,
    bool hidden = false,
  }) => CustomCategory(
    id: '${CustomCategory.idPrefix}$id',
    name: name,
    icon: icon,
    createdAt: DateTime.utc(2026, 9, day),
    hidden: hidden,
  );

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Finder sheetList() => find
      .descendant(of: find.byType(EntrySheet), matching: find.byType(Scrollable))
      .first;

  /// The checks on the whole of [screenId]'s list, scrolled top to bottom.
  Future<void> checkScrolled(
    WidgetTester tester,
    String screenId,
    String state,
  ) async {
    final list = find
        .descendant(of: byId(screenId), matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(list).position;
    position.jumpTo(0);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await expectSoundLayout(
        tester,
        reason: '$state at ${position.pixels.round()}',
      );
      if (position.pixels >= position.maxScrollExtent) break;
      position.jumpTo(
        (position.pixels + position.viewportDimension * 0.7).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
      await tester.pump();
    }
    position.jumpTo(0);
    await tester.pumpAndSettle();
  }

  /// Two hidden built-ins, and two of your own of the longest names (one
  /// hidden).
  Future<void> open(
    WidgetTester tester,
    LayoutCase c, {
    required String location,
    bool plusOn = true,
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
      await app.journal.putCustomCategory(own('a', name30, CategoryIcon.coffee));
      await app.journal.putCustomCategory(
        own('b', other, CategoryIcon.charity, day: 2, hidden: location != '/home'),
      );
      await app.journal.setBuiltInHidden(SpendCategory.fun, true);
      await app.journal.setBuiltInHidden(SpendCategory.gifts, true);
    });
    await app.pump(tester, location: location);
    await settle(
      tester,
      byId(location == '/home' ? 'home-screen' : 'categories-food'),
    );
  }

  for (final c in layoutCases) {
    testWidgets('C1 Categories with Plus: hidden rows, your own, Add category ($c)', (tester) async {
      await open(tester, c, location: '/me/categories');
      await checkScrolled(tester, 'categories-screen', 'C1');
    });

    testWidgets('C2 Categories after Plus ended: its line above your own ($c)', (tester) async {
      await open(tester, c, location: '/me/categories', plusOn: false);
      await tester.revealId('categories-plus-ended');
      await tester.pumpAndSettle();
      expect(byId('categories-plus-ended'), findsOneWidget);
      await checkScrolled(tester, 'categories-screen', 'C2');
    });

    testWidgets("C3 the editor: a name you have, and the icons ($c)", (tester) async {
      await open(tester, c, location: '/me/categories');
      await tester.tapId('categories-add');
      await tester.enterId('category-name', name30);
      expect(find.text('You already have a category with this name'), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await checkScrolled(tester, 'category-edit-screen', 'C3');
    });

    testWidgets('C4 the Add sheet: your own of the longest name, and Add category ($c)', (tester) async {
      await open(tester, c, location: '/home');
      await tester.tapId('home-add');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(byId('add-cat-add'), 120, scrollable: sheetList());
      await tester.pumpAndSettle();
      expect(byId('add-cat-custom-1'), findsOneWidget);
      expect(byId('add-cat-custom-2'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'C4');
    });
  }
}
