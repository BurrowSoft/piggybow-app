import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Plus never runs in a release build until its own release PR lifts this
/// with its gates met (decision 79). The Dart guard covers Android and the
/// iPhone alike; the Android build's own refusal is pinned in
/// release_no_network_test.dart.
void main() {
  test('PLUS_ENABLED counts only outside release builds, and is read once', () {
    final config = File('lib/core/app_config.dart').readAsStringSync();
    expect(
      config,
      contains("plusEnabled: const bool.fromEnvironment('PLUS_ENABLED') && !kReleaseMode,"),
    );
    final reads = <String>[
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart'))
          for (final _ in "fromEnvironment('PLUS_ENABLED'".allMatches(f.readAsStringSync()))
            f.path,
    ];
    expect(reads, hasLength(1));
    expect(reads.single, endsWith('app_config.dart'));
    // The one place that builds Plus asks the config first.
    expect(File('lib/main.dart').readAsStringSync(), contains('!config.plusEnabled'));
  });
}
