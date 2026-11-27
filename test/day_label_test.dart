import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/day_label.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';

/// The one way the UI names a day (decision 48): Timeline's day headers and
/// a goal's saves.
void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });
  final friday = DateTime(2026, 10, 2);
  String label(DateTime day, {DateTime? today}) =>
      dayLabel(l10n, 'en_US', day, today: today ?? friday);

  test('Today, Yesterday, then the weekday and date', () {
    expect(label(DateTime(2026, 10, 2)), 'Today');
    expect(label(DateTime(2026, 10, 1)), 'Yesterday');
    expect(label(DateTime(2026, 9, 30)), 'Wed, Sep 30');
    expect(label(DateTime(2026, 1, 1)), 'Thu, Jan 1');
  });

  test('the year only for a day in another year', () {
    expect(label(DateTime(2025, 12, 31)), 'Wed, Dec 31, 2025');
    expect(label(DateTime(2025, 10, 2)), 'Thu, Oct 2, 2025');
  });

  test('Yesterday across a month and a year', () {
    expect(
      label(DateTime(2026, 9, 30), today: DateTime(2026, 10, 1)),
      'Yesterday',
    );
    expect(
      label(DateTime(2025, 12, 31), today: DateTime(2026, 1, 1)),
      'Yesterday',
    );
  });

  test('a UTC date names the same day', () {
    expect(label(DateTime.utc(2026, 10, 2)), 'Today');
    expect(label(DateTime.utc(2026, 10, 1)), 'Yesterday');
  });
}
