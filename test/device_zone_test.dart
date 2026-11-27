import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/clock.dart';
import 'package:timezone/timezone.dart' as tz;

/// When the phone gives no zone, or one the zone database lacks, "today"
/// still follows the phone's offset (never plain UTC for a phone far from
/// it).
void main() {
  test('a known zone is kept, whatever the offset', () {
    expect(Clock.knownZoneOr('Asia/Bangkok', Duration.zero), 'Asia/Bangkok');
  });

  test('whole hours: the Etc zones, sign inverted; UTC only at +0', () {
    expect(Clock.knownZoneOr(null, const Duration(hours: 7)), 'Etc/GMT-7');
    expect(
      Clock.knownZoneOr('Mars/Base', const Duration(hours: 7)),
      'Etc/GMT-7',
    );
    expect(Clock.knownZoneOr(null, const Duration(hours: -3)), 'Etc/GMT+3');
    expect(Clock.knownZoneOr(null, const Duration(hours: 14)), 'Etc/GMT-14');
    expect(Clock.knownZoneOr(null, const Duration(hours: -12)), 'Etc/GMT+12');
    expect(Clock.knownZoneOr(null, Duration.zero), 'UTC');
    expect(
      tz.getLocation('Etc/GMT-7').currentTimeZone.offset,
      const Duration(hours: 7),
    );
  });

  test('a part hour: a zone at that offset now, never UTC', () {
    for (final offset in const [
      Duration(hours: 5, minutes: 30),
      Duration(hours: 5, minutes: 45),
      Duration(hours: -9, minutes: -30),
    ]) {
      final zone = Clock.knownZoneOr(null, offset);
      expect(zone, isNot('UTC'), reason: '$offset');
      expect(tz.getLocation(zone).currentTimeZone.offset, offset, reason: zone);
    }
  });

  test("the zone it gives is the phone's day", () {
    // 18:45 UTC on 1 October is already 2 October at +7 and at +5:30.
    final clock = Clock(fixed: DateTime.utc(2026, 10, 1, 18, 45));
    for (final offset in const [
      Duration(hours: 7),
      Duration(hours: 5, minutes: 30),
    ]) {
      expect(
        clock.todayIn(Clock.knownZoneOr(null, offset)),
        DateTime(2026, 10, 2),
        reason: '$offset',
      );
    }
    expect(clock.todayIn('UTC'), DateTime(2026, 10, 1));
  });
}
