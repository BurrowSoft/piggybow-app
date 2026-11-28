// Piggybow Plus's store layer (decision 79): Plus is bought and read on the
// phone, through Google Play Billing or StoreKit 2. There is no server and
// no account (decision 3), so nothing checks a purchase elsewhere and
// nothing ties it to a person: the store account (the Google account, the
// Apple ID) owns it.

import 'package:flutter/foundation.dart' show Listenable;

/// Which store this phone buys Plus from.
enum PlusSource { play, apple }

/// Play: one subscription with two base plans; the free week is an offer
/// on a plan.
const plusPlayProductId = 'piggybow_plus';
const plusPlayMonthlyPlan = 'monthly';
const plusPlayYearlyPlan = 'yearly';

/// Apple: two products in one subscription group; the free week is a
/// product's introductory offer.
const plusAppleMonthlyId = 'piggybow_plus_monthly';
const plusAppleYearlyId = 'piggybow_plus_yearly';

/// Whether a store's product id is Plus's.
bool isPlusProduct(String productId) =>
    productId == plusPlayProductId ||
    productId == plusAppleMonthlyId ||
    productId == plusAppleYearlyId;

/// How often a plan renews.
enum PlusPeriod { month, year }

/// One plan as the store offers it to this account.
class PlusPlan {
  const PlusPlan({
    required this.period,
    required this.price,
    required this.trialOffered,
    this.handle,
  });

  final PlusPeriod period;

  /// The store's own formatted price for one period ("£2.99"): the app
  /// never shows a price of its own, so the price shown is the price
  /// charged.
  final String price;

  /// The store offers this account a free week on this plan. The store
  /// decides, not us.
  final bool trialOffered;

  /// The store layer's own object, to buy this plan with.
  final Object? handle;
}

/// A purchase the store reports: bought, approved later, or owned now.
class PlusProof {
  const PlusProof({
    required this.token,
    required this.productId,
    this.handle,
    this.needsFinish = false,
  });

  /// Play's purchase token or Apple's transaction id: one purchase, however
  /// many times the store reports it.
  final String token;
  final String productId;

  /// The store layer's own object, to finish the purchase with.
  final Object? handle;

  /// The store still waits for the app to finish it ([PlusStore.finish]).
  final bool needsFinish;
}

sealed class PlusBuyOutcome {
  const PlusBuyOutcome();
}

/// Bought: the app finishes it in the store at once ([PlusStore.finish]).
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

  /// The plans as this account sees them, monthly first; empty when
  /// purchases aren't available here (no store, no products yet).
  Future<List<PlusPlan>> plans();

  /// The store's purchase sheet for [plan].
  Future<PlusBuyOutcome> buy(PlusPlan plan);

  /// What the store account owns now: its active Plus purchases, from the
  /// store on the phone (which answers offline from its own records). Never
  /// a new purchase, never a charge, never a sign-in sheet. null: the store
  /// couldn't say (none on this phone, or it didn't answer).
  Future<List<PlusProof>?> owned();

  /// Finishes a purchase in the store: Play's acknowledgement (Play refunds
  /// a purchase left unacknowledged for 3 days), StoreKit's finish. Only
  /// one that [PlusProof.needsFinish].
  Future<void> finish(PlusProof proof);

  /// Purchases the store reported with nobody waiting (approved after a
  /// pending payment, renewed, or left unfinished last time), handed over
  /// once.
  List<PlusProof> takeUnclaimed();

  /// Notifies when the store reports such a purchase.
  Listenable get changes;

  /// The store's own subscription page: StoreKit 2's sheet on the iPhone,
  /// Play's subscriptions page on Android. Never a purchase or a charge.
  Future<void> manageSubscriptions();
}
