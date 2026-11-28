import 'package:flutter/foundation.dart';

import '../core/clock.dart';
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
  });

  /// A uuid, made on the phone.
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
  };

  /// Null for a record this build can't read (never a half-read entry).
  static Entry? fromMap(String id, Map<String, Object?> m) {
    try {
      final type = EntryType.fromId(m['type']);
      final amount = m['amount_minor'];
      final localDate = m['local_date'] as String;
      if (type == null || amount is! int || amount <= 0) return null;
      if (parseWireDate(localDate) == null) return null;
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
  }) => Entry(
    id: id,
    type: type ?? this.type,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency,
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
      other.updatedAt == updatedAt;

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
  );
}
