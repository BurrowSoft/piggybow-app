import 'package:flutter/foundation.dart';

import '../core/clock.dart';
import '../money/rate.dart';
import 'category.dart';

/// Spent, saved, or taken out of a goal's savings (`type`).
enum EntryType {
  spent('spent'),
  saved('saved'),

  /// Money taken out of a goal's savings: never a spend, never negative
  /// (a positive amount, the goal's progress goes down by it).
  withdraw('withdraw');

  const EntryType(this.id);

  /// The stored value (and the CSV's).
  final String id;

  static EntryType? fromId(Object? id) =>
      values.where((t) => t.id == id).firstOrNull;
}

/// "Worth it?" on a spend (`feeling`); none is fine.
enum Feeling {
  worthIt('worth_it'),
  notSure('not_sure'),
  notReally('not_really');

  const Feeling(this.id);

  /// The stored value (and the CSV's).
  final String id;

  static Feeling? fromId(Object? id) =>
      values.where((f) => f.id == id).firstOrNull;
}

/// One spend or save, as stored on the phone. Money is an integer number of
/// minor units ([amountMinor], e.g. satang or cents) with its ISO 4217
/// [currency]; never a double anywhere.
///
/// In another currency than the journal's (a trip, feature 19), it also
/// keeps the [rate] typed and [convertedMinor], its amount in the home
/// currency, converted once when it was saved. Every total counts
/// [homeMinor].
@immutable
class Entry {
  const Entry({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.currency,
    required this.localDate,
    required this.createdAt,
    required this.updatedAt,
    this.category,
    this.customCategory,
    this.feeling,
    this.note = '',
    this.goalId,
    this.repeatId,
    this.auto = false,
    this.rate,
    this.convertedMinor,
  }) : assert((rate == null) == (convertedMinor == null));

  /// A uuid, made on the phone (for an entry a repeat added, its repeat and
  /// day: see repeatEntryId).
  final String id;
  final EntryType type;

  /// > 0, in minor units.
  final int amountMinor;
  final String currency;

  /// Spends only: a built-in category, or [customCategory] (one of them).
  final SpendCategory? category;

  /// Spends only: the id of a category of your own (Plus, decision 79),
  /// "c:…"; null with a built-in [category].
  final String? customCategory;

  /// The spend's category id, built-in or your own (Summary, the CSV).
  String? get categoryId => category?.id ?? customCategory;

  /// Spends only; null = not answered.
  final Feeling? feeling;

  /// Up to 80 characters; may be empty.
  final String note;

  /// A save's goal (null when there was none), or the goal a withdrawal was
  /// taken out of (always one).
  final String? goalId;

  /// The repeat it belongs to, its first entry included; null for most.
  final String? repeatId;

  /// True when a repeat added it, not the person: it's money like any
  /// entry, but not something the person wrote (the pig's "recently", the
  /// reminder's "added today" and the questions about a day leave it out).
  final bool auto;

  /// In another currency: the rate typed. Null in the home currency.
  final Rate? rate;

  /// In another currency: the amount in the home currency's minor units,
  /// frozen when it was saved. Null in the home currency.
  final int? convertedMinor;

  /// The amount in the journal's home currency: what every total counts.
  int get homeMinor => convertedMinor ?? amountMinor;

  /// The day the person picked, `YYYY-MM-DD`: never derived from a time.
  final String localDate;

  /// UTC.
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isSpend => type == EntryType.spent;

  /// [localDate] as a date (midnight, no zone).
  DateTime get date => parseWireDate(localDate)!;

  Map<String, Object?> toMap() => {
    'type': type.id,
    'amount_minor': amountMinor,
    'currency': currency,
    // One field for both: a built-in's id ("food") or your own's ("c:…").
    'category': categoryId,
    'feeling': feeling?.id,
    'note': note,
    'goal_id': goalId,
    'local_date': localDate,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'repeat_id': repeatId,
    'auto': auto,
    // Only in another currency, so a home-currency record is as before.
    if (rate != null) 'rate': rate!.toMap(),
    if (convertedMinor != null) 'home_minor': convertedMinor,
  };

