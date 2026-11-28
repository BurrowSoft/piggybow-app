import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/plus/plus_store.dart';
import 'package:piggybow/features/plus/rows_plus_store.dart';

/// PLUS_FAKE_STORE (UX, 13 Nov): the rows' store never buys, and nothing
/// that ships can switch it on.
void main() {
  test(
    "the rows' store shows placeholder prices and never buys or owns anything",
    () async {
      final lines = <String>[];
      final store = RowsPlusStore(log: lines.add);
      final plans = await store.plans();
      expect([for (final p in plans) (p.period, p.price, p.trialOffered)], [
        (PlusPeriod.month, r'US$2.99', false),
        (PlusPeriod.year, r'US$19.99', true),
      ]);
      expect(await store.buy(plans.last), isA<PlusCancelled>());
      expect(await store.owned(), isEmpty);
      expect(store.takeUnclaimed(), isEmpty);
      expect(lines, hasLength(1));
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
    // main builds a store only with PLUS_ENABLED (never in a release build),
    // and the rows' store only through config.plusFakeStore above.
    final main = File(
      'lib/main.dart',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
    expect(
      main,
      contains(
        '!config.plusEnabled ? null : config.plusFakeStore ? RowsPlusStore() : platformPlusStore()',
      ),
    );
    expect('RowsPlusStore('.allMatches(main), hasLength(1));
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
