import '../../data/plus.dart';
import 'plus_store.dart';

/// A store with no store behind it: tests, and dev builds on the in-memory
/// backend. Each field is a test hook.
class FakePlusStore implements PlusStore {
  FakePlusStore({
    this.source = PlusSource.play,
    this.price = '£49.99',
    this.trialOffered = true,
    this.available = true,
    this.offerPrice,
    this.offerFromStore = false,
  });

  @override
  final PlusSource source;
  String price;
  bool trialOffered;
  bool available;

  /// The store's first-year price (null: no offer); given only when asked.
  String? offerPrice;

  /// Apple-like (S11): [offerPrice] and [trialOffered] are the store's final
  /// word, given whether or not the app asked for the offer.
  bool offerFromStore;

  /// Whether the last product() asked for the offer.
  bool? askedOffer;

  /// What the next buy() answers (null: bought, with [nextToken]).
  PlusBuyOutcome? nextOutcome;
  String nextToken = 'fake-token-1';

  /// What restore() finds.
  List<PlusProof> owned = const [];

  /// The account each buy and restore was tied to; the proofs finished.
  final buys = <String>[];
  final restores = <String>[];
  final finished = <String>[];

  @override
  Future<PlusProduct?> product({bool offer = false}) async {
    askedOffer = offer;
    return available
        ? PlusProduct(
            price: price,
            trialOffered: trialOffered,
            offerPrice: offer || offerFromStore ? offerPrice : null,
            offerFromStore: offerFromStore,
          )
        : null;
  }

  @override
  Future<PlusBuyOutcome> buy({required String accountId}) async {
    buys.add(accountId);
    return nextOutcome ??
        PlusBought(PlusProof(token: nextToken, productId: plusProductId));
  }

  @override
  Future<List<PlusProof>> restore({required String accountId}) async {
    restores.add(accountId);
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
