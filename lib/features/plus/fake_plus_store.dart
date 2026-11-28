import 'plus_store.dart';

/// A store with no store behind it, for tests. Each field is a test hook.
class FakePlusStore implements PlusStore {
  FakePlusStore({
    this.source = PlusSource.play,
    this.price = '£49.99',
    this.trialOffered = true,
    this.available = true,
  });

  @override
  final PlusSource source;
  String price;
  bool trialOffered;
  bool available;

  /// What the next buy() answers (null: bought, with [nextToken]).
  PlusBuyOutcome? nextOutcome;
  String nextToken = 'fake-token-1';

  /// What restore() finds.
  List<PlusProof> owned = const [];

  /// How many buys and restores were asked for; the proofs finished.
  int buyCalls = 0;
  int restoreCalls = 0;
  final finished = <String>[];

  @override
  Future<PlusProduct?> product() async =>
      available ? PlusProduct(price: price, trialOffered: trialOffered) : null;

  @override
  Future<PlusBuyOutcome> buy() async {
    buyCalls++;
    return nextOutcome ??
        PlusBought(PlusProof(token: nextToken, productId: plusProductId));
  }

  @override
  Future<List<PlusProof>> restore() async {
    restoreCalls++;
    return owned;
  }

  @override
  Future<void> finish(PlusProof proof) async => finished.add(proof.token);

  /// What takeUnclaimed() hands over (once).
  List<PlusProof> unclaimed = [];

  @override
  List<PlusProof> takeUnclaimed() {
    final out = unclaimed;
    unclaimed = [];
    return out;
  }

  /// How many times the store's manage sheet was asked for.
  int manageCalls = 0;

  @override
  Future<void> manageSubscriptions() async => manageCalls++;
}
