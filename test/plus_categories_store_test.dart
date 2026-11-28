import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/journal_store.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';

import 'helpers.dart';

/// Categories of your own (Plus, decision 79) and hidden built-ins, in the
/// store and in the rules the Add sheet and Categories share: your own are
/// never deleted, only hidden; their spends keep them; the sheet offers the
/// built-ins not hidden and, with Plus, your own; never none.
void main() {
  late JournalStore store;
  late MovableClock clock;
  var ids = 0;
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(() async {
    clock = MovableClock(DateTime.utc(2026, 10, 2, 1));
    ids = 0;
    store = await JournalStore.inMemory(clock: clock, newId: () => 'e${++ids}');
  });
  tearDown(() => store.close());

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

  Future<Entry> spend({SpendCategory? category, String? custom}) =>
      store.addEntry(
        type: EntryType.spent,
        amountMinor: 450,
        currency: 'USD',
        localDate: '2026-10-02',
        category: category,
        customCategory: custom,
      );

  group('your own categories', () {
    test('kept oldest first, the name trimmed; a rename keeps the id', () async {
      await store.putCustomCategory(own('b', 'Pets', day: 3));
      await store.putCustomCategory(own('a', '  Coffee runs  ', day: 2));
      expect((await store.customCategories()).map((c) => c.name), [
        'Coffee runs',
        'Pets',
      ]);
      final coffee = (await store.customCategories()).first;
      await store.putCustomCategory(
        coffee.copyWith(name: 'Coffee', icon: CategoryIcon.bakery),
      );
      final again = (await store.customCategories()).first;
      expect(again.id, 'c:a');
      expect(again.name, 'Coffee');
      expect(again.icon, CategoryIcon.bakery);
    });

    test('a new id is "c:" and a fresh id', () {
      expect(store.newCategoryId(), 'c:e1');
      expect(CustomCategory.isCustomId('c:e1'), isTrue);
      expect(CustomCategory.isCustomId('food'), isFalse);
    });

    test('refused: no name, over 30 characters, a name you have (any case), '
        'an id that is not your own kind', () async {
      await store.putCustomCategory(own('a', 'Coffee'));
      await expectLater(
        store.putCustomCategory(own('b', '   ')),
        throwsArgumentError,
      );
      await expectLater(
        store.putCustomCategory(own('b', 'x' * (categoryNameMax + 1))),
        throwsArgumentError,
      );
      await store.putCustomCategory(own('b', 'x' * categoryNameMax));
      await expectLater(
        store.putCustomCategory(own('c', 'COFFEE')),
        throwsStateError,
      );
      await expectLater(
        store.putCustomCategory(
          CustomCategory(
            id: 'food',
            name: 'Food 2',
            icon: CategoryIcon.star,
            createdAt: DateTime.utc(2026, 9, 1),
          ),
        ),
        throwsArgumentError,
      );
      expect((await store.customCategories()).length, 2);
    });

    test('30 characters as people count them: 30 emoji fit', () async {
      await store.putCustomCategory(own('a', '🐷' * categoryNameMax));
      await expectLater(
        store.putCustomCategory(own('b', '🐷' * (categoryNameMax + 1))),
        throwsArgumentError,
      );
    });

    test('hidden and shown again, never deleted', () async {
      await store.putCustomCategory(own('a', 'Coffee'));
      await store.setCustomHidden('c:a', true);
      expect((await store.customCategories()).single.hidden, isTrue);
      await store.setCustomHidden('c:a', false);
      expect((await store.customCategories()).single.hidden, isFalse);
      await expectLater(store.setCustomHidden('c:nope', true), throwsArgumentError);
    });

    test('a record this build cannot read is skipped', () {
      expect(CustomCategory.fromMap('c:a', {'name': 'X', 'icon': 'nope'}), isNull);
      expect(
        CustomCategory.fromMap('food', {
          'name': 'X',
          'icon': 'coffee',
          'created_at': '2026-09-01T00:00:00.000Z',
        }),
        isNull,
      );
      final ok = CustomCategory.fromMap('c:a', {
        'name': 'X',
        'icon': 'coffee',
        'created_at': '2026-09-01T00:00:00.000Z',
      });
      expect(ok?.hidden, isFalse);
    });
  });

  group('built-ins: hidden and shown again', () {
    test('kept in the enum order, whatever the order hidden', () async {
      expect(await store.hiddenBuiltIns(), isEmpty);
      await store.setBuiltInHidden(SpendCategory.gifts, true);
      await store.setBuiltInHidden(SpendCategory.food, true);
      expect(await store.hiddenBuiltIns(), {SpendCategory.food, SpendCategory.gifts});
      await store.setBuiltInHidden(SpendCategory.food, false);
      expect(await store.hiddenBuiltIns(), {SpendCategory.gifts});
    });
  });

  group('spends in your own categories', () {
    test('stored in the one category field; read back as yours', () async {
      await store.putCustomCategory(own('a', 'Coffee'));
      final e = await spend(custom: 'c:a');
      final read = (await store.entries()).single;
      expect(read, e);
      expect(read.category, isNull);
      expect(read.customCategory, 'c:a');
      expect(read.categoryId, 'c:a');
      expect(read.toMap()['category'], 'c:a');
    });

    test('a spend goes only to one of your own that exists', () async {
      await expectLater(spend(custom: 'c:nope'), throwsArgumentError);
      await expectLater(spend(custom: 'food'), throwsArgumentError);
      await expectLater(spend(), throwsArgumentError);
      expect(await store.entries(), isEmpty);
    });

    test('a hidden one keeps its spends, and still takes an edit', () async {
      await store.putCustomCategory(own('a', 'Coffee'));
      final e = await spend(custom: 'c:a');
      await store.setCustomHidden('c:a', true);
      final edited = await store.updateEntry(e.copyWith(amountMinor: 500));
      expect(edited.customCategory, 'c:a');
    });

    test('an edit swaps a built-in and your own, both ways', () async {
      await store.putCustomCategory(own('a', 'Coffee'));
      final e = await spend(category: SpendCategory.food);
      final mine = await store.updateEntry(e.copyWith(customCategory: 'c:a'));
      expect((mine.category, mine.customCategory), (null, 'c:a'));
      final back = await store.updateEntry(
        mine.copyWith(category: SpendCategory.fun),
      );
      expect((back.category, back.customCategory), (SpendCategory.fun, null));
    });

    test('a save never has a category of yours', () async {
      await store.putCustomCategory(own('a', 'Coffee'));
      final s = await store.addEntry(
        type: EntryType.saved,
        amountMinor: 100,
        currency: 'USD',
        localDate: '2026-10-02',
        customCategory: 'c:a',
      );
      expect(s.customCategory, isNull);
      expect(s.categoryId, isNull);
    });

    test('Delete everything erases your categories and the hidden list', () async {
      await store.putCustomCategory(own('a', 'Coffee'));
      await store.setBuiltInHidden(SpendCategory.food, true);
      await store.wipe();
      expect(await store.customCategories(), isEmpty);
      expect(await store.hiddenBuiltIns(), isEmpty);
    });
  });

  group('names and icons', () {
    test("a built-in's in the app's language, your own as typed", () {
      final customs = {'c:a': own('a', 'Coffee runs', icon: CategoryIcon.pets)};
      expect(categoryName(l10n, 'food', customs), l10n.catFood);
      expect(categoryName(l10n, 'c:a', customs), 'Coffee runs');
      expect(categoryIcon('food', customs), SpendCategory.food.icon);
      expect(categoryIcon('c:a', customs), Icons.pets);
    });

    test('every icon has its name to be read out', () {
      final names = {for (final i in CategoryIcon.values) i.label(l10n)};
      expect(names.length, CategoryIcon.values.length);
      expect(CategoryIcon.star.label(l10n), 'Other favorite');
      expect(CategoryIcon.preset, CategoryIcon.star);
      expect({for (final i in CategoryIcon.values) i.id}.length, CategoryIcon.values.length);
    });
  });

  group('what the Add sheet offers', () {
    final coffee = own('a', 'Coffee');
    final pets = own('b', 'Pets', day: 2, hidden: true);
    final books = own('c', 'Books', day: 3);
    final customs = [coffee, pets, books];
    final builtIns = [for (final c in SpendCategory.values) c.id];

    test('without Plus: the built-ins not hidden, and none of your own', () {
      expect(
        offeredCategories(
          hidden: {SpendCategory.fun},
          customs: customs,
          plus: false,
        ),
        [...builtIns.where((id) => id != 'fun')],
      );
    });

    test('with Plus: then your own not hidden, oldest first', () {
      expect(
        offeredCategories(hidden: const {}, customs: customs, plus: true),
        [...builtIns, 'c:a', 'c:c'],
      );
    });

    test("an edited spend's own and the one picked stay, in their places", () {
      expect(
        offeredCategories(
          hidden: {SpendCategory.food, SpendCategory.fun},
          customs: customs,
          plus: false,
          keep: ['c:b', 'food'],
        ),
        [...builtIns.where((id) => id != 'fun'), 'c:b'],
      );
    });

    test('never none: every built-in hidden and Plus ended → every built-in', () {
      final all = SpendCategory.values.toSet();
      expect(
        usableCategories(hidden: all, customs: customs, plus: false),
        isEmpty,
      );
      expect(
        offeredCategories(hidden: all, customs: customs, plus: false),
        builtIns,
      );
      // With Plus, your own are enough.
      expect(
        offeredCategories(hidden: all, customs: customs, plus: true),
        ['c:a', 'c:c'],
      );
    });
  });
}
