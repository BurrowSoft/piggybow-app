import 'package:flutter/foundation.dart';

import '../core/clock.dart';
import '../journal/category.dart';
import '../journal/entry.dart';

/// How a repeat comes back (`kind`).
enum RepeatKind {
  monthly('monthly'),
  weekly('weekly');

  const RepeatKind(this.id);

  /// The stored value (and the CSV's).
  final String id;

  static RepeatKind? fromId(Object? id) =>
      values.where((k) => k.id == id).firstOrNull;
}

/// When a repeat comes back.
///
/// Monthly: on [day] 1 to 31 of every month, and on the month's last day in
/// a month without that day, so 31 is always the last day. Weekly: on the
/// weekday [day], 1 (Monday) to 7 (Sunday), as `DateTime.weekday` counts.
@immutable
class RepeatSchedule {
  const RepeatSchedule.monthly(this.day) : kind = RepeatKind.monthly;
  const RepeatSchedule.weekly(this.day) : kind = RepeatKind.weekly;

  /// The day of the month (monthly) or the weekday (weekly) of [date].
  factory RepeatSchedule.from(RepeatKind kind, DateTime date) =>
      switch (kind) {
        RepeatKind.monthly => RepeatSchedule.monthly(date.day),
        RepeatKind.weekly => RepeatSchedule.weekly(date.weekday),
      };

  /// Every month on the last day (the end of the month).
  static const lastDay = RepeatSchedule.monthly(31);

  final RepeatKind kind;
  final int day;

  bool get isValid => switch (kind) {
    RepeatKind.monthly => day >= 1 && day <= 31,
    RepeatKind.weekly => day >= 1 && day <= 7,
  };

  @override
  bool operator ==(Object other) =>
      other is RepeatSchedule && other.kind == kind && other.day == day;

  @override
  int get hashCode => Object.hash(kind, day);

  @override
  String toString() => '${kind.id}:$day';
}

/// A spend or a save that comes back on a schedule, as stored on the phone.
/// Its first entry is one the person added; after that, the journal adds one
/// on each of its days, the next time the app is open (never ahead of time).
/// Money is an integer number of minor units, as in an entry.
@immutable
class Repeat {
  const Repeat({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.currency,
    required this.schedule,
    required this.firstDate,
    required this.startedOn,
    required this.madeThrough,
    required this.createdAt,
    required this.updatedAt,
    this.category,
    this.customCategory,
    this.goalId,
    this.note = '',
    this.skipThrough,
    this.stoppedOn,
  });

  /// A uuid, made on the phone.
  final String id;
  final EntryType type;

  /// > 0, in minor units.
  final int amountMinor;
  final String currency;

  /// Spends only: a built-in category, or [customCategory] (one of them).
  final SpendCategory? category;

  /// Spends only: the id of a category of your own (Plus), "c:…"; null with
  /// a built-in [category]. Its entries go there even once it's hidden or
  /// Plus has ended, as any entry keeps its category.
  final String? customCategory;

  /// The spend's category id, built-in or your own.
  String? get categoryId => category?.id ?? customCategory;

  /// Saves only: the goal its first entry went to, or null (none). Its saves
  /// go there while that goal is active, then to none: never to a goal the
  /// person didn't pick.
  final String? goalId;

  /// Up to 80 characters; may be empty. Its entries get it too.
  final String note;
  final RepeatSchedule schedule;

  /// The first entry's day, `YYYY-MM-DD`.
  final String firstDate;

  /// The day it was made, `YYYY-MM-DD` (its first entry's day when that's
  /// later): it never adds that day or one before.
  final String startedOn;

  /// The last day already dealt with, `YYYY-MM-DD`: entries come only for
  /// the days after it. It moves forward with each catch-up, and back only
  /// when it's further after today than any time zone explains (a clock that
  /// was set ahead, then put right).
  final String madeThrough;

  /// After a schedule change, the last day the new schedule skips,
  /// `YYYY-MM-DD`: the end of the month (or week) that already has the old
  /// schedule's last entry. Null when nothing is skipped.
  final String? skipThrough;

  /// UTC.
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The day it was stopped, `YYYY-MM-DD`, or null while it runs. A stopped
  /// repeat is kept, so the entries it added can still say what made them.
  final String? stoppedOn;

  bool get running => stoppedOn == null;

