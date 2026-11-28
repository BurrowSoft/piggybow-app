import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/pig/pig_mood.dart' show HappyPick;
import 'package:piggybow/settings_rules/settings_rules.dart';

/// The plan's titles (§3.1), standing in for the ARB lookup.
String title(HappyPick pick) => switch (pick) {
  HappyPick.save => 'Saving something each week',
  HappyPick.plan => 'Staying within my weekly plan',
  HappyPick.worth => 'Spends that feel worth it',
};

void main() {
  group('the currency lock (decision 21)', () {
    test('changeable only while no entry and no goal exist', () {
      expect(currencyChangeable(entryCount: 0, goalCount: 0), isTrue);
      expect(currencyChangeable(entryCount: 1, goalCount: 0), isFalse);
      expect(currencyChangeable(entryCount: 0, goalCount: 1), isFalse, reason: 'an onboarding goal counts');
      expect(currencyChangeable(entryCount: 3, goalCount: 2), isFalse);
      expect(
        currencyChangeable(entryCount: 0, goalCount: 0, repeatCount: 1),
        isFalse,
        reason: 'a running repeat keeps adding in it',
      );
    });

    test('negative counts are refused', () {
      expect(() => currencyChangeable(entryCount: -1, goalCount: 0), throwsArgumentError);
      expect(() => currencyChangeable(entryCount: 0, goalCount: -1), throwsArgumentError);
      expect(() => currencyChangeable(entryCount: 0, goalCount: 0, repeatCount: -1), throwsArgumentError);
    });
  });

  group('the picks check (O2 and Me)', () {
    test('nothing picked: happyPickOne', () {
      expect(validatePicks({}, planMinor: null), PicksProblem.pickOne);
      expect(validatePicks({}, planMinor: 15000), PicksProblem.pickOne);
    });

    test('"weekly plan" picked without an amount: happyPlanNeeded', () {
      expect(validatePicks({HappyPick.plan}, planMinor: null), PicksProblem.planNeeded);
      expect(validatePicks({HappyPick.save, HappyPick.plan}, planMinor: 0), PicksProblem.planNeeded);
    });

    test('valid picks pass, and a plan without the pick is fine (decision 34)', () {
      expect(validatePicks({HappyPick.save}, planMinor: null), isNull);
      expect(validatePicks({HappyPick.plan}, planMinor: 15000), isNull);
      expect(validatePicks({HappyPick.save, HappyPick.plan, HappyPick.worth}, planMinor: 1), isNull);
      expect(validatePicks({HappyPick.worth}, planMinor: 15000), isNull);
    });
  });

  group('Remove plan (decision 29)', () {
    test('with other picks: "weekly plan" is unpicked at once', () {
      final r = removePlan({HappyPick.save, HappyPick.plan});
      expect(r.picks, {HappyPick.save});
      expect(r.openPickerFirst, isFalse);
    });

    test('as the only pick: nothing changes yet, the picker opens first', () {
      final r = removePlan({HappyPick.plan});
      expect(r.picks, {HappyPick.plan});
      expect(r.openPickerFirst, isTrue);
    });

    test('without the pick: the picks stay as they are', () {
      final r = removePlan({HappyPick.worth});
      expect(r.picks, {HappyPick.worth});
      expect(r.openPickerFirst, isFalse);
    });

    test('the input set is never changed, and the result is read-only', () {
      final picks = {HappyPick.save, HappyPick.plan};
      final r = removePlan(picks);
      expect(picks, {HappyPick.save, HappyPick.plan});
      expect(() => r.picks.add(HappyPick.worth), throwsUnsupportedError);
    });
  });

  group('the "What makes your pig happy" subtitle (decision 32)', () {
    test('titles in the order save, plan, worth, joined by " · "', () {
      expect(
        happySubtitle({HappyPick.worth, HappyPick.save}, title),
        'Saving something each week · Spends that feel worth it',
      );
      expect(
        happySubtitle({HappyPick.worth, HappyPick.plan, HappyPick.save}, title),
        'Saving something each week · Staying within my weekly plan · Spends that feel worth it',
      );
    });

    test('one pick: just its title; none: empty', () {
      expect(happySubtitle({HappyPick.plan}, title), 'Staying within my weekly plan');
      expect(happySubtitle({}, title), '');
    });
  });
}
