import 'package:flutter/foundation.dart';

import 'plus_store.dart';

/// A store with no store behind it, for tests. Each field is a test hook.
class FakePlusStore implements PlusStore {
  FakePlusStore({
    this.source = PlusSource.play,
    this.yearly = '£19.99',
    this.trialOffered = true,
    this.available = true,
  });

  @override
  final PlusSource source;

  /// The yearly plan's price (Plus is yearly only, decision 85), as the
  /// store formats it.
  String yearly;

  /// The free week on the yearly plan.
  bool trialOffered;

  /// Purchases are available here (else no plans, and owned() can't say).
  bool available;

  /// What owned() finds (null: the store can't say).
  List<PlusProof>? owns = const [];

  /// What the next buy() answers (null: bought, with [nextToken]).
  PlusBuyOutcome? nextOutcome;
  String nextToken = 'fake-token-1';

  /// The plans bought, owned() calls, and the proofs finished.
  final bought = <PlusPeriod>[];
  int ownedCalls = 0;
  final finished = <String>[];

  @override
  Future<List<PlusPlan>> plans() async => available
      ? [PlusPlan(period: PlusPeriod.year, price: yearly, trialOffered: trialOffered, handle: 'year')]
      : const [];

  @override
  Future<PlusBuyOutcome> buy(PlusPlan plan) async {
    bought.add(plan.period);
    return nextOutcome ??
        PlusBought(PlusProof(token: nextToken, productId: plusPlayProductId, needsFinish: true));
  }

  @override
  Future<List<PlusProof>?> owned() async {
    ownedCalls++;
    return available ? owns : null;
  }

  @override
  Future<void> finish(PlusProof proof) async {
    if (proof.needsFinish) finished.add(proof.token);
  }

  /// What takeUnclaimed() hands over (once).
  List<PlusProof> unclaimed = [];

  @override
  List<PlusProof> takeUnclaimed() {
    final out = unclaimed;
    unclaimed = [];
    return out;
  }

  final _changes = _Changes();

  @override
  Listenable get changes => _changes;

  /// The store reports [proof] with nobody waiting.
  void report(PlusProof proof) {
    unclaimed = [...unclaimed, proof];
    _changes.ping();
  }

  /// How many times the store's subscription page was asked for.
  int manageCalls = 0;

  @override
  Future<void> manageSubscriptions() async => manageCalls++;
}

class _Changes extends ChangeNotifier {
  void ping() => notifyListeners();
}
