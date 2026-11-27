import 'package:flutter/foundation.dart';

import '../../data/plus.dart';
import 'plus_store.dart';

/// PLUS_FAKE_STORE (UX, 13 Nov): a store for the Mobile Tester's large-text
/// rows on a staging debug build, where Play Billing has no product. It shows
/// the spec's price, so the footer's shots have the true text length, and it
/// never buys: Start and Restore only write a debug line, so nothing reaches
/// plus-store. Wired only when [AppConfig.plusFakeStore] is on, which needs a
/// debug build of the staging flavor.
class RowsPlusStore implements PlusStore {
  RowsPlusStore({void Function(String line)? log}) : _log = log ?? debugPrint;

  final void Function(String line) _log;

  /// The spec's yearly price (specs/plus.md).
  static const price = r'US$59.99';

  /// The spec's first-year price (a placeholder for the rows, OFFER_PREVIEW).
  static const offerPrice = r'US$29.99';

  @override
  PlusSource get source => PlusSource.play;

  @override
  Future<PlusProduct?> product({bool offer = false}) async => PlusProduct(
    price: price,
    trialOffered: !offer,
    offerPrice: offer ? offerPrice : null,
  );

  @override
  Future<PlusBuyOutcome> buy({required String accountId}) async {
    _log('[plus-fake] Start: nothing bought, nothing sent (PLUS_FAKE_STORE)');
    return const PlusCancelled();
  }

  @override
  Future<List<PlusProof>> restore({required String accountId}) async {
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
