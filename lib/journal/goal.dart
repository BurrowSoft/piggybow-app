import 'package:flutter/foundation.dart';

/// A goal's state (`status`). One goal is active at a time.
enum GoalStatus {
  active('active'),
  reached('reached'),
  ended('ended');

  const GoalStatus(this.id);

  final String id;

  static GoalStatus? fromId(Object? id) =>
      values.where((s) => s.id == id).firstOrNull;
}

/// A savings goal, as stored on the phone. Amounts are integer minor units.
/// Its progress is [startMinor] plus the saves that name it; the rainbow's
/// bands and the reached celebration are sticky ([bandReachedAt],
/// [reachedAt]): once set, never unset.
@immutable
class Goal {
  const Goal({
    required this.id,
    required this.name,
    required this.targetMinor,
    required this.createdAt,
    required this.updatedAt,
    this.startMinor = 0,
    this.status = GoalStatus.active,
    this.bandReachedAt = const [null, null, null, null, null],
    this.reachedAt,
  }) : assert(bandReachedAt.length == 5);

  final String id;

  /// Up to 40 characters.
  final String name;

  /// > 0.
  final int targetMinor;

  /// "Already saved" when the goal was made, ≥ 0.
  final int startMinor;
  final GoalStatus status;

  /// Band i (1–5) = index i − 1: when it first completed (UTC), else null.
  final List<DateTime?> bandReachedAt;

  /// When the target was first reached (UTC).
  final DateTime? reachedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// This goal with some fields changed. The stamps are sticky, so there's
  /// no way to clear them here.
  Goal copyWith({
    String? name,
    int? targetMinor,
    int? startMinor,
    GoalStatus? status,
    List<DateTime?>? bandReachedAt,
    DateTime? reachedAt,
    DateTime? updatedAt,
  }) => Goal(
    id: id,
    name: name ?? this.name,
    targetMinor: targetMinor ?? this.targetMinor,
    startMinor: startMinor ?? this.startMinor,
    status: status ?? this.status,
    bandReachedAt: bandReachedAt ?? this.bandReachedAt,
    reachedAt: reachedAt ?? this.reachedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'name': name,
    'target_minor': targetMinor,
    'start_minor': startMinor,
    'status': status.id,
    'band_reached_at': [
      for (final t in bandReachedAt) t?.toUtc().toIso8601String(),
    ],
    'reached_at': reachedAt?.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  /// Null for a record this build can't read.
  static Goal? fromMap(String id, Map<String, Object?> m) {
    try {
      final status = GoalStatus.fromId(m['status']);
      final target = m['target_minor'];
      final start = m['start_minor'] ?? 0;
      final bands =
          (m['band_reached_at'] as List?) ??
          const [null, null, null, null, null];
      if (status == null || target is! int || target <= 0) return null;
      if (start is! int || start < 0 || bands.length != 5) return null;
      DateTime? at(Object? s) =>
          s == null ? null : DateTime.parse(s as String).toUtc();
      return Goal(
        id: id,
        name: m['name'] as String,
        targetMinor: target,
        startMinor: start,
        status: status,
        bandReachedAt: [for (final b in bands) at(b)],
        reachedAt: at(m['reached_at']),
        createdAt: at(m['created_at'])!,
        updatedAt: at(m['updated_at'])!,
      );
    } on Object {
      return null;
    }
  }
}
