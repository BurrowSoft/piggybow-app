import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Plus runs on the phone (decisions 3 and 79): the store's own answer is
/// the truth. No server checks a purchase, nothing ties a purchase to a
/// person (there is no account), and a price is only ever the store's own
/// formatted text, never the plugin's double (money is never a float).
void main() {
  test('no app code checks a purchase on a server, ties it to a person, or '
      "reads the store's price as a double", () {
    const banned = {
      'rawPrice': "the store's price as a double",
      'applicationUserName': 'a purchase tied to a person',
      'obfuscatedAccountId': 'a purchase tied to a person',
      'appAccountToken': 'a purchase tied to a person',
      'verifyPurchase': 'a purchase checked on a server',
      'plus-store': 'a purchase checked on a server',
    };
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(sources, isNotEmpty);
    final hits = <String>[];
    for (final f in sources) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final MapEntry(key: word, value: why) in banned.entries) {
          if (lines[i].contains(word)) hits.add('${f.path}:${i + 1} $word ($why)');
        }
      }
    }
    expect(hits, isEmpty);
  });
}
