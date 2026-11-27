import 'dart:math' show Random;

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/money/money.dart';

void main() {
  test('10,000 amounts add up exactly, and the per-category totals add up to the grand total', () {
    final r = Random(28);
    const categories = ['food', 'groceries', 'transport', 'home', 'shopping', 'fun', 'health', 'gifts', 'other'];
    final byCategory = {for (final c in categories) c: 0};
    var total = 0;
    var reference = BigInt.zero;
    for (var i = 0; i < 10000; i++) {
      // Up to the 12-digit cap, built from two smaller random parts.
      final minor = 1 + (r.nextInt(1000000) * 1000000 + r.nextInt(1000000)) % maxAmountMinor;
      final category = categories[r.nextInt(categories.length)];
      byCategory[category] = byCategory[category]! + minor;
      total += minor;
      reference += BigInt.from(minor);
    }
    expect(BigInt.from(total), reference);
    expect(byCategory.values.fold<int>(0, (a, b) => a + b), total);
    expect(formatMoney(total, 'USD', 'en_US').replaceAll(RegExp(r'[$,]'), ''), plainAmount(total, 'USD'));
  });

  test('a total past 2^53 (where floating point rounds) still shows every digit', () {
    var total = 0;
    for (var i = 0; i < 10000; i++) {
      total += maxAmountMinor;
    }
    expect(total, 9999999999990000);
    expect(total > (1 << 53), isTrue);
    expect(plainAmount(total, 'USD'), '99999999999900.00');
    expect(formatMoney(total, 'USD', 'en_US'), r'$99,999,999,999,900.00');
  });
}
