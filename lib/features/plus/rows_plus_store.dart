import 'package:flutter/foundation.dart';

import 'plus_store.dart';

/// PLUS_FAKE_STORE: a store for the Mobile Tester's large-text rows on a
/// staging debug build, where Play Billing has no product. It shows a
/// price as long as a real one, so the shots have the true text length,
/// and it never buys: Start and Restore only write a debug line. Wired
/// only when [AppConfig.plusFakeStore] is on, which needs a debug build of
/// the staging flavor.
class RowsPlusStore implements PlusStore {
  RowsPlusStore({void Function(String line)? log}) : _log = log ?? debugPrint;

  final void Function(String line) _log;

  /// A placeholder yearly price, until Plus's price is set.
  static const price = r'US$59.99';

  @override
  PlusSource get source => PlusSource.play;

  @override
  Future<PlusProduct?> product() async =>
      const PlusProduct(price: price, trialOffered: true);

  @override
  Future<PlusBuyOutcome> buy() async {
    _log('[plus-fake] Start: nothing bought, nothing sent (PLUS_FAKE_STORE)');
    return const PlusCancelled();
  }

  @override
  Future<List<PlusProof>> restore() async {
    _log('[plus-fake] Restore: nothing found, nothing sent (PLUS_FAKE_STORE)');
    return const [];
  }

  @override
  Future<void> finish(PlusProof proof) async {}

  @override
  List<PlusProof> takeUnclaimed() => const [];

  @override
  Future<void> manageSubscriptions() async =>
      _log('[plus-fake] Manage subscription: no store sheet (PLUS_FAKE_STORE)');
}
