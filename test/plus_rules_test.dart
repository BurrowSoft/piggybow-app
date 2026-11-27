import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/data/plus.dart';

/// Piggybow Plus's entitlement rules (the plumbing; no Plus UI in v0.1), and
/// the shared contract case for case.
void main() {
  final now = DateTime.utc(2026, 11, 11, 12);

  group('the entitlement row (has_plus, the trial counter, the view)', () {
    Entitlement row(
      String status, {
      PlusSource source = PlusSource.play,
      Duration? end = const Duration(days: 30),
      Duration? trialEnd,
      bool trialStarted = false,
      Duration? grace,
      Duration? start,
    }) => Entitlement(
      source: source,
      status: status,
      currentPeriodStart: start == null ? null : now.add(start),
      currentPeriodEnd: end == null ? null : now.add(end),
      trialEndsAt: trialEnd == null ? null : now.add(trialEnd),
      trialStartedAt: trialStarted ? now.subtract(const Duration(days: 1)) : null,
      graceUntil: grace == null ? null : now.add(grace),
    );

    test('trialing or active inside the period, or past_due for 7 days after it (041)', () {
      expect(hasPlus(row('active'), now), isTrue);
      expect(hasPlus(row('trialing'), now), isTrue);
      for (final s in ['paused', 'canceled', 'expired']) {
        expect(hasPlus(row(s), now), isFalse, reason: s);
      }
      // From the renewal (the period's start); the end is already a year ahead.
      const web = PlusSource.stripe;
      const yearAhead = Duration(days: 358);
      expect(hasPlus(row('past_due', source: web, start: const Duration(hours: -1), end: yearAhead), now), isTrue);
      expect(
        hasPlus(row('past_due', source: web, start: const Duration(days: -6, hours: -23), end: yearAhead), now),
        isTrue,
      );
      expect(hasPlus(row('past_due', source: web, start: const Duration(days: -7), end: yearAhead), now), isFalse);
      expect(hasPlus(row('past_due', source: web, start: const Duration(days: -8), end: yearAhead), now), isFalse);
      expect(hasPlus(row('past_due', source: web, end: yearAhead), now), isFalse, reason: 'no start');
      // A store's past_due never grants: the store gave its own grace first (UX, 20 Nov).
      expect(hasPlus(row('past_due', start: const Duration(hours: -1)), now), isFalse);
      expect(hasPlus(row('past_due', source: PlusSource.apple, start: const Duration(hours: -1)), now), isFalse);
      expect(hasPlus(row('active', end: const Duration(seconds: -1)), now), isFalse);
      expect(hasPlus(row('active', end: null), now), isFalse);
      expect(hasPlus(null, now), isFalse);
    });

    test('days left: rounded up, 1 to 7, only in a running trial', () {
      expect(
        trialDaysLeft(row('trialing', trialEnd: const Duration(hours: 1)), now),
        1,
      );
      expect(
        trialDaysLeft(row('trialing', trialEnd: const Duration(days: 6, hours: 1)), now),
        7,
      );
      expect(
        trialDaysLeft(row('trialing', trialEnd: const Duration(days: 30)), now),
        7,
      );
      expect(trialDaysLeft(row('active', trialEnd: const Duration(days: 3)), now), isNull);
      expect(
        trialDaysLeft(row('trialing', trialEnd: const Duration(seconds: -1)), now),
        isNull,
      );
    });

    test('the view: Plus, past due (Stripe only), or free with or without the trial', () {
      expect(plusView(row('active'), now), isA<PlusOn>());
      // 041: in its 7 days a past_due row is Plus with the payment line.
      final inGrace = plusView(
        row('past_due', source: PlusSource.stripe, start: const Duration(days: -2)),
        now,
      );
      expect(inGrace, isA<PlusOn>());
      expect((inGrace as PlusOn).grace, isTrue);
      expect(inGrace.source, PlusSource.stripe);
      expect(
        plusView(row('past_due', source: PlusSource.stripe, start: const Duration(days: -8)), now),
        isA<PlusPastDue>(),
      );
      // A store's past_due is just "no Plus" (the store had its own grace first; UX, 20 Nov).
      expect(plusView(row('past_due'), now), isA<PlusFree>());
      expect(plusView(row('past_due', start: const Duration(days: -1)), now), isA<PlusFree>());
      expect((plusView(null, now) as PlusFree).trial, isTrue);
      expect(
        (plusView(row('expired', trialStarted: true), now) as PlusFree).trial,
        isFalse,
      );
    });

    test('grace_until: the store line while ahead, never on a Stripe row', () {
      expect(
        (plusView(row('active', grace: const Duration(days: 2)), now) as PlusOn).grace,
        isTrue,
      );
      expect(
        (plusView(row('active', grace: const Duration(seconds: -1)), now) as PlusOn)
            .grace,
        isFalse,
      );
      expect(
        (plusView(
                  row('active', source: PlusSource.stripe, grace: const Duration(days: 2)),
                  now,
                )
                as PlusOn)
            .grace,
        isFalse,
      );
    });

    test('the Insights offer: none with Plus, none on a hard week', () {
      expect(insightsOffer(const PlusOn(source: PlusSource.play), hardWeek: false), isNull);
      expect(insightsOffer(null, hardWeek: false), isNull);
      expect(insightsOffer(const PlusFree(trial: true), hardWeek: true), isNull);
      expect(
        insightsOffer(const PlusFree(trial: true), hardWeek: false),
        const PlusOffer(trial: true),
      );
      expect(
        insightsOffer(const PlusPastDue(), hardWeek: false),
        const PlusOffer(trial: false),
      );
    });

    test('a row of another shape is no row', () {
      expect(Entitlement.fromJson({'source': 'paypal', 'status': 'active'}), isNull);
      expect(Entitlement.fromJson({'source': 'play'}), isNull);
      final e = Entitlement.fromJson({
        'source': 'apple',
        'status': 'active',
        'current_period_end': '2027-01-01T00:00:00Z',
        'grace_until': '2026-11-13T00:00:00Z',
      })!;
      expect(e.source, PlusSource.apple);
      expect(e.graceUntil, DateTime.utc(2026, 11, 13));
    });
  });

  // 041: supabase/contracts/plus-entitlement.json, case for case with has_plus() and the web.
  test('the shared entitlement contract (041)', () {
    final c = jsonDecode(File('supabase/contracts/plus-entitlement.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(c['past_due_grace_seconds'], plusPastDueGrace.inSeconds);
    final cases = (c['cases'] as List).cast<Map<String, dynamic>>();
    expect(cases.length, greaterThanOrEqualTo(22));
    for (final k in cases) {
      final status = k['status'] as String?;
      DateTime? at(String key) {
        final s = k[key] as int?;
        return s == null ? null : now.add(Duration(seconds: s));
      }
      final row = status == null
          ? null
          : Entitlement(
              source: PlusSource.values.byName(k['source'] as String),
              status: status,
              currentPeriodStart: at('period_start_offset_s'),
              currentPeriodEnd: at('period_end_offset_s'),
            );
      expect(hasPlus(row, now), k['plus'], reason: k['name'] as String);
    }
  });
}
