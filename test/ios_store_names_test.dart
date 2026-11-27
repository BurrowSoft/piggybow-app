// Apple 2.3.10 (S10): an iPhone-only string never names another store or
// platform. The iPhone-only keys end in "Ios" or "Apple" (the platform switch
// picks them on an iPhone); every shipped ARB is read.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_l10n.dart';

void main() {
  test('no iPhone-only string names Google Play, Stripe or Android', () {
    final keys = <String>{};
    for (final locale in shippedLocales()) {
      final arb =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, dynamic>;
      for (final entry in arb.entries) {
        final key = entry.key;
        if (key.startsWith('@')) continue;
        if (!key.endsWith('Ios') && !key.endsWith('Apple')) continue;
        keys.add(key);
        for (final name in ['Google Play', 'Play Store', 'Stripe', 'Android']) {
          expect(
            (entry.value as String).contains(name),
            isFalse,
            reason: '$locale: "$key" names $name',
          );
        }
      }
    }
    // v0.1 has no iPhone-only strings yet; any added later is checked here.
    expect(keys.every((k) => k.endsWith('Ios') || k.endsWith('Apple')), isTrue);
  });
}
