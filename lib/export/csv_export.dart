// "Export my data" as a spreadsheet file (CSV).
//
// UTF-8 with a byte-order mark (so Excel reads Thai and emoji), RFC 4180 quoting, CRLF line
// ends, and every cell protected against spreadsheet formulas. Amounts use plainAmount ("."
// as the mark, no grouping), so the file reads the same in every locale.

import '../money/money.dart';

/// The byte-order mark, written out so it's visible here.
const String csvBom = '\uFEFF';

const List<String> csvColumns = [
  'date',
  'type',
  'amount',
  'currency',
  'category',
  'feeling',
  'note',
  'goal',
];

/// One entry as it goes into the file. Ids, not labels, for type, category and feeling.
class CsvRow {
  const CsvRow({
    required this.localDate,
    required this.type,
    required this.amountMinor,
    required this.currency,
    this.category,
    this.feeling,
    required this.note,
    this.goalName,
  });

  /// The entry's local_date, "YYYY-MM-DD".
  final String localDate;

  /// "spent", "saved" or "withdraw".
  final String type;
  final int amountMinor;
  final String currency;

  /// A category id ("food"); spends only.
  final String? category;

  /// "worth_it", "not_sure" or "not_really"; spends only.
  final String? feeling;
  final String note;

  /// The goal's name for a save or a withdrawal attached to a goal; empty otherwise.
  final String? goalName;
}

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// A spreadsheet runs a cell starting with = + - @, a tab or a CR as a formula, so such a cell
/// gets one ' in front. Apostrophes already at the start count, so an importer that removes
/// exactly one restores the original both ways.
final _formulaStart = RegExp(r"^'*[=+\-@\t\r]");

String neutralizeCell(String cell) => _formulaStart.hasMatch(cell) ? "'$cell" : cell;

final _needsQuotes = RegExp('[",\r\n]');

/// RFC 4180: a cell with a quote, a comma or a line break is quoted, with quotes doubled.
/// Formula starts are neutralized first.
String csvCell(String value) {
  final safe = neutralizeCell(value);
  return _needsQuotes.hasMatch(safe) ? '"${safe.replaceAll('"', '""')}"' : safe;
}

/// The whole file: the BOM, the header, then one line per row in the order given.
String buildCsv(List<CsvRow> rows) {
  final lines = <String>[csvColumns.join(',')];
  for (final r in rows) {
    if (!_isoDate.hasMatch(r.localDate)) {
      throw ArgumentError.value(r.localDate, 'localDate', 'must be YYYY-MM-DD');
    }
    if (r.type != 'spent' && r.type != 'saved' && r.type != 'withdraw') {
      throw ArgumentError.value(r.type, 'type', 'must be "spent", "saved" or "withdraw"');
    }
    lines.add(
      [
        r.localDate,
        r.type,
        plainAmount(r.amountMinor, r.currency),
        r.currency,
        r.category ?? '',
        r.feeling ?? '',
        r.note,
        r.goalName ?? '',
      ].map(csvCell).join(','),
    );
  }
  return '$csvBom${lines.join('\r\n')}\r\n';
}

/// The file's name for the phone's local date: piggybow-2026-11-28.csv.
String csvFileName(DateTime localToday) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'piggybow-${localToday.year.toString().padLeft(4, '0')}-${two(localToday.month)}-${two(localToday.day)}.csv';
}
