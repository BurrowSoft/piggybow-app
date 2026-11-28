import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/features/plus/plus_entitlement.dart';
import 'package:piggybow/features/plus/plus_store.dart';
import 'package:piggybow/features/plus/rows_plus_store.dart';

/// PLUS_FAKE_STORE (UX, 13 Nov): the rows' store never buys, and nothing
/// that ships can switch it on. PLUS_ROWS_OWNED (UX, 28 Nov): on top of it,
/// the rows see Plus on with nothing bought, under the same guard.
void main() {
  test(
    "the rows' store shows Plus's yearly plan alone and never buys or owns anything",
    () async {
      final lines = <String>[];
      final store = RowsPlusStore(log: lines.add);
      final plans = await store.plans();
      // Yearly only, with the free week (decision 85).
      expect([for (final p in plans) (p.period, p.price, p.trialOffered)], [
        (PlusPeriod.year, r'US$59.99', true),
      ]);
      expect(await store.buy(plans.single), isA<PlusCancelled>());
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
        '!config.plusEnabled ? null : config.plusFakeStore '
        '? RowsPlusStore(ownsPlus: config.plusRowsOwned) : platformPlusStore()',
      ),
    );
    expect('RowsPlusStore('.allMatches(main), hasLength(1));
  });

  test('no env file and no workflow turns it on, or PLUS_ROWS_OWNED', () {
    const defines = ['PLUS_FAKE_STORE', 'PLUS_ROWS_OWNED'];
    for (final f in Directory(
      'env',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      final env = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      for (final define in defines) {
        expect(env.containsKey(define), isFalse, reason: '${f.path}: $define');
      }
    }
    // GitHub's workflows and Codemagic's (it has a staging --debug iOS build).
    for (final f in [
      ...Directory('.github/workflows').listSync().whereType<File>(),
      File('codemagic.yaml'),
    ]) {
      expect(f.existsSync(), isTrue, reason: f.path);
      final text = f.readAsStringSync();
      for (final define in defines) {
        expect(text, isNot(contains(define)), reason: '${f.path}: $define');
      }
    }
    // The release build is never a debug one.
    final release = File('.github/workflows/release-aab.yaml')
        .readAsStringSync();
    expect(release, isNot(contains('--debug')));
  });

  test("with PLUS_ROWS_OWNED the rows' store owns Plus's yearly plan, and still never buys", () async {
    final lines = <String>[];
    final store = RowsPlusStore(log: lines.add, ownsPlus: true);
    final owned = (await store.owned())!;
    expect([for (final p in owned) (p.productId, p.needsFinish)], [(plusPlayProductId, false)]);
    expect(isPlusProduct(owned.single.productId), isTrue);
    expect(owned.single.token, isNotEmpty);
    expect(await store.buy((await store.plans()).single), isA<PlusCancelled>());
    expect(store.takeUnclaimed(), isEmpty);
    expect(lines, hasLength(2));
    expect(lines.every((l) => l.startsWith('[plus-fake]')), isTrue);
    expect(lines.first, contains('PLUS_ROWS_OWNED'));
  });

  test('with it, Plus is on at launch and on every resume', () async {
    final plus = PlusEntitlement(
      store: RowsPlusStore(log: (_) {}, ownsPlus: true),
      hint: MemoryPlusHint(),
      clock: Clock(fixed: DateTime.utc(2026, 11, 28, 5)),
    );
    await plus.start();
    expect(plus.active, isTrue);
    await plus.refresh();
    expect(plus.active, isTrue);
  });

  test("PLUS_ROWS_OWNED needs the rows' store: kDebugMode, the flavor and PLUS_FAKE_STORE guard it", () {
    final config = File('lib/core/app_config.dart').readAsStringSync();
    expect(
      config,
      contains(
        "kDebugMode &&\n          flavor == Flavor.staging &&\n          const bool.fromEnvironment('PLUS_FAKE_STORE') &&\n          const bool.fromEnvironment('PLUS_ROWS_OWNED')",
      ),
    );
    expect("bool.fromEnvironment('PLUS_ROWS_OWNED')".allMatches(config), hasLength(1));
    // Without its defines (every test run, every build but the rows'), off.
    expect(AppConfig.fromEnvironment().plusRowsOwned, isFalse);
  });
}
