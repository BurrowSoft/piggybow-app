import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/plus/plus_store.dart';
import 'package:piggybow/features/plus/rows_plus_store.dart';

/// PLUS_FAKE_STORE (UX, 13 Nov): the rows' store never buys, and nothing
/// that ships can switch it on.
void main() {
  test(
    "the rows' store shows a placeholder price and never buys or finds anything",
    () async {
      final lines = <String>[];
      final store = RowsPlusStore(log: lines.add);
      final product = await store.product();
      expect(product?.price, r'US$59.99');
      expect(product?.trialOffered, isTrue);
      expect(await store.buy(), isA<PlusCancelled>());
      expect(await store.restore(), isEmpty);
      expect(lines, hasLength(2));
      expect(lines.every((l) => l.startsWith('[plus-fake]')), isTrue);
    },
  );

  test('it needs a debug build of staging: kDebugMode and the flavor guard the define', () {
    final config = File('lib/core/app_config.dart').readAsStringSync();
    expect(
      config,
      contains(
        "kDebugMode &&\n          flavor == Flavor.staging &&\n          const bool.fromEnvironment('PLUS_FAKE_STORE')",
      ),
    );
    // v0.1 has no Plus UI: main wires no store at all (the plumbing only
    // compiles). Wiring one later goes through config.plusFakeStore above.
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, isNot(contains('PlusStore(')));
  });

  test('no env file and no workflow turns it on', () {
    for (final f in Directory(
      'env',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      final env = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      expect(env.containsKey('PLUS_FAKE_STORE'), isFalse, reason: f.path);
    }
    // GitHub's workflows and Codemagic's (it has a staging --debug iOS build).
    for (final f in [
      ...Directory('.github/workflows').listSync().whereType<File>(),
      File('codemagic.yaml'),
    ]) {
      expect(f.existsSync(), isTrue, reason: f.path);
      expect(
        f.readAsStringSync(),
        isNot(contains('PLUS_FAKE_STORE')),
        reason: f.path,
      );
    }
    // The release build is never a debug one.
    final release = File('.github/workflows/release-aab.yaml')
        .readAsStringSync();
    expect(release, isNot(contains('--debug')));
  });
}
