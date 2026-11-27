// Piggybow Plus (decision 246, specs/plus.md): the person's entitlements row
// (migration 028) and what the app shows from it. The same rules as the web's
// src/lib/plus/entitlements.ts and view.ts, rule for rule. Pure, apart from
// the repository at the end.

/// Who sold Plus. The app only ever buys through Play or Apple; a Stripe row
/// is Plus bought on the web, shown the same way.
enum PlusSource {
  stripe,
  play,
  apple;

  static PlusSource? parse(Object? v) {
    for (final s in values) {
      if (s.name == v) return s;
    }
    return null;
  }
}

/// The free week's length, everywhere.
const plusTrialDays = 7;

/// The row as the person reads it (RLS: own row only; no client writes).
class Entitlement {
  const Entitlement({
    required this.source,
    required this.status,
    this.trialEndsAt,
    this.currentPeriodEnd,
    this.trialStartedAt,
    this.graceUntil,
    this.currentPeriodStart,
  });

  final PlusSource source;

  /// trialing, active, past_due, paused, canceled or expired.
  final String status;
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodEnd;

  /// Set once, never cleared: the web's one free week per person.
  final DateTime? trialStartedAt;

  /// A store's grace end (028, UX 11 Nov): the payment line shows while it's
  /// ahead. Only plus-store writes it; never on a Stripe row.
  final DateTime? graceUntil;

  /// 041: the current period's start (Stripe rows, from the web's sync). A
  /// failed renewal keeps Plus for 7 days from it.
  final DateTime? currentPeriodStart;

  /// The columns the app reads (no store ids: the app has no use for them).
  /// current_period_start needs 041 on the server first.
  static const columns =
      'source, status, trial_ends_at, current_period_end, trial_started_at, '
      'grace_until, current_period_start';

  /// null for anything that isn't a row of 028's shape.
  static Entitlement? fromJson(Object? json) {
    if (json is! Map) return null;
    final source = PlusSource.parse(json['source']);
    final status = json['status'];
    if (source == null || status is! String) return null;
    DateTime? at(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return Entitlement(
      source: source,
      status: status,
      trialEndsAt: at(json['trial_ends_at']),
      currentPeriodEnd: at(json['current_period_end']),
      trialStartedAt: at(json['trial_started_at']),
      graceUntil: at(json['grace_until']),
      currentPeriodStart: at(json['current_period_start']),
    );
  }
}

/// 041: how long a failed renewal (past_due) keeps Plus after its period end.
const plusPastDueGrace = Duration(days: 7);

/// The one rule, as has_plus() in SQL (041; cases in
/// supabase/contracts/plus-entitlement.json): trialing or active inside the
/// period, or a web (Stripe) past_due row until 7 × 24 h after its period's
/// START (the renewal: Stripe opens the new period before it tries the card,
/// so the end is already ahead). End excluded; a null start never grants. A
/// store's past_due never grants (the store gave its own grace first).
/// paused, canceled and expired never grant.
bool hasPlus(Entitlement? row, DateTime now) {
  if (row == null) return false;
  final end = row.currentPeriodEnd;
  final start = row.currentPeriodStart;
  return switch (row.status) {
    'trialing' || 'active' => end != null && end.isAfter(now),
    'past_due' =>
      row.source == PlusSource.stripe &&
          start != null &&
          start.add(plusPastDueGrace).isAfter(now),
    _ => false,
  };
}

/// Me's trial counter ("Plus trial · {n} days left"): whole days left,
/// rounded up, 1 to 7; null outside a running trial.
int? trialDaysLeft(Entitlement? row, DateTime now) {
  if (row == null || row.status != 'trialing' || !hasPlus(row, now)) {
    return null;
  }
  final ends = row.trialEndsAt;
  if (ends == null) return null;
  final ms = ends.difference(now).inMilliseconds;
  if (ms <= 0) return null;
  final days = (ms / Duration.millisecondsPerDay).ceil();
  return days > plusTrialDays ? plusTrialDays : days;
}

/// What a screen shows about Plus.
sealed class PlusView {
  const PlusView();
}

/// No Plus. [trial]: the screen offers the free week. In the app the store
/// decides (PlusStore.trialOffered); until it has answered, the web's rule
/// (no trial started yet) stands in.
class PlusFree extends PlusView {
  const PlusFree({required this.trial});
  final bool trial;
}

/// Plus, from whichever store; [daysLeft] only while the free week runs.
/// [grace]: a renewal is failing but Plus still runs: a store's own grace
/// (Play's grace period, Apple's billing grace period; UX 11 Nov), or a web
/// (Stripe) past_due row inside its 7 days (041). Me shows the payment line
/// for [source]: the store's, or for stripe the web's card line.
class PlusOn extends PlusView {
  const PlusOn({required this.source, this.daysLeft, this.grace = false, this.until});
  final PlusSource source;
  final int? daysLeft;
  final bool grace;