  /// Null for a record this build can't read (never a half-read entry).
  static Entry? fromMap(String id, Map<String, Object?> m) {
    try {
      final type = EntryType.fromId(m['type']);
      final amount = m['amount_minor'];
      final localDate = m['local_date'] as String;
      if (type == null || amount is! int || amount <= 0) return null;
      if (parseWireDate(localDate) == null) return null;
      // Both or neither: a rate without its amount, or the reverse, is never
      // read as a guess.
      final storedRate = m['rate'];
      final converted = m['home_minor'];
      if ((storedRate == null) != (converted == null)) return null;
      final rate = Rate.fromMap(storedRate);
      if (storedRate != null && (rate == null || converted is! int || converted <= 0)) {
        return null;
      }
      return Entry(
        id: id,
        type: type,
        amountMinor: amount,
        currency: m['currency'] as String,
        category: type == EntryType.spent
            ? SpendCategory.fromId(m['category'])
            : null,
        customCategory:
            type == EntryType.spent && CustomCategory.isCustomId(m['category'])
            ? m['category'] as String
            : null,
        feeling: type == EntryType.spent ? Feeling.fromId(m['feeling']) : null,
        note: (m['note'] as String?) ?? '',
        goalId: type == EntryType.spent ? null : m['goal_id'] as String?,
        localDate: localDate,
        createdAt: DateTime.parse(m['created_at'] as String).toUtc(),
        updatedAt: DateTime.parse(m['updated_at'] as String).toUtc(),
        // Older entries have neither: no repeat, written by the person.
        repeatId: m['repeat_id'] as String?,
        auto: m['auto'] == true,
        rate: rate,
        convertedMinor: converted as int?,
      );
    } on Object {
      return null;
    }
  }

  /// A built-in [category] replaces a [customCategory] and the other way
  /// round; [clearCategory] clears both.
  Entry copyWith({
    EntryType? type,
    int? amountMinor,
    SpendCategory? category,
    String? customCategory,
    bool clearCategory = false,
    Feeling? feeling,
    bool clearFeeling = false,
    String? note,
    String? goalId,
    bool clearGoal = false,
    String? localDate,
    DateTime? updatedAt,
    String? currency,
    Rate? rate,
    int? convertedMinor,
    bool clearRate = false,
  }) => Entry(
    id: id,
    type: type ?? this.type,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency ?? this.currency,
    category: clearCategory || customCategory != null
        ? null
        : (category ?? this.category),
    customCategory: clearCategory || category != null
        ? null
        : (customCategory ?? this.customCategory),
    feeling: clearFeeling ? null : (feeling ?? this.feeling),
    note: note ?? this.note,
    goalId: clearGoal ? null : (goalId ?? this.goalId),
    localDate: localDate ?? this.localDate,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    repeatId: repeatId,
    auto: auto,
    rate: clearRate ? null : (rate ?? this.rate),
    convertedMinor: clearRate ? null : (convertedMinor ?? this.convertedMinor),
  );

  @override
  bool operator ==(Object other) =>
      other is Entry &&
      other.id == id &&
      other.type == type &&
      other.amountMinor == amountMinor &&
      other.currency == currency &&
      other.category == category &&
      other.customCategory == customCategory &&
      other.feeling == feeling &&
      other.note == note &&
      other.goalId == goalId &&
      other.localDate == localDate &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.repeatId == repeatId &&
      other.auto == auto &&
      other.rate == rate &&
      other.convertedMinor == convertedMinor;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    amountMinor,
    currency,
    category,
    customCategory,
    feeling,
    note,
    goalId,
    localDate,
    createdAt,
    updatedAt,
    repeatId,
    auto,
    rate,
    convertedMinor,
  );
}
