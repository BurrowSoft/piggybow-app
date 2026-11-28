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
    required this.madeThrough,
    required this.createdAt,
    required this.updatedAt,
    this.category,
    this.note = '',
    this.stoppedOn,
  });

  /// A uuid, made on the phone.
  final String id;
  final EntryType type;

  /// > 0, in minor units.
  final int amountMinor;
  final String currency;

  /// Spends only.
  final SpendCategory? category;

  /// Up to 80 characters; may be empty. Its entries get it too.
  final String note;
  final RepeatSchedule schedule;

  /// The first entry's day, `YYYY-MM-DD`.
  final String firstDate;

  /// The last day already dealt with, `YYYY-MM-DD`: entries come only for
  /// the days after it. It only ever moves forward.
  final String madeThrough;

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
    'category': category?.id,
    'note': note,
    'kind': schedule.kind.id,
    'day': schedule.day,
    'first_date': firstDate,
    'made_through': madeThrough,
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
      if (amount is! int || amount <= 0 || day is! int) return null;
      final schedule = switch (kind) {
        RepeatKind.monthly => RepeatSchedule.monthly(day),
        RepeatKind.weekly => RepeatSchedule.weekly(day),
      };
      final firstDate = m['first_date'] as String;
      final madeThrough = m['made_through'] as String;
      final stoppedOn = m['stopped_on'] as String?;
      if (!schedule.isValid ||
          parseWireDate(firstDate) == null ||
          parseWireDate(madeThrough) == null ||
          (stoppedOn != null && parseWireDate(stoppedOn) == null)) {
        return null;
      }
      final category = type == EntryType.spent
          ? SpendCategory.fromId(m['category'])
          : null;
      if (type == EntryType.spent && category == null) return null;
      return Repeat(
        id: id,
        type: type,
        amountMinor: amount,
        currency: m['currency'] as String,
        category: category,
        note: (m['note'] as String?) ?? '',
        schedule: schedule,
        firstDate: firstDate,
        madeThrough: madeThrough,
        createdAt: DateTime.parse(m['created_at'] as String).toUtc(),
        updatedAt: DateTime.parse(m['updated_at'] as String).toUtc(),
        stoppedOn: stoppedOn,
      );
    } on Object {
      return null;
    }
  }

  Repeat copyWith({
    int? amountMinor,
    SpendCategory? category,
    String? note,
    RepeatSchedule? schedule,
    String? madeThrough,
    DateTime? updatedAt,
    String? stoppedOn,
  }) => Repeat(
    id: id,
    type: type,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency,
    category: type == EntryType.spent ? (category ?? this.category) : null,
    note: note ?? this.note,
    schedule: schedule ?? this.schedule,
    firstDate: firstDate,
    madeThrough: madeThrough ?? this.madeThrough,
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
      other.note == note &&
      other.schedule == schedule &&
      other.firstDate == firstDate &&
      other.madeThrough == madeThrough &&
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
    note,
    schedule,
    firstDate,
    madeThrough,
    createdAt,
    updatedAt,
    stoppedOn,
  );
}
