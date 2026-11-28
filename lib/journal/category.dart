import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// The spend categories that come with the app. [id] is stored, exported in
/// the CSV and used in test ids (`add-cat-<id>`). They can be hidden, never
/// renamed: their names follow the app's language.
enum SpendCategory {
  food('food', Icons.restaurant),
  groceries('groceries', Icons.shopping_cart),
  transport('transport', Icons.directions_bus),
  home('home', Icons.home),
  shopping('shopping', Icons.shopping_bag),
  fun('fun', Icons.celebration),
  health('health', Icons.favorite),
  gifts('gifts', Icons.redeem),
  other('other', Icons.category);

  const SpendCategory(this.id, this.icon);

  final String id;
  final IconData icon;

  static SpendCategory? fromId(Object? id) =>
      values.where((c) => c.id == id).firstOrNull;

  String label(AppLocalizations l10n) => switch (this) {
    food => l10n.catFood,
    groceries => l10n.catGroceries,
    transport => l10n.catTransport,
    home => l10n.catHome,
    shopping => l10n.catShopping,
    fun => l10n.catFun,
    health => l10n.catHealth,
    gifts => l10n.catGifts,
    other => l10n.catOther,
  };
}

/// The icons a category of your own can take (Plus, decision 79): the
/// built-ins' own style, so the grid reads as one family; no emoji. [id] is
/// stored.
enum CategoryIcon {
  coffee('coffee', Icons.local_cafe),
  bakery('bakery', Icons.bakery_dining),
  drinks('drinks', Icons.local_bar),
  takeout('takeout', Icons.takeout_dining),
  pets('pets', Icons.pets),
  kids('kids', Icons.child_friendly),
  school('school', Icons.school),
  books('books', Icons.menu_book),
  music('music', Icons.music_note),
  games('games', Icons.sports_esports),
  sports('sports', Icons.sports_soccer),
  fitness('fitness', Icons.fitness_center),
  beauty('beauty', Icons.spa),
  clothes('clothes', Icons.checkroom),
  tech('tech', Icons.devices),
  phone('phone', Icons.smartphone),
  bills('bills', Icons.receipt_long),
  car('car', Icons.directions_car),
  fuel('fuel', Icons.local_gas_station),
  travel('travel', Icons.flight),
  garden('garden', Icons.local_florist),
  tools('tools', Icons.build),
  charity('charity', Icons.volunteer_activism),
  star('star', Icons.star);

  const CategoryIcon(this.id, this.icon);

  final String id;
  final IconData icon;

  static CategoryIcon? fromId(Object? id) =>
      values.where((i) => i.id == id).firstOrNull;

  /// A new category's icon until another is picked (UX).
  static const preset = star;

  /// What a screen reader says for the icon in the picker.
  String label(AppLocalizations l10n) => switch (this) {
    coffee => l10n.categoryIconCoffee,
    bakery => l10n.categoryIconBakery,
    drinks => l10n.categoryIconDrinks,
    takeout => l10n.categoryIconTakeout,
    pets => l10n.categoryIconPets,
    kids => l10n.categoryIconKids,
    school => l10n.categoryIconSchool,
    books => l10n.categoryIconBooks,
    music => l10n.categoryIconMusic,
    games => l10n.categoryIconGames,
    sports => l10n.categoryIconSports,
    fitness => l10n.categoryIconFitness,
    beauty => l10n.categoryIconBeauty,
    clothes => l10n.categoryIconClothes,
    tech => l10n.categoryIconTech,
    phone => l10n.categoryIconPhone,
    bills => l10n.categoryIconBills,
    car => l10n.categoryIconCar,
    fuel => l10n.categoryIconFuel,
    travel => l10n.categoryIconTravel,
    garden => l10n.categoryIconGarden,
    tools => l10n.categoryIconTools,
    charity => l10n.categoryIconCharity,
    star => l10n.categoryIconStar,
  };
}

/// The longest name a category of your own can have.
const categoryNameMax = 30;

/// A category of your own (Plus, decision 79): the name you typed, its icon,
/// and whether it's hidden. Never deleted, only hidden (UX), so every spend
/// in it keeps its name in Timeline, Summary and the CSV.
class CustomCategory {
  const CustomCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.createdAt,
    this.hidden = false,
  });

  /// Every own category's id starts with it: never a built-in's id, and never
  /// a spreadsheet formula's first character (= + - @, a tab or a CR).
  static const idPrefix = 'c:';

  static bool isCustomId(Object? id) => id is String && id.startsWith(idPrefix);

  final String id;
  final String name;
  final CategoryIcon icon;
  final DateTime createdAt;
  final bool hidden;

  CustomCategory copyWith({String? name, CategoryIcon? icon, bool? hidden}) =>
      CustomCategory(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        createdAt: createdAt,
        hidden: hidden ?? this.hidden,
      );

  Map<String, Object?> toMap() => {
    'name': name,
    'icon': icon.id,
    'created_at': createdAt.toUtc().toIso8601String(),
    'hidden': hidden,
  };

  /// Null for a record this build can't read.
  static CustomCategory? fromMap(String id, Map<String, Object?> m) {
    try {
      final icon = CategoryIcon.fromId(m['icon']);
      final name = m['name'];
      if (!isCustomId(id) || icon == null || name is! String) return null;
      return CustomCategory(
        id: id,
        name: name,
        icon: icon,
        createdAt: DateTime.parse(m['created_at'] as String).toUtc(),
        hidden: m['hidden'] == true,
      );
    } on Object {
      return null;
    }
  }
}

/// A spend's category name as the app shows it: a built-in's in the app's
/// language, your own as typed. [customs] by id.
String categoryName(
  AppLocalizations l10n,
  String id,
  Map<String, CustomCategory> customs,
) => SpendCategory.fromId(id)?.label(l10n) ?? customs[id]?.name ?? id;

/// A spend's category icon, built-in or your own.
IconData categoryIcon(String id, Map<String, CustomCategory> customs) =>
    SpendCategory.fromId(id)?.icon ?? customs[id]?.icon.icon ?? Icons.category;

/// The categories a new spend can go to, by id: the built-ins not [hidden]
/// and, while [plus] is on, your own not hidden ([customs] oldest first).
/// Categories always keeps at least one of them (UX).
List<String> usableCategories({
  required Set<SpendCategory> hidden,
  required List<CustomCategory> customs,
  required bool plus,
}) => [
  for (final c in SpendCategory.values)
    if (!hidden.contains(c)) c.id,
  if (plus)
    for (final c in customs)
      if (!c.hidden) c.id,
];

/// The categories the Add sheet offers, by id, built-ins first, then your
/// own: the [usableCategories]; every built-in when none is (each hidden,
/// and your own out of the sheet once Plus ended), so the sheet never has
/// none. Each of [keep] (an edited spend's own category, the one picked) is
/// always offered in its place, even hidden or after Plus ended.
List<String> offeredCategories({
  required Set<SpendCategory> hidden,
  required List<CustomCategory> customs,
  required bool plus,
  Iterable<String> keep = const [],
}) {
  final usable = usableCategories(
    hidden: hidden,
    customs: customs,
    plus: plus,
  );
  final offered = {
    ...(usable.isEmpty ? [for (final c in SpendCategory.values) c.id] : usable),
    ...keep,
  };
  return [
    for (final c in SpendCategory.values)
      if (offered.contains(c.id)) c.id,
    for (final c in customs)
      if (offered.contains(c.id)) c.id,
  ];
}
