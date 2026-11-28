import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every link the app shows opens in the browser, outside Piggybow. A web
/// view inside the app would load the page in Piggybow itself, and a
/// release build reaches the network for pig tips only.
void main() {
  test('every launchUrl opens outside the app', () {
    var links = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      final calls = 'launchUrl('.allMatches(src).length;
      links += calls;
      expect(
        'mode: LaunchMode.externalApplication'.allMatches(src).length,
        calls,
        reason: f.path,
      );
      expect(src, isNot(contains('launchUrlString(')), reason: f.path);
      expect(
        RegExp(r'LaunchMode\.(?!externalApplication\b)').hasMatch(src),
        isFalse,
        reason: f.path,
      );
    }
    expect(links, greaterThanOrEqualTo(1), reason: 'launchUrl calls found');
  });
}
