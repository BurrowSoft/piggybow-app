import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// The spend categories of v0.1 (custom ones come later). [id] is stored,
/// exported in the CSV and used in test ids (`add-cat-<id>`).
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
