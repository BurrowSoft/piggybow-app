import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The one source of "now" in the app. Never call DateTime.now() directly in
/// features: tests and the staging flavor pin the time through this
/// (FAKE_NOW). "Today" is the phone's live zone (LocalDay), never a stored
/// one.
class Clock {
  Clock({DateTime? fixed}) : _fixed = fixed?.toUtc() {
    _ensureTimeZones();
  }

  final DateTime? _fixed;

  static bool _loaded = false;
  static void _ensureTimeZones() {
    if (_loaded) return;
    tzdata.initializeTimeZones();
    _loaded = true;
  }

  DateTime nowUtc() => _fixed ?? DateTime.now().toUtc();

  /// [name] when the zone database knows it. Otherwise (the platform gave no
  /// zone, or one this database doesn't have) a zone at [offset] from UTC
  /// now, so "today" is still the phone's day: `Etc/GMT-7` for UTC+7 (the Etc
  /// zones' sign is inverted), or for a part hour the first zone by name at
  /// that offset now (+5:30, +5:45). UTC only at +0 or when nothing matches.
  static String knownZoneOr(String? name, Duration offset) {
    _ensureTimeZones();
    final zones = tz.timeZoneDatabase.locations;
    if (name != null && zones.containsKey(name)) return name;
    final h = offset.inHours;
    if (offset.inMinutes % 60 == 0 && h >= -12 && h <= 14) {
      return h == 0 ? 'UTC' : 'Etc/GMT${h > 0 ? '-' : '+'}${h.abs()}';
    }
    for (final zone in zones.keys.toList()..sort()) {
      if (zones[zone]!.currentTimeZone.offset == offset) return zone;
    }
    return 'UTC';
  }

  /// Now in [timeZone]; an unknown zone falls back to UTC.
  tz.TZDateTime nowIn(String timeZone) {
    final location = _location(timeZone);
    return tz.TZDateTime.from(nowUtc(), location);
  }

  /// The user's local calendar date (a date-only DateTime, no time part).
  DateTime todayIn(String timeZone) => dateOnly(nowIn(timeZone));

  /// The calendar date of [instant] in [timeZone] (unknown or null → UTC).
  static DateTime localDateOf(DateTime instant, String? timeZone) {
    _ensureTimeZones();
    return dateOnly(
      tz.TZDateTime.from(instant.toUtc(), _location(timeZone ?? 'UTC')),
    );
  }

  /// [instant] as wall-clock time in [timeZone] (unknown or null → UTC).
  static tz.TZDateTime inZone(DateTime instant, String? timeZone) {
    _ensureTimeZones();
    return tz.TZDateTime.from(instant.toUtc(), _location(timeZone ?? 'UTC'));
  }

  /// The instant of wall-clock [day] at [hour]:00 in [timeZone] (unknown or
  /// null → UTC); [day]'s time part is ignored. 1.4 H's windows.
  static tz.TZDateTime wallClock(DateTime day, int hour, String? timeZone) {
    _ensureTimeZones();
    return tz.TZDateTime(
      _location(timeZone ?? 'UTC'),
      day.year,
      day.month,
      day.day,
      hour,
    );
  }

  static tz.Location _location(String name) {
    try {
      return tz.getLocation(name);
    } on Object {
      return tz.UTC;
    }
  }
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// `YYYY-MM-DD`, as Postgres `date` takes it.
String wireDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// [day] moved by [days] calendar days. Never `Duration(days:)` on dates: across
/// a DST change in the device zone that lands at 23:00 / 01:00 and
/// wireDate drifts by a day.
DateTime addDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

/// A strict `YYYY-MM-DD` (a route parameter) → that date, else null.
/// Rejects impossible dates (2026-02-30) instead of rolling them over.
DateTime? parseWireDate(String? s) {
  if (s == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return null;
  final d = DateTime.tryParse(s);
  return d != null && wireDate(d) == s ? dateOnly(d) : null;
}

/// "Your week" (1.1 D): the Monday of the last complete week (Monday–Sunday)
/// before [today], as the report function and the DB compute it
/// (report/prompt.ts lastWeekStart, public._last_week_start).
DateTime lastWeekStart(DateTime today) =>
    addDays(dateOnly(today), -((today.weekday - 1) % 7) - 7);
