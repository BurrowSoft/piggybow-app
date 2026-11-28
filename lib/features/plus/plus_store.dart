// Piggybow Plus's store layer (decision 79): Plus is bought and read on the
// phone, through Google Play Billing or StoreKit 2. There is no server and
// no account (decision 3), so nothing checks a purchase elsewhere and
// nothing ties it to a person: the store account (the Google account, the
// Apple ID) owns it.

/// Which store this phone buys Plus from.
enum PlusSource { play, apple }

/// The one Plus product, the same id in both stores.
const plusProductId = 'piggybow_plus_yearly';

/// What the store says about the product on this phone.
class PlusProduct {
  const PlusProduct({required this.price, required this.trialOffered});

  /// The store's own formatted price ("£49.99"): the app never shows a
  /// price of its own, so the price shown is the price charged.
  final String price;

  /// The store offers this account the free week (a Play offer, Apple's
  /// introductory offer). The store decides, not us.
  final bool trialOffered;
}

/// A purchase the store reports (bought or restored).
class PlusProof {
  const PlusProof({required this.token, required this.productId, this.handle});

  /// Play's purchase token or Apple's transaction id: one purchase, however
  /// many times the store reports it.
  final String token;
  final String productId;

  /// The store layer's own object, to finish the purchase with.
  final Object? handle;
}

sealed class PlusBuyOutcome {
  const PlusBuyOutcome();
}

/// Bought: the app finishes it in the store (see [PlusStore.finish]).
class PlusBought extends PlusBuyOutcome {
  const PlusBought(this.proof);
  final PlusProof proof;
}

/// The person closed the store's sheet: nothing shows.
class PlusCancelled extends PlusBuyOutcome {
  const PlusCancelled();
}

/// Play's pending payment, Apple's Ask to Buy: Plus starts once the store
/// approves it and reports the purchase again.
class PlusPending extends PlusBuyOutcome {
  const PlusPending();
}

/// The store said no, or never answered.
class PlusBuyFailed extends PlusBuyOutcome {
  const PlusBuyFailed();
}

/// Google Play Billing or StoreKit, behind one interface (a fake in tests;
/// the in_app_purchase layer in the app).
abstract interface class PlusStore {
  /// play or apple: which store this phone buys from.
  PlusSource get source;

  /// The product as this account sees it; null when purchases aren't
  /// available here (no store, no product yet).
  Future<PlusProduct?> product();

  /// The store's purchase sheet for [plusProductId].
  Future<PlusBuyOutcome> buy();

  /// The store account's current Plus purchases (never a new purchase,
  /// never a charge). Empty: none found.
  Future<List<PlusProof>> restore();

  /// Finishes a purchase in the store: Play's acknowledgement (Play refunds
  /// a purchase left unacknowledged for 3 days), StoreKit's finish.
  Future<void> finish(PlusProof proof);

  /// Purchases the store reported with nobody waiting (approved after a
  /// pending payment, or left unfinished last time), handed over once.
  /// Also starts listening, so later ones wait for the next call.
  List<PlusProof> takeUnclaimed();

  /// The store's own manage-subscriptions page (StoreKit 2's sheet on the
  /// iPhone). Never a purchase or a charge; a no-op where the store has no
  /// such sheet.
  Future<void> manageSubscriptions();
}
