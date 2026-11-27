// The settings' rules (plan §3.1, §3.8, decisions 21, 29, 32): when the currency can change, the
// "What makes your pig happy" checks, removing the weekly plan, and the picks' subtitle in Me.

import '../pig/pig_mood.dart' show HappyPick;

/// The currency can change only while nothing is stored in it: no entry and no goal (decision 21).
/// Deleting everything therefore unlocks it again.
bool currencyChangeable({required int entryCount, required int goalCount}) {
  if (entryCount < 0 || goalCount < 0) throw ArgumentError('counts must not be negative');
  return entryCount == 0 && goalCount == 0;
}

/// Why a set of picks can't be saved: none picked (happyPickOne), or "weekly plan" picked without
/// a plan amount (happyPlanNeeded).
enum PicksProblem { pickOne, planNeeded }

/// The check behind Continue (onboarding) and Done (Me): null when the picks can be saved.
PicksProblem? validatePicks(Set<HappyPick> picks, {required int? planMinor}) {
  if (picks.isEmpty) return PicksProblem.pickOne;
  if (picks.contains(HappyPick.plan) && (planMinor == null || planMinor <= 0)) return PicksProblem.planNeeded;
  return null;
}

/// Me → Weekly spending plan → Remove plan (decision 29). Removing the plan also unpicks "weekly
/// plan". When that's the only pick, nothing changes yet: the picker opens first
/// ([openPickerFirst]), and the plan goes once another pick is made.
({Set<HappyPick> picks, bool openPickerFirst}) removePlan(Set<HappyPick> picks) {
  if (picks.length == 1 && picks.contains(HappyPick.plan)) {
    return (picks: Set<HappyPick>.unmodifiable(picks), openPickerFirst: true);
  }
  return (picks: Set<HappyPick>.unmodifiable(picks.difference({HappyPick.plan})), openPickerFirst: false);
}

/// The subtitle of Me's "What makes your pig happy" row: the picks' titles in the order save, plan,
/// worth, joined by " · " (decision 32).
String happySubtitle(Set<HappyPick> picks, String Function(HappyPick pick) title) =>
    [for (final pick in HappyPick.values) if (picks.contains(pick)) title(pick)].join(' · ');
