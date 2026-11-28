import '../journal/entry.dart';

/// "How did yesterday feel?" on Home: [yesterday]'s spends with no feeling
/// yet, in the order they were added, three at most. Only the person's own:
/// a repeat's spends weren't noted by them, so they aren't asked about.
/// Never a count of the rest.
List<Entry> unfeltYesterday(Iterable<Entry> entries, String yesterday) => ([
  for (final e in entries)
    if (e.type == EntryType.spent && !e.auto && e.localDate == yesterday && e.feeling == null) e,
]..sort((a, b) => a.createdAt.compareTo(b.createdAt))).take(3).toList();
