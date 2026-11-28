import 'package:flutter/foundation.dart';

import 'plus_store.dart';

/// PLUS_FAKE_STORE: a store for the Mobile Tester's large-text rows on a
/// staging debug build, where Play Billing has no product. It shows prices
/// as long as real ones, so the shots have the true text length, and it
/// never buys anything: Start and Restore only write a debug line. It owns
/// nothing either, unless PLUS_ROWS_OWNED is on too ([ownsPlus]): then it
/// reports an active yearly purchase, so the rows see Plus on. Wired only
/// when [AppConfig.plusFakeStore] is on, which needs a debug build of the
/// staging flavor.
class RowsPlusStore implements PlusStore {
  RowsPlusStore({void Function(String line)? log, this.ownsPlus = false})
    : _log = log ?? debugPrint {
    if (ownsPlus) _log('[plus-fake] Plus on, with nothing bought (PLUS_ROWS_OWNED)');
  }

  final void Function(String line) _log;

  /// PLUS_ROWS_OWNED ([AppConfig.plusRowsOwned]): the store account owns
  /// Plus, with nothing bought.
  final bool ownsPlus;

  /// The purchase [ownsPlus] reports, with nothing to finish.
  static const rowsPurchase = PlusProof(token: 'plus-rows-owned', productId: plusPlayProductId);

  /// Plus's price (decision 85: yearly only, with the free week), as
  /// long as the real one.
  static const yearly = r'US$59.99';

  @override
  PlusSource get source => PlusSource.play;

  @override
  Future<List<PlusPlan>> plans() async => const [
    PlusPlan(period: PlusPeriod.year, price: yearly, trialOffered: true),
  ];

  @override
  Future<PlusBuyOutcome> buy(PlusPlan plan) async {
    _log('[plus-fake] Start: nothing bought, nothing sent (PLUS_FAKE_STORE)');
    return const PlusCancelled();
  }

  @override
  Future<List<PlusProof>?> owned() async => ownsPlus ? const [rowsPurchase] : const [];

  @override
  Future<void> finish(PlusProof proof) async {}

  @override
  List<PlusProof> takeUnclaimed() => const [];

  // Nothing is ever reported.
  final _changes = ChangeNotifier();

  @override
  Listenable get changes => _changes;

  @override
  Future<void> manageSubscriptions() async =>
      _log('[plus-fake] Manage subscription: no store page (PLUS_FAKE_STORE)');
}
