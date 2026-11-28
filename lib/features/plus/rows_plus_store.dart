import 'package:flutter/foundation.dart';

import 'plus_store.dart';

/// PLUS_FAKE_STORE: a store for the Mobile Tester's large-text rows on a
/// staging debug build, where Play Billing has no product. It shows prices
/// as long as real ones, so the shots have the true text length, and it
/// never buys and never owns anything: Start and Restore only write a
/// debug line. Wired only when [AppConfig.plusFakeStore] is on, which needs
/// a debug build of the staging flavor.
class RowsPlusStore implements PlusStore {
  RowsPlusStore({void Function(String line)? log}) : _log = log ?? debugPrint;

  final void Function(String line) _log;

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
  Future<List<PlusProof>?> owned() async => const [];

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
