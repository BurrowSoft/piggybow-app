import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:piggybow/core/app_dates.dart';

/// Decision 193: Thai UI dates in the Buddhist era (2026 → 2569); every
/// other locale unchanged; the weekday never shifts.
void main() {
  setUpAll(initializeDateFormatting);
  final d = DateTime(2026, 10, 2); // a Friday

  test('Thai: Buddhist-era year, right weekday', () {
    for (final l in ['th', 'th_TH']) {
      expect(AppDates.full(l, d), 'วันศุกร์ที่ 2 ตุลาคม 2569');
      expect(AppDates.monthYear(l, d), 'ตุลาคม 2569');
      expect(AppDates.dayShort(l, d), 'ศุกร์ 2 ต.ค.');
      expect(AppDates.year(l, 2026), '2569');
    }
  });

  test("the year card's title year: Thai Buddhist era, else Gregorian", () {
    expect(AppDates.year('th', 2026), '2569');
    expect(AppDates.year('en_US', 2026), '2026');
    expect(AppDates.year('en_GB', 2026), '2026');
  });

  test('other locales: Gregorian, as before (decision 89)', () {
    expect(AppDates.full('en_US', d), 'Friday, October 2, 2026');
    expect(AppDates.full('en_GB', d), 'Friday, 2 October 2026');
    expect(AppDates.monthYear('en_US', d), 'October 2026');
  });

  test('only Thai uses the Buddhist era', () {
    expect(AppDates.usesBuddhistEra('th'), isTrue);
    expect(AppDates.usesBuddhistEra('th_TH'), isTrue);
    expect(AppDates.usesBuddhistEra('en_TH'), isFalse);
    expect(AppDates.usesBuddhistEra('the'), isFalse);
  });
}
