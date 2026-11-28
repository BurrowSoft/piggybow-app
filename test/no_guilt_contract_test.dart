import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/no_guilt.dart';

/// The pig-tip function filters the model's words with the app's own
/// no-guilt rules, through supabase/contracts/no-guilt.json. That file has
/// to say exactly what tool/no_guilt.dart says, in the same order.
void main() {
  test("supabase/contracts/no-guilt.json is tool/no_guilt.dart's list", () {
    final contract =
        jsonDecode(File('supabase/contracts/no-guilt.json').readAsStringSync())
            as Map<String, dynamic>;
    final patterns = [
      for (final p in contract['patterns'] as List)
        ((p as Map<String, dynamic>)['pattern'] as String, p['why'] as String),
    ];
    expect(patterns, [for (final b in bannedPhrases) (b.pattern, b.why)]);
  });
}
