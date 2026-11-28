import 'category.dart';
import 'entry.dart';

/// Feature 3, quick amounts: at most this many chips under the Add sheet's
/// amount.
const quickAmountsMax = 3;

/// The last [limit] different amounts spent in [category], newest first (by
/// when each was added), in [currency] only. Integer minor units; no doubles.
/// Empty when the category has no spends yet.
List<int> quickAmounts(
  Iterable<Entry> entries, {
  required SpendCategory category,
  required String currency,
  int limit = quickAmountsMax,
}) {
  final spends = [
    for (final e in entries)
      if (e.type == EntryType.spent &&
          e.category == category &&
          e.currency == currency)
        e,
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final amounts = <int>[];
  for (final e in spends) {
    if (amounts.length == limit) break;
    if (!amounts.contains(e.amountMinor)) amounts.add(e.amountMinor);
  }
  return amounts;
}