  /// When the paid year (or the trial) runs out: Plus's extra theme runs to it.
  final DateTime? until;
}

/// A Stripe renewal failed and its 7 days (041) are over: Plus is paused
/// until the card is fixed on the web (a state, not a reminder). The app has no card form: it says so and
/// points to the web's page.
class PlusPastDue extends PlusView {
  const PlusPastDue();
}

PlusView plusView(Entitlement? row, DateTime now) {
  if (row != null && hasPlus(row, now)) {
    final grace = row.status == 'past_due' ||
        (row.source != PlusSource.stripe &&
            (row.graceUntil?.isAfter(now) ?? false));
    return PlusOn(
      source: row.source,
      daysLeft: trialDaysLeft(row, now),
      grace: grace,
      until: row.currentPeriodEnd,
    );
  }
  if (row?.source == PlusSource.stripe && row?.status == 'past_due') {
    return const PlusPastDue();
  }
  return PlusFree(trial: row?.trialStartedAt == null);
}

/// Insights' locked items (Year and All time, More patterns, the Your week
/// line): only for someone without Plus, and none at all on a hard week,
/// beside the help offer (UX, #271). null: show nothing about Plus.
PlusOffer? insightsOffer(PlusView? view, {required bool hardWeek}) {
  if (view == null || view is PlusOn || hardWeek) return null;
  return PlusOffer(trial: view is PlusFree && view.trial);
}

/// The sheet's and the banner's offer: the free week or not. The price is
/// the store's own formatted price (never one of ours), so it isn't here.
/// 1.3 Christmas special offer (spec §1, "Christmas look and copy"; the
/// web's offer.ts, #315): from 1 December to 1 January 00:00 UTC (the stores'
/// own moment), or with [preview] (OFFER_PREVIEW, dev/staging only).
bool offerWindowOpen(DateTime nowUtc, {bool preview = false}) =>
    preview || nowUtc.toUtc().month == DateTime.december;

/// Who it's for (UX, 14 Nov): never had Plus, a free week or a purchase on any
/// store, i.e. no entitlement row at all. The store also offers it only to
/// new subscribers.
bool offerEligible(Entitlement? row) => row == null;

class PlusOffer {
  const PlusOffer({required this.trial});
  final bool trial;

  @override
  bool operator ==(Object other) => other is PlusOffer && other.trial == trial;

  @override
  int get hashCode => trial.hashCode;
}

/// Plus's reads and the store check (decision 246). The row is read as the
/// person (RLS); purchases go to plus-store, which asks the store and writes
/// the row with the service role. Only built while `plus` is on.
/// The web's cancel-for-delete answer (web #331), as the app uses it:
/// [cancelled] now (200 "cancelled"); [none] running on the web (200
/// "none"); [later]: anything else (202, 503, 404, a timeout, offline, no
/// origin in this build): delete_my_account queues it and the cron ends it.
enum CancelForDelete { cancelled, none, later }

abstract interface class PlusRepository {
  /// Before deleting an account whose Plus came from the web (Stripe):
  /// cancel it now on the web ([webOrigin]/api/plus/cancel-for-delete, the
  /// person's own token, ~10 s). Never throws: the delete always goes on.
  Future<CancelForDelete> cancelForDelete(String webOrigin);

  /// The person's row, or null for none. Throws AppFailure when it can't be
  /// read: the screen then shows nothing about Plus (never an offer to
  /// someone who may already pay).
  Future<Entitlement?> myEntitlement();

  /// After a purchase or a restore: the store's proof (Play's purchase token,
  /// Apple's transaction id) to plus-store /verify. It returns once the row
  /// is written (or the store said no: AppFailure 'plus_not_verified').
  Future<void> verifyPurchase({
    required PlusSource store,
    required String token,
    required String productId,
  });
}