  Map<String, Object?> toMap() => {
    'type': type.id,
    'amount_minor': amountMinor,
    'currency': currency,
    // One field for both, as an entry's: a built-in's id ("food") or your
    // own's ("c:…").
    'category': categoryId,
    'goal_id': goalId,
    'note': note,
    'kind': schedule.kind.id,
    'day': schedule.day,
    'first_date': firstDate,
    'started_on': startedOn,
    'made_through': madeThrough,
    'skip_through': skipThrough,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'stopped_on': stoppedOn,
  };

  /// Null for a record this build can't read (never a half-read repeat).
  static Repeat? fromMap(String id, Map<String, Object?> m) {
    try {
      final type = EntryType.fromId(m['type']);
      final kind = RepeatKind.fromId(m['kind']);
      final amount = m['amount_minor'];
      final day = m['day'];
      if (type == null || kind == null) return null;
      // A repeat is a spend or a save, never any other kind of entry.
      if (type != EntryType.spent && type != EntryType.saved) return null;
      if (amount is! int || amount <= 0 || day is! int) return null;
      final schedule = switch (kind) {
        RepeatKind.monthly => RepeatSchedule.monthly(day),
        RepeatKind.weekly => RepeatSchedule.weekly(day),
      };
      final firstDate = m['first_date'] as String;
      final startedOn = m['started_on'] as String;
      final madeThrough = m['made_through'] as String;
      final skipThrough = m['skip_through'] as String?;
      final stoppedOn = m['stopped_on'] as String?;
      bool date(String? s) => s == null || parseWireDate(s) != null;
      if (!schedule.isValid ||
          parseWireDate(firstDate) == null ||
          parseWireDate(startedOn) == null ||
          parseWireDate(madeThrough) == null ||
          !date(skipThrough) ||
          !date(stoppedOn)) {
        return null;
      }
      final spend = type == EntryType.spent;
      final category = spend ? SpendCategory.fromId(m['category']) : null;
      final custom = spend && CustomCategory.isCustomId(m['category'])
          ? m['category'] as String
          : null;
      if (spend && category == null && custom == null) return null;
      // Older records have none: their saves go to none.
      final goalId = type == EntryType.saved ? (m['goal_id'] as String?) : null;
      return Repeat(
        id: id,
        type: type,
        amountMinor: amount,
        currency: m['currency'] as String,
        category: category,
        customCategory: custom,
        goalId: goalId,
        note: (m['note'] as String?) ?? '',
        schedule: schedule,
        firstDate: firstDate,
        startedOn: startedOn,
        madeThrough: madeThrough,
        skipThrough: skipThrough,
        createdAt: DateTime.parse(m['created_at'] as String).toUtc(),
        updatedAt: DateTime.parse(m['updated_at'] as String).toUtc(),
        stoppedOn: stoppedOn,
      );
    } on Object {
      return null;
    }
  }

  /// A built-in [category] replaces a [customCategory] and the other way
  /// round; a save has neither.
  Repeat copyWith({
    int? amountMinor,
    SpendCategory? category,
    String? customCategory,
    String? note,
    RepeatSchedule? schedule,
    String? madeThrough,
    String? skipThrough,
    bool clearSkip = false,
    DateTime? updatedAt,
    String? stoppedOn,
  }) => Repeat(
    id: id,
    type: type,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency,
    category: type != EntryType.spent || customCategory != null
        ? null
        : (category ?? this.category),
    customCategory: type != EntryType.spent || category != null
        ? null
        : (customCategory ?? this.customCategory),
    goalId: goalId,
    note: note ?? this.note,
    schedule: schedule ?? this.schedule,
    firstDate: firstDate,
    startedOn: startedOn,
    madeThrough: madeThrough ?? this.madeThrough,
    skipThrough: clearSkip ? null : (skipThrough ?? this.skipThrough),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    stoppedOn: stoppedOn ?? this.stoppedOn,
  );

  @override
  bool operator ==(Object other) =>
      other is Repeat &&
      other.id == id &&
      other.type == type &&
      other.amountMinor == amountMinor &&
      other.currency == currency &&
      other.category == category &&
      other.customCategory == customCategory &&
      other.goalId == goalId &&
      other.note == note &&
      other.schedule == schedule &&
      other.firstDate == firstDate &&
      other.startedOn == startedOn &&
      other.madeThrough == madeThrough &&
      other.skipThrough == skipThrough &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.stoppedOn == stoppedOn;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    amountMinor,
    currency,
    category,
    customCategory,
    goalId,
    note,
    schedule,
    firstDate,
    startedOn,
    madeThrough,
    skipThrough,
    createdAt,
    updatedAt,
    stoppedOn,
  );
}
