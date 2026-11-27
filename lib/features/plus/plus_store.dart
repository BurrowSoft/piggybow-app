import '../../data/plus.dart';

/// The one Plus product, the same id in both stores (docs/plus-app-purchases.md).
const plusProductId = 'piggybow_plus_yearly';

/// The Christmas special's Play offer id on that product (the owner's store
/// setup; a PLACEHOLDER until he creates it). Apple uses the product's
/// introductory offer instead.
const plusOfferId = 'christmas-first-year';

/// What the store says about the product on this phone.
class PlusProduct {
  const PlusProduct({
    required this.price,
    required this.trialOffered,
    this.offerPrice,
    this.offerFromStore = false,
  });

  /// The store's own formatted yearly price ("£49.99"): the app never shows
  /// a price of its own, so the price shown is the price charged.
  final String price;

  /// The store offers this account the free week (Play's offer
  /// free-trial-7d, Apple's introductory offer). The store decides, not us.
  final bool trialOffered;

  /// The Christmas special: the store's own first-year price for this
  /// account (Play's offer phase, Apple's introductory price); null when
  /// the store doesn't offer it. Never computed here.
  final String? offerPrice;

  /// [offerPrice] and [trialOffered] are the store's final word for this
  /// buyer (Apple, iOS plan S11): StoreKit applies its introductory offer to
  /// every eligible Apple ID on its own dates, so the app shows what StoreKit
  /// reports, not the app's December window or the account's row. Play's
  /// offer is bought only when the app picks it, so Play keeps those rules.
  final bool offerFromStore;
}

/// A purchase the store reports (bought or restored), for plus-store.
class PlusProof {
  const PlusProof({required this.token, required this.productId, this.handle});

  /// Play's purchase token or Apple's transaction id.
  final String token;
  final String productId;

  /// The store layer's own object, to finish the purchase after /verify.
  final Object? handle;
}

sealed class PlusBuyOutcome {
  const PlusBuyOutcome();
}

/// Bought: the proof goes to plus-store, then the purchase is finished.
class PlusBought extends PlusBuyOutcome {
  const PlusBought(this.proof);
  final PlusProof proof;
}

/// The person closed the store's sheet: nothing shows (UX, 11 Nov).
class PlusCancelled extends PlusBuyOutcome {
  const PlusCancelled();
}

/// Play's pending payment, Apple's Ask to Buy: Plus starts once approved
/// (the store's notification reaches plus-store).
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
  /// available here (no store, no product yet, offline).
  ///
  /// [offer]: look for the Christmas special too (only while its window is
  /// open and the account is eligible); then Start buys it.
  Future<PlusProduct?> product({bool offer = false});

  /// The store's purchase sheet for [plusProductId], tied to the person
  /// ([accountId]: Play's obfuscatedAccountId, a hash of the user id; Apple's
  /// appAccountToken, the user id) so plus-store can match it.
  Future<PlusBuyOutcome> buy({required String accountId});

  /// The account's current Plus purchases (never a new purchase, never a
  /// charge). Empty: none found.
  Future<List<PlusProof>> restore({required String accountId});

  /// After plus-store wrote the row: finish the purchase in the store
  /// (StoreKit's finishTransaction; Play's acknowledgement is the server's).
  Future<void> finish(PlusProof proof);

  /// Purchases the store reported with nobody waiting (finished on another
  /// screen, or left unfinished last time), handed over once: the
  /// controller verifies and finishes them when it loads (the Reviewer's
  /// payments audit). Also starts listening, so later ones wait for the
  /// next load.
  List<PlusProof> takeUnclaimed();

  /// The store's own manage-subscriptions page (Apple: StoreKit 2's
  /// showManageSubscriptions sheet; UX, 23 Nov). Never a purchase or a
  /// charge; a no-op where the store has no such sheet.
  Future<void> manageSubscriptions();
}
