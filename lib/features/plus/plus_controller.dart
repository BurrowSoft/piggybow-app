import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../data/models.dart';
import '../../data/plus.dart';
import 'plus_store.dart';

/// A line under the Plus footer (UX, 11 Nov). None while nothing's to say;
/// a cancelled purchase says nothing either.
enum PlusNote {
  none,
  starting,
  onItsWay,
  pending,
  purchaseFailed,
  storeUnavailable,
  restoreNone,
  restored,
}

/// What every Plus surface reads (Me, the Plus screen, Insights): the row's
/// view, the store's product, and the buy and restore flows. The row is the
/// truth; the store only sells and proves.
class PlusController extends ChangeNotifier {
  PlusController({
    required this.repository,
    required this.store,
    required this.clock,
    required this.userId,
    this.waitStep = const Duration(seconds: 2),
    this.waitFor = const Duration(seconds: 20),
    this.offerPreview = false,
    this.onBought,
  });

  /// AppConfig.offerPreview (dev/staging only).
  final bool offerPreview;

  /// A purchase went through (the review prompt never follows one).
  final VoidCallback? onBought;

  /// The row as read (null: none; unread: [view] is null).
  Entitlement? _row;

  /// The Christmas special's window is open and this account may have it
  /// (no Plus row ever). The store still decides with its own price.
  bool get offerOpen =>
      _view is PlusFree &&
      offerWindowOpen(clock.nowUtc(), preview: offerPreview) &&
      offerEligible(_row);

  /// The Christmas special to show: the window, the account and the store's
  /// own first-year price; null otherwise (never a price we didn't get). On
  /// Apple, StoreKit's own answer alone (S11): the price shown is the price
  /// it charges, at the 1 January edge and for an account with a row too.
  String? get offerPrice {
    final p = _product;
    if (p != null && p.offerFromStore) return _view is PlusFree ? p.offerPrice : null;
    return offerOpen ? p?.offerPrice : null;
  }

  final PlusRepository repository;

  /// null: no store on this platform (purchases unavailable).
  final PlusStore? store;
  final Clock clock;

  /// The signed-in person (null: signed out); the store ties purchases to it.
  final String? Function() userId;

  /// After plus-store, the row may land a moment later (the store's own
  /// notification): look again every [waitStep] for [waitFor], then the calm
  /// "on its way" line (the web's rule).
  final Duration waitStep;
  final Duration waitFor;

  /// null: not read yet, or the row can't be read (then nothing about Plus
  /// shows at all, never an offer to someone who may already pay).
  PlusView? get view => _view;
  PlusView? _view;
  bool _loaded = false;
  bool get loaded => _loaded;

  /// null: purchases unavailable here (or not asked yet).
  PlusProduct? get product => _product;
  PlusProduct? _product;

  bool get busy => _busy;
  bool _busy = false;

  PlusNote get note => _note;
  PlusNote _note = PlusNote.none;

  bool _disposed = false;

  /// The free week on offer: the store's word once it has answered, else the
  /// web's rule from the row (no trial started yet).
  bool get trialOffered {
    final v = _view;
    if (v is! PlusFree) return false;
    final p = _product;
    // Apple: StoreKit's word (S11); it has one introductory offer at a time.
    if (p != null && p.offerFromStore) return p.trialOffered;
    // The special replaces the free week while it runs (spec §1).
    if (offerOpen) return false;
    return p?.trialOffered ?? v.trial;
  }

  /// The locked items' offer (the web's insightsOffer, with no hard week in
  /// the app: it has no non-AI Your week card): none with Plus or when the
  /// row can't be read; a past-due row sees them locked, with no trial.
  PlusOffer? get offer => switch (_view) {
    null || PlusOn() => null,
    _ => PlusOffer(trial: trialOffered),
  };

  Future<void> load() async {
    try {
      // A purchase the store reported with nobody waiting is verified (and
      // finished) first, so the row read next already has it.
      await _claimUnclaimed();
      final row = await repository.myEntitlement();
      _row = row;
      _view = plusView(row, clock.nowUtc());
    } on AppFailure {
      _view = null;
    }
    _loaded = true;
    if (_view is PlusFree && store != null) {
      try {
        _product = await store!.product(offer: offerOpen);
      } on Object {
        _product = null;
      }
    }
    _notify();
  }

  Future<void> buy() async {
    final s = store, uid = userId();
    if (_busy || uid == null) return;
    if (s == null || _product == null) {
      _set(PlusNote.storeUnavailable);
      return;
    }
    _busy = true;
    _set(PlusNote.none);
    final PlusBuyOutcome outcome;
    try {
      outcome = await s.buy(accountId: uid);
    } on Object {
      _busy = false;
      _set(PlusNote.purchaseFailed);
      return;
    }
    switch (outcome) {
      case PlusCancelled():
        _busy = false;
        _set(PlusNote.none);
      case PlusPending():
        _busy = false;
        _set(PlusNote.pending);
      case PlusBuyFailed():
        _busy = false;
        _set(PlusNote.purchaseFailed);
      case PlusBought(:final proof):
        onBought?.call();
        _set(PlusNote.starting);
        await _verify(s, proof);
        await _waitForPlus();
        _busy = false;
        _notify();
    }
  }

  Future<void> restore() async {
    final s = store, uid = userId();
    if (_busy || uid == null) return;
    if (s == null) {
      _set(PlusNote.storeUnavailable);
      return;
    }
    _busy = true;
    _set(PlusNote.none);
    List<PlusProof> found;
    try {
      found = await s.restore(accountId: uid);
    } on Object {
      found = const [];
    }
    for (final proof in found) {
      await _verify(s, proof);
    }
    await load();
    _busy = false;
    _set(_view is PlusOn ? PlusNote.restored : PlusNote.restoreNone);
  }

  /// The store's manage-subscriptions sheet (Apple's; UX, 23 Nov). Nothing is
  /// bought or changed here: the next load reads whatever the person did in
  /// the sheet (plus-store hears the cancel from Apple's notification).
  Future<void> manageSubscriptions() async {
    final s = store;
    if (s == null) return;
    try {
      await s.manageSubscriptions();
    } on Object {
      return;
    }
    await load();
  }

  Future<void> _claimUnclaimed() async {
    final s = store;
    if (s == null || userId() == null) return;
    final List<PlusProof> proofs;
    try {
      proofs = s.takeUnclaimed();
    } on Object {
      return;
    }
    for (final proof in proofs) {
      await _verify(s, proof);
    }
  }

  /// plus-store writes the row; only then is the purchase finished in the
  /// store. A failed /verify leaves it unfinished, so the store hands it
  /// back on the next start or Restore: never lost, never charged twice.
  Future<void> _verify(PlusStore s, PlusProof proof) async {
    try {
      await repository.verifyPurchase(
        store: s.source,
        token: proof.token,
        productId: proof.productId,
      );
      await s.finish(proof);
    } on Object {
      // The row may still come from the store's notification.
    }
  }

  Future<void> _waitForPlus() async {
    // Counted in steps, not by the clock (a fixed test clock never moves).
    var left = waitFor.inMilliseconds ~/ waitStep.inMilliseconds;
    await load();
    while (_view is! PlusOn && !_disposed) {
      if (left-- <= 0) {
        _set(PlusNote.onItsWay);
        return;
      }
      await Future<void>.delayed(waitStep);
      await load();
    }
    _set(PlusNote.none);
  }

  void _set(PlusNote n) {
    _note = n;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
