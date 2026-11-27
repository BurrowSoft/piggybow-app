import 'dart:convert' show utf8;

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/export/csv_export.dart';

/// A small RFC 4180 reader for the tests: quoted cells, doubled quotes, CRLF records.
List<List<String>> readCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i += 2;
          continue;
        }
        quoted = false;
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
      i += 2;
      continue;
    } else {
      cell.write(c);
    }
    i++;
  }
  if (cell.isNotEmpty || row.isNotEmpty) rows.add([...row, cell.toString()]);
  return rows;
}

/// The file without its BOM, read back.
List<List<String>> roundTrip(List<CsvRow> rows) => readCsv(buildCsv(rows).substring(1));

CsvRow spend({String note = 'Lunch', String date = '2026-12-02'}) => CsvRow(
  localDate: date,
  type: 'spent',
  amountMinor: 12050,
  currency: 'THB',
  category: 'food',
  feeling: 'worth_it',
  note: note,
);

const header = 'date,type,amount,currency,category,feeling,note,goal';

void main() {
  test('an empty export is the BOM and the header, ending in CRLF', () {
    expect(buildCsv(const []), '\uFEFF$header\r\n');
  });

  test('the file starts with the UTF-8 BOM bytes EF BB BF', () {
    expect(utf8.encode(buildCsv(const [])).take(3), [0xEF, 0xBB, 0xBF]);
  });

  test('a spend and a save, exactly', () {
    final csv = buildCsv([
      spend(),
      const CsvRow(
        localDate: '2026-12-03',
        type: 'saved',
        amountMinor: 50000,
        currency: 'THB',
        note: '',
        goalName: 'Trip to Chiang Mai',
      ),
      const CsvRow(localDate: '2026-12-04', type: 'saved', amountMinor: 1200, currency: 'JPY', note: 'Coins'),
    ]);
    expect(
      csv,
      '\uFEFF$header\r\n'
      '2026-12-02,spent,120.50,THB,food,worth_it,Lunch,\r\n'
      '2026-12-03,saved,500.00,THB,,,,Trip to Chiang Mai\r\n'
      '2026-12-04,saved,1200,JPY,,,Coins,\r\n',
    );
  });

  test('every line ends in CRLF; no bare LF outside a quoted note', () {
    final csv = buildCsv([spend(), spend(note: 'Bus')]);
    expect(csv.replaceAll('\r\n', '').contains('\n'), isFalse);
    expect(csv.endsWith('\r\n'), isTrue);
  });

  test('rows keep the order they are given in', () {
    final rows = roundTrip([spend(date: '2026-12-09'), spend(date: '2026-12-01'), spend(date: '2026-12-05')]);
    expect(rows.skip(1).map((r) => r.first), ['2026-12-09', '2026-12-01', '2026-12-05']);
  });

  group('RFC 4180: notes come back exactly', () {
    for (final note in [
      'Coffee, cake',
      'The "big" shop',
      'Line one\nline two',
      'Line one\r\nline two',
      '"',
      ',',
      '',
      '  spaces kept  ',
    ]) {
      test(note.replaceAll('\n', r'\n').replaceAll('\r', r'\r'), () {
        final rows = roundTrip([spend(note: note)]);
        expect(rows.length, 2);
        expect(rows[1].length, 8);
        expect(rows[1][6], note);
      });
    }
  });

  group('formula starts get one apostrophe', () {
    for (final start in ['=', '+', '-', '@', '\t', '\r']) {
      test('a note starting with ${start == '\t' ? 'a tab' : start == '\r' ? 'a CR' : start}', () {
        final note = '${start}SUM(A1:A9)';
        expect(roundTrip([spend(note: note)])[1][6], "'$note");
      });
    }

    test('"=" in the middle of a note is left alone', () {
      expect(roundTrip([spend(note: 'a=b')])[1][6], 'a=b');
    });

    test('apostrophes already there are counted, so one removal restores the note', () {
      expect(roundTrip([spend(note: "'=x")])[1][6], "''=x");
      expect(roundTrip([spend(note: "it's fine")])[1][6], "it's fine");
      expect(roundTrip([spend(note: "'hello")])[1][6], "'hello");
    });

    test("the goal's name is protected the same way", () {
      const row = CsvRow(
        localDate: '2026-12-03',
        type: 'saved',
        amountMinor: 100,
        currency: 'USD',
        note: '',
        goalName: '=HYPERLINK("x")',
      );
      expect(roundTrip([row])[1][7], '\'=HYPERLINK("x")');
    });
  });

  test('80-character notes made of multi-part characters come back exactly', () {
    // Each unit is one character as people see it, made of several code points.
    for (final unit in ['👨\u200D👩\u200D👧', 'ก้', '🇹🇭', 'e\u0301', '👍🏽']) {
      final note = List.filled(80, unit).join();
      expect(roundTrip([spend(note: note)])[1][6], note, reason: unit);
    }
  });

  test('amounts use "." and no grouping, whatever the currency', () {
    final rows = roundTrip([
      const CsvRow(localDate: '2026-12-02', type: 'spent', amountMinor: 999999999999, currency: 'EUR', category: 'other', note: ''),
      const CsvRow(localDate: '2026-12-02', type: 'spent', amountMinor: 5, currency: 'USD', category: 'other', note: ''),
      const CsvRow(localDate: '2026-12-02', type: 'spent', amountMinor: 1500000, currency: 'VND', category: 'other', note: ''),
    ]);
    expect(rows.skip(1).map((r) => r[2]), ['9999999999.99', '0.05', '1500000']);
  });

  test('a malformed date, an unknown type or a negative amount throws', () {
    expect(() => buildCsv([spend(date: '2026-12-2')]), throwsArgumentError);
    expect(() => buildCsv([spend(date: '02/12/2026')]), throwsArgumentError);
    expect(
      () => buildCsv([const CsvRow(localDate: '2026-12-02', type: 'spend', amountMinor: 1, currency: 'USD', note: '')]),
      throwsArgumentError,
    );
    expect(
      () => buildCsv([const CsvRow(localDate: '2026-12-02', type: 'spent', amountMinor: -1, currency: 'USD', note: '')]),
      throwsArgumentError,
    );
  });

  test('the file name uses the local date', () {
    expect(csvFileName(DateTime(2026, 11, 28, 23, 59)), 'piggybow-2026-11-28.csv');
    expect(csvFileName(DateTime(2027, 1, 2)), 'piggybow-2027-01-02.csv');
  });
}
