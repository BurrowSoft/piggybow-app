import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/core/device.dart';
import 'package:piggybow/core/local_day.dart';

import 'helpers.dart';

/// "Today" is the phone's live zone (plan §0.4): read at start and on every
/// resume, never stored at first open, never a UTC fallback.
class ZoneDevice implements DeviceContext {
  ZoneDevice(this.zone);

  /// The zone the phone is in now (a test moves it).
  String zone;

  @override
  Future<String> timeZone() async => zone;

  @override
  String? get countryCode => 'TH';

  @override
  String get languageCode => 'en';

  @override
  String get localeName => 'en_US';
}

void main() {
  test('at UTC+14 and UTC−11 the same instant is two different days', () async {
    // 10:30 UTC on 2 October: 00:30 on the 3rd in Kiritimati, 23:30 on the
    // 1st in Niue.
    final clock = Clock(fixed: DateTime.utc(2026, 10, 2, 10, 30));
    final east = LocalDay(
      clock: clock,
      device: ZoneDevice('Pacific/Kiritimati'),
    );
    final west = LocalDay(clock: clock, device: ZoneDevice('Pacific/Niue'));
    await east.refresh();
    await west.refresh();
    expect(east.todayWire, '2026-10-03');
    expect(west.todayWire, '2026-10-01');
  });

  test('in Bangkok the day turns at local midnight, not at 07:00', () async {
    // The source app read the zone once, as UTC, so its day turned at 07:00.
    final clock = MovableClock(DateTime.utc(2026, 10, 1, 23, 59)); // 06:59
    final day = LocalDay(clock: clock, device: ZoneDevice('Asia/Bangkok'));
    await day.refresh();
    expect(day.todayWire, '2026-10-02');
    clock.now = DateTime.utc(2026, 10, 2); // 07:00
    expect(day.todayWire, '2026-10-02');
    clock.now = DateTime.utc(2026, 10, 2, 16, 59); // 23:59
    expect(day.todayWire, '2026-10-02');
    clock.now = DateTime.utc(2026, 10, 2, 17); // 00:00 on the 3rd
    expect(day.todayWire, '2026-10-03');
  });

  test(
    'a zone change while away moves today at the next read (resume)',
    () async {
      // 20:00 UTC: 03:00 on the 3rd in Bangkok, 21:00 on the 2nd in London.
      final clock = Clock(fixed: DateTime.utc(2026, 10, 2, 20));
      final device = ZoneDevice('Asia/Bangkok');
      final day = LocalDay(clock: clock, device: device);
      await day.refresh();
      expect(day.todayWire, '2026-10-03');
      var heard = 0;
      day.addListener(() => heard++);

      device.zone = 'Europe/London';
      expect(
        day.todayWire,
        '2026-10-03',
        reason: 'until the zone is read again',
      );
      await day.refresh();
      expect(day.zone, 'Europe/London');
      expect(day.todayWire, '2026-10-02');
      expect(heard, 1, reason: 'listeners hear the change');

      await day.refresh();
      expect(heard, 1, reason: 'the same zone again is no news');
    },
  );
}
